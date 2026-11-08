import SwiftUI

/// サーバー証明書の確認画面
struct CertificateSheet: View {
    let info: CertificateInfo
    let onAnswer: (_ accept: Bool, _ remember: Bool) -> Void

    @State private var remember = true

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label {
                        Text(info.changed
                             ? "この PC の証明書が、以前に信頼したものから変わっています。PC を再設定した覚えがなければ、なりすましの可能性があります。"
                             : "この PC の証明書を確認できませんでした。自宅や社内の PC で使われる自己署名証明書では通常このように表示されます。接続先が正しいことを確認してください。")
                    } icon: {
                        Image(systemName: info.changed ? "exclamationmark.shield.fill" : "lock.shield")
                            .foregroundStyle(info.changed ? .red : .orange)
                    }
                }

                Section("証明書") {
                    LabeledContent("接続先", value: "\(info.host):\(info.port)")
                    if !info.commonName.isEmpty { LabeledContent("名前", value: info.commonName) }
                    if !info.issuer.isEmpty { LabeledContent("発行者", value: info.issuer) }
                    VStack(alignment: .leading, spacing: 4) {
                        Text("フィンガープリント").font(.subheadline).foregroundStyle(.secondary)
                        Text(info.fingerprint)
                            .font(.system(.footnote, design: .monospaced))
                            .textSelection(.enabled)
                    }
                }

                Section {
                    Toggle("次回から確認しない", isOn: $remember)
                }
            }
            .navigationTitle("証明書の確認")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onAnswer(false, false) }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("接続する") { onAnswer(true, remember) }
                }
            }
        }
    }
}
