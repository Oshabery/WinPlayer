import CoreGraphics
import Foundation
import Observation

/// リモート座標（ピクセル）
struct RemotePoint: Equatable {
    var x: UInt16
    var y: UInt16
}

/// 入力の送り先。RDPSession が実装する（テストではモックに差し替え可能）。
protocol RemoteInputSink: AnyObject {
    func mouseMove(to point: RemotePoint)
    func mouseButton(_ button: DLMouseButton, down: Bool, at point: RemotePoint)
    func mouseWheel(_ delta: Int, horizontal: Bool, at point: RemotePoint)
    func key(_ scancode: UInt16, down: Bool)
    func unicode(_ codeUnit: UInt16, down: Bool)
}

/// 接続パラメーター
struct ConnectParameters {
    var host: String
    var port: Int
    var username: String
    var password: String
    var domain: String
    var width: UInt32
    var height: UInt32
    var keyboard: KeyboardLayoutOption
    var useNLA: Bool
}

/// FreeRDP の接続1本を表す。UI 状態はメインスレッドで更新される。
@Observable
final class RDPSession {
    enum State: Equatable {
        case idle
        case connecting
        case connected
        case disconnected
        case failed(message: String, isAuthFailure: Bool)
    }

    private(set) var state: State = .idle
    private(set) var desktopSize: CGSize = .zero
    /// ユーザーの確認待ちの証明書
    private(set) var pendingCertificate: CertificateInfo?

    @ObservationIgnored let framebuffer = Framebuffer()
    /// 画面が更新されたときに呼ばれる（任意のスレッド）
    @ObservationIgnored var onFrameUpdated: (() -> Void)?

    @ObservationIgnored private var handle: OpaquePointer?
    @ObservationIgnored private var retainedSelf: Unmanaged<RDPSession>?

    @ObservationIgnored private let certLock = NSLock()
    @ObservationIgnored private var certSemaphore: DispatchSemaphore?
    @ObservationIgnored private var certDecision = DL_CERT_REJECT

    deinit {
        // 通常は disconnect() 済み。念のため後始末する。
        if let handle {
            dl_session_stop(handle)
            dl_session_free(handle)
        }
    }

    // MARK: - 接続／切断

    func connect(_ params: ConnectParameters) {
        guard handle == nil else { return }

        let unmanaged = Unmanaged.passRetained(self)
        var callbacks = DLCallbacks()
        callbacks.userdata = unmanaged.toOpaque()
        callbacks.on_state = { userdata, state, error, message in
            RDPSession.from(userdata).handleState(state, error: error,
                                                  message: message.map { String(cString: $0) })
        }
        callbacks.on_resize = { userdata, width, height in
            RDPSession.from(userdata).handleResize(width: Int(width), height: Int(height))
        }
        callbacks.on_frame = { userdata, buffer, stride, width, height, x, y, w, h in
            guard let buffer else { return }
            let session = RDPSession.from(userdata)
            session.framebuffer.update(from: buffer, sourceStride: Int(stride),
                                       sourceWidth: Int(width), sourceHeight: Int(height),
                                       x: Int(x), y: Int(y), w: Int(w), h: Int(h))
            session.onFrameUpdated?()
        }
        callbacks.on_verify_certificate = { userdata, host, port, commonName, subject, issuer, fingerprint, changed in
            func str(_ p: UnsafePointer<CChar>?) -> String { p.map { String(cString: $0) } ?? "" }
            let info = CertificateInfo(host: str(host), port: port, commonName: str(commonName),
                                       subject: str(subject), issuer: str(issuer),
                                       fingerprint: str(fingerprint), changed: changed)
            return RDPSession.from(userdata).verifyCertificate(info)
        }

        guard let newHandle = dl_session_new(&callbacks) else {
            unmanaged.release()
            state = .failed(message: "接続の準備に失敗しました。", isAuthFailure: false)
            return
        }

        let kb = params.keyboard.rdpValues
        let cHost = strdup(params.host)
        let cUser = strdup(params.username)
        let cPass = strdup(params.password)
        let cDomain = strdup(params.domain)
        defer {
            // パスワードはメモリから消してから解放する
            if let cPass { memset(cPass, 0, strlen(cPass)) }
            free(cHost); free(cUser); free(cPass); free(cDomain)
        }

        var config = DLConnectConfig()
        config.host = UnsafePointer(cHost)
        config.port = UInt16(clamping: params.port)
        config.username = UnsafePointer(cUser)
        config.password = UnsafePointer(cPass)
        config.domain = UnsafePointer(cDomain)
        config.width = params.width
        config.height = params.height
        config.keyboard_layout = kb.layout
        config.keyboard_type = kb.type
        config.keyboard_subtype = kb.subtype
        config.keyboard_function_keys = 12
        config.use_nla = params.useNLA

        handle = newHandle
        retainedSelf = unmanaged
        state = .connecting

        if !dl_session_start(newHandle, &config) {
            handle = nil
            retainedSelf = nil
            dl_session_free(newHandle)
            unmanaged.release()
            state = .failed(message: "接続を開始できませんでした。", isAuthFailure: false)
        }
    }

    /// 切断する。接続スレッドの終了はバックグラウンドで待つ。
    func disconnect() {
        guard let h = handle else { return }
        handle = nil
        let retained = retainedSelf
        retainedSelf = nil

        // 証明書確認でブロック中の接続スレッドを解放する
        pendingCertificate = nil
        resolveCertificate(DL_CERT_REJECT)

        DispatchQueue.global(qos: .userInitiated).async {
            dl_session_stop(h)
            dl_session_free(h)
            retained?.release()
        }
        if state != .idle { state = .disconnected }
    }

