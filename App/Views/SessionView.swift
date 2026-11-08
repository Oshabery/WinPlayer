import GameController
import SwiftData
import SwiftUI

/// リモートデスクトップの全画面表示
struct SessionView: View {
    let connection: Connection

    @Environment(\.dismiss) private var dismiss

    @State private var session = RDPSession()
    @State private var viewHandle = RemoteViewHandle()
    @State private var viewSize: CGSize = .zero
    @State private var started = false

    @State private var askPassword = false
    @State private var passwordInput = ""
    /// 保存されていない場合に、このセッションの間だけ使うパスワード
    @State private var sessionPassword: String?

    @State private var keyboardActive = false
    @State private var toolbarExpanded = true

    var body: some View {
        GeometryReader { geo in
            ZStack {
                Color.black

                RemoteDesktopRepresentable(session: session, handle: viewHandle, keyboardActive: $keyboardActive)
                    .id(ObjectIdentifier(session)) // 再接続時はビューを作り直す
                    .opacity(session.state == .connected ? 1 : 0.3)

                statusOverlay

                VStack {
                    SessionToolbar(
                        expanded: $toolbarExpanded,
                        keyboardActive: $keyboardActive,
                        onCtrlAltDel: { viewHandle.view?.keyboardInput.sendCtrlAltDelete() },
                        onResetZoom: { viewHandle.view?.resetZoom() },
                        onDisconnect: close
                    )
                    Spacer()
                }
                .padding(.top, 8)
            }
            .onAppear {
                viewSize = geo.size
                startIfNeeded()
            }
        }
        .ignoresSafeArea()
        .statusBarHidden()
        .persistentSystemOverlays(.hidden)
        .onChange(of: session.state) { _, newState in
            if newState == .connected {
                connection.lastConnectedAt = Date()
                // ハードウェアキーボードがつながっていれば、すぐにキー入力を受け付ける
                if GCKeyboard.coalesced != nil { keyboardActive = true }
            }
        }
        .alert("パスワードを入力", isPresented: $askPassword) {
            SecureField("パスワード", text: $passwordInput)
            Button("接続") {
                sessionPassword = passwordInput
                passwordInput = ""
                reconnect()
            }
            Button("キャンセル", role: .cancel) { close() }
        } message: {
            Text("\(connection.username.isEmpty ? "" : connection.username + " の")パスワードを入力してください。")
        }
        .sheet(item: certificateBinding) { info in
            CertificateSheet(info: info) { accept, remember in
                session.answerCertificate(accept: accept, remember: remember)
                if !accept { close() }
            }
            .interactiveDismissDisabled()
        }
    }

    // MARK: - 状態表示

    @ViewBuilder
    private var statusOverlay: some View {
        switch session.state {
        case .idle, .connecting:
            VStack(spacing: 16) {
                ProgressView().controlSize(.large).tint(.white)
                Text("\(connection.displayName) に接続しています…")
                    .foregroundStyle(.white)
                Button("キャンセル", action: close)
                    .buttonStyle(.bordered)
                    .tint(.white)
            }
        case .connected:
            EmptyView()
        case .disconnected:
            messageCard(title: "切断されました", message: "リモートセッションが終了しました。", isAuth: false)
        case let .failed(message, isAuth):
            messageCard(title: "接続できませんでした", message: message, isAuth: isAuth)
        }
    }

