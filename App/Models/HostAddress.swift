import Foundation

/// 「host」「host:port」「[IPv6]:port」形式の入力を解析する。
struct HostAddress: Equatable {
    static let defaultPort = 3389

    var host: String
    var port: Int

    init(host: String, port: Int = HostAddress.defaultPort) {
        self.host = host
        self.port = port
    }

    /// 入力文字列を解析する。不正な場合は nil。
    init?(parsing input: String) {
        let text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return nil }

        if text.hasPrefix("[") {
            // [IPv6] または [IPv6]:port
            guard let close = text.firstIndex(of: "]") else { return nil }
            let host = String(text[text.index(after: text.startIndex)..<close])
            guard !host.isEmpty else { return nil }
            let rest = text[text.index(after: close)...]
            if rest.isEmpty {
                self.init(host: host)
            } else {
                guard rest.hasPrefix(":"), let port = Self.parsePort(rest.dropFirst()) else { return nil }
                self.init(host: host, port: port)
            }
            return
        }

        let colons = text.filter { $0 == ":" }.count
        if colons == 1 {
            let parts = text.split(separator: ":", omittingEmptySubsequences: false)
            guard !parts[0].isEmpty, let port = Self.parsePort(parts[1]) else { return nil }
            self.init(host: String(parts[0]), port: port)
        } else {
            // コロンなし（ホスト名/IPv4）または括弧なしの IPv6
            guard !text.contains(where: { $0 == " " || $0 == "/" }) else { return nil }
            self.init(host: text)
        }
    }

    /// 表示用の文字列。既定ポートの場合は省略する。
    var displayString: String {
        let h = host.contains(":") ? "[\(host)]" : host
        return port == Self.defaultPort ? h : "\(h):\(port)"
    }

    private static func parsePort<S: StringProtocol>(_ s: S) -> Int? {
        guard let p = Int(s), (1...65535).contains(p) else { return nil }
        return p
    }
}