    // MARK: - 証明書

    /// 証明書確認ダイアログへの回答（メインスレッドから呼ぶ）
    func answerCertificate(accept: Bool, remember: Bool) {
        if accept, remember, let info = pendingCertificate {
            CertificateTrust.trust(host: info.host, port: info.port, fingerprint: info.fingerprint)
        }
        pendingCertificate = nil
        resolveCertificate(accept ? DL_CERT_ACCEPT_ONCE : DL_CERT_REJECT)
    }

    /// 接続スレッドから呼ばれる。必要ならユーザーの回答が出るまでブロックする。
    private func verifyCertificate(_ info: CertificateInfo) -> DLCertDecision {
        let stored = CertificateTrust.storedFingerprint(host: info.host, port: info.port)
        if let stored, stored.caseInsensitiveCompare(info.fingerprint) == .orderedSame {
            return DL_CERT_ACCEPT_ONCE
        }

        let changed = info.changed || stored != nil
        let prompt = CertificateInfo(host: info.host, port: info.port, commonName: info.commonName,
                                     subject: info.subject, issuer: info.issuer,
                                     fingerprint: info.fingerprint, changed: changed)
        let semaphore = DispatchSemaphore(value: 0)
        certLock.lock()
        certSemaphore = semaphore
        certDecision = DL_CERT_REJECT
        certLock.unlock()

        DispatchQueue.main.async { self.pendingCertificate = prompt }
        semaphore.wait()

        certLock.lock()
        defer { certLock.unlock() }
        return certDecision
    }

    private func resolveCertificate(_ decision: DLCertDecision) {
        certLock.lock()
        defer { certLock.unlock() }
        guard let semaphore = certSemaphore else { return }
        certDecision = decision
        certSemaphore = nil
        semaphore.signal()
    }

    // MARK: - コールバック（接続スレッド）

    private static func from(_ userdata: UnsafeMutableRawPointer?) -> RDPSession {
        Unmanaged<RDPSession>.fromOpaque(userdata!).takeUnretainedValue()
    }

    private func handleState(_ dlState: DLState, error: UInt32, message: String?) {
        let newState: State
        if dlState == DL_STATE_CONNECTING {
            newState = .connecting
        } else if dlState == DL_STATE_CONNECTED {
            newState = .connected
        } else if dlState == DL_STATE_DISCONNECTED {
            newState = .disconnected
        } else {
            let isAuth = dl_error_is_auth_failure(error)
            newState = .failed(message: Self.describe(error: error, fallback: message), isAuthFailure: isAuth)
        }
        DispatchQueue.main.async {
            // 利用者が切断した後に届いた通知は無視する（disconnect() が状態を設定済み）
            // 再接続は新しい RDPSession で行うので、古い接続の通知が混ざることはない
            guard self.handle != nil else { return }
            self.state = newState
        }
    }

    private func handleResize(width: Int, height: Int) {
        framebuffer.resize(width: width, height: height)
        DispatchQueue.main.async {
            self.desktopSize = CGSize(width: width, height: height)
        }
        onFrameUpdated?()
    }

    static func describe(error: UInt32, fallback: String?) -> String {
        if dl_error_is_auth_failure(error) {
            return "ユーザー名またはパスワードが正しくありません。"
        }
        // FreeRDP の接続エラー (FREERDP_ERROR_CONNECT_CLASS = 0x0002xxxx)
        switch error {
        case 0x0002_0004, 0x0002_0005:
            return "ホスト名が見つかりません。アドレスを確認してください。"
        case 0x0002_0006, 0x0002_000D:
            return "接続できませんでした。PC の電源、リモートデスクトップの設定、ネットワークを確認してください。"
        case 0x0002_0008:
            return "安全な接続（TLS）を確立できませんでした。"
        case 0x0002_000C:
            return "セキュリティ方式の交渉に失敗しました。「ネットワークレベル認証」の設定を切り替えて試してください。"
        default:
            let detail = fallback ?? "不明なエラー"
            return "接続エラー: \(detail) (0x\(String(error, radix: 16)))"
        }
    }
}

// MARK: - 入力

extension RDPSession: RemoteInputSink {
    func mouseMove(to point: RemotePoint) {
        guard let handle else { return }
        dl_send_mouse_move(handle, point.x, point.y)
    }

    func mouseButton(_ button: DLMouseButton, down: Bool, at point: RemotePoint) {
        guard let handle else { return }
        dl_send_mouse_button(handle, button, down, point.x, point.y)
    }

    func mouseWheel(_ delta: Int, horizontal: Bool, at point: RemotePoint) {
        guard let handle, delta != 0 else { return }
        // 1回の送信は -256〜255 に収める
        var remaining = delta
        while remaining != 0 {
            let step = max(-240, min(240, remaining))
            dl_send_mouse_wheel(handle, Int16(step), horizontal, point.x, point.y)
            remaining -= step
        }
    }

    func key(_ scancode: UInt16, down: Bool) {
        guard let handle else { return }
        dl_send_key(handle, scancode, down)
    }

    func unicode(_ codeUnit: UInt16, down: Bool) {
        guard let handle else { return }
        dl_send_unicode(handle, codeUnit, down)
    }
}