    private func messageCard(title: String, message: String, isAuth: Bool) -> some View {
        VStack(spacing: 16) {
            Image(systemName: isAuth ? "key.slash" : "exclamationmark.triangle")
                .font(.system(size: 40))
            Text(title).font(.title2.bold())
            Text(message)
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            HStack {
                Button("閉じる", action: close)
                    .buttonStyle(.bordered)
                if isAuth {
                    Button("パスワードを入力") { askPassword = true }
                        .buttonStyle(.borderedProminent)
                } else {
                    Button("再接続", action: reconnect)
                        .buttonStyle(.borderedProminent)
                }
            }
        }
        .padding(32)
        .frame(maxWidth: 460)
        .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 20))
    }

    private var certificateBinding: Binding<CertificateInfo?> {
        Binding(
            get: { session.pendingCertificate },
            set: { newValue in
                if newValue == nil, session.pendingCertificate != nil {
                    session.answerCertificate(accept: false, remember: false)
                }
            }
        )
    }

    // MARK: - 接続処理

    private func startIfNeeded() {
        guard !started else { return }
        started = true
        connect(using: session)
    }

    private func connect(using target: RDPSession) {
        let password = sessionPassword ?? KeychainStore.password(for: connection.id) ?? ""
        if password.isEmpty {
            askPassword = true
            return
        }

        let size = connection.resolution.size(fitting: viewSize)
        target.connect(ConnectParameters(
            host: connection.host,
            port: connection.port,
            username: connection.username,
            password: password,
            domain: connection.domain,
            width: size.width,
            height: size.height,
            keyboard: connection.keyboard,
            useNLA: connection.useNLA
        ))
    }

    private func reconnect() {
        session.disconnect()
        keyboardActive = false
        let fresh = RDPSession()
        session = fresh
        connect(using: fresh)
    }

    private func close() {
        session.disconnect()
        dismiss()
    }
}

/// SwiftUI から UIKit のビューを操作するための参照
final class RemoteViewHandle {
    weak var view: RemoteDesktopView?
}

struct RemoteDesktopRepresentable: UIViewRepresentable {
    let session: RDPSession
    let handle: RemoteViewHandle
    @Binding var keyboardActive: Bool

    func makeUIView(context: Context) -> RemoteDesktopView {
        let view = RemoteDesktopView(session: session)
        handle.view = view
        return view
    }

    func updateUIView(_ view: RemoteDesktopView, context: Context) {
        handle.view = view
        // ウィンドウに載る前は first responder になれないので次のループで反映する
        let wantsKeyboard = keyboardActive
        DispatchQueue.main.async {
            if wantsKeyboard, !view.isFirstResponder {
                view.becomeFirstResponder()
            } else if !wantsKeyboard, view.isFirstResponder {
                _ = view.resignFirstResponder()
            }
        }
    }

    static func dismantleUIView(_ view: RemoteDesktopView, coordinator: ()) {
        view.keyboardInput.releaseAllKeys()
    }
}

/// 画面上部のフローティングツールバー
private struct SessionToolbar: View {
    @Binding var expanded: Bool
    @Binding var keyboardActive: Bool
    let onCtrlAltDel: () -> Void
    let onResetZoom: () -> Void
    let onDisconnect: () -> Void

    var body: some View {
        HStack(spacing: 4) {
            if expanded {
                toolButton("keyboard", label: "キーボード", active: keyboardActive) { keyboardActive.toggle() }
                toolButton("command", label: "Ctrl+Alt+Del", active: false, action: onCtrlAltDel)
                toolButton("arrow.down.right.and.arrow.up.left", label: "全体を表示", active: false, action: onResetZoom)
                toolButton("xmark.circle", label: "切断", active: false, action: onDisconnect)
            }
            Button {
                withAnimation(.snappy) { expanded.toggle() }
            } label: {
                Image(systemName: expanded ? "chevron.up" : "chevron.down")
                    .frame(width: 36, height: 36)
            }
            .accessibilityLabel(expanded ? "ツールバーを隠す" : "ツールバーを表示")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .background(.ultraThinMaterial, in: Capsule())
        .foregroundStyle(.primary)
    }

    private func toolButton(_ icon: String, label: String, active: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: icon)
                .frame(width: 40, height: 36)
                .background(active ? Color.accentColor.opacity(0.3) : .clear, in: RoundedRectangle(cornerRadius: 8))
        }
        .accessibilityLabel(label)
        .help(label)
    }
}
