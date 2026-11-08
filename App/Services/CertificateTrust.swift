import Foundation

/// サーバー証明書の情報（ユーザーへの確認ダイアログに表示する）
struct CertificateInfo: Identifiable, Equatable {
    let id = UUID()
    let host: String
    let port: UInt16
    let commonName: String
    let subject: String
    let issuer: String
    let fingerprint: String
    /// 以前信頼した証明書から変わっている
    let changed: Bool
}

/// 信頼済み証明書のフィンガープリントを「host:port」単位で保存する。
/// FreeRDP 自身の known_hosts は使わず、アプリ側でこれを判定する。
enum CertificateTrust {
    private static let key = "trustedCertificates"

    static func storedFingerprint(host: String, port: UInt16) -> String? {
        let all = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        return all[entryKey(host: host, port: port)]
    }

    static func isTrusted(host: String, port: UInt16, fingerprint: String) -> Bool {
        storedFingerprint(host: host, port: port)?.caseInsensitiveCompare(fingerprint) == .orderedSame
    }

    static func trust(host: String, port: UInt16, fingerprint: String) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        all[entryKey(host: host, port: port)] = fingerprint
        UserDefaults.standard.set(all, forKey: key)
    }

    static func forget(host: String, port: UInt16) {
        var all = UserDefaults.standard.dictionary(forKey: key) as? [String: String] ?? [:]
        all.removeValue(forKey: entryKey(host: host, port: port))
        UserDefaults.standard.set(all, forKey: key)
    }

    private static func entryKey(host: String, port: UInt16) -> String {
        "\(host.lowercased()):\(port)"
    }
}
