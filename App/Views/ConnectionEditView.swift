import SwiftData
import SwiftUI

/// 接続先の追加・編集
struct ConnectionEditView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss

    /// nil の場合は新規作成
    let connection: Connection?

    @State private var name = ""
    @State private var address = ""
    @State private var username = ""
    @State private var domain = ""
    @State private var password = ""
    @State private var savePassword = true
    @State private var resolution: ResolutionMode = .fitScreen
    @State private var keyboard: KeyboardLayoutOption = .japanese
    @State private var useNLA = true
    @State private var loaded = false

    private var parsedAddress: HostAddress? { HostAddress(parsing: address) }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("PC 名または IP アドレス（例: 192.168.1.10）", text: $address)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .keyboardType(.URL)
                    TextField("表示名（省略可）", text: $name)
                } header: {
                    Text("接続先")
                } footer: {
                    if !address.isEmpty && parsedAddress == nil {
                        Text("アドレスの形式が正しくありません。「ホスト名」または「ホスト名:ポート」で入力してください。")
                            .foregroundStyle(.red)
                    }
                }

                Section("ユーザー") {
                    TextField("ユーザー名（Microsoft アカウントはメールアドレス）", text: $username)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .textContentType(.username)
                    SecureField("パスワード", text: $password)
                        .textContentType(.password)
                    Toggle("パスワードを保存する", isOn: $savePassword)
                    TextField("ドメイン（省略可）", text: $domain)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                Section("表示と入力") {
                    Picker("解像度", selection: $resolution) {
                        ForEach(ResolutionMode.allCases) { Text($0.label).tag($0) }
                    }
                    Picker("キーボード配列", selection: $keyboard) {
                        ForEach(KeyboardLayoutOption.allCases) { Text($0.label).tag($0) }
                    }
                }

                Section {
                    Toggle("ネットワークレベル認証 (NLA)", isOn: $useNLA)
                } header: {
                    Text("セキュリティ")
                } footer: {
                    Text("通常はオンのままにしてください。古いサーバーで接続できない場合のみオフにします。")
                }
            }
            .navigationTitle(connection == nil ? "PC を追加" : "接続先を編集")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { save() }
                        .disabled(parsedAddress == nil)
                }
            }
            .onAppear(perform: load)
        }
    }

    private func load() {
        guard !loaded else { return }
        loaded = true
        guard let c = connection else { return }
        name = c.name
        address = c.address.displayString
        username = c.username
        domain = c.domain
        resolution = c.resolution
        keyboard = c.keyboard
        useNLA = c.useNLA
        let stored = KeychainStore.password(for: c.id)
        password = stored ?? ""
        savePassword = stored != nil || c.username.isEmpty
    }

    private func save() {
        guard let addr = parsedAddress else { return }
        let target: Connection
        if let connection {
            target = connection
        } else {
            target = Connection()
            modelContext.insert(target)
        }

        // 接続先が変わったら、以前の証明書の信頼は引き継がない
        if target.host != addr.host || target.port != addr.port {
            CertificateTrust.forget(host: target.host, port: UInt16(clamping: target.port))
        }

        target.name = name.trimmingCharacters(in: .whitespaces)
        target.host = addr.host
        target.port = addr.port
        target.username = username.trimmingCharacters(in: .whitespaces)
        target.domain = domain.trimmingCharacters(in: .whitespaces)
        target.resolution = resolution
        target.keyboard = keyboard
        target.useNLA = useNLA

        KeychainStore.setPassword(savePassword ? password : nil, for: target.id)
        dismiss()
    }
}
