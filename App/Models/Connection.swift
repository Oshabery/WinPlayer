import Foundation
import SwiftData

/// リモートデスクトップの解像度設定
enum ResolutionMode: String, CaseIterable, Codable, Identifiable {
    case fitScreen
    case hd = "1280x800"
    case fullHD = "1920x1080"
    case qhd = "2560x1440"

    var id: String { rawValue }

    var label: String {
        switch self {
        case .fitScreen: return "画面に合わせる"
        case .hd: return "1280 × 800"
        case .fullHD: return "1920 × 1080"
        case .qhd: return "2560 × 1440"
        }
    }

    /// 実際に要求するサイズ。fitScreen の場合は表示領域（ポイント単位）を使う。
    /// RDP の制約に合わせて幅・高さを 4 の倍数、200〜8192 に丸める。
    func size(fitting viewSize: CGSize) -> (width: UInt32, height: UInt32) {
        let raw: (Double, Double)
        switch self {
        case .fitScreen: raw = (Double(viewSize.width), Double(viewSize.height))
        case .hd: raw = (1280, 800)
        case .fullHD: raw = (1920, 1080)
        case .qhd: raw = (2560, 1440)
        }
        func clamp(_ v: Double) -> UInt32 {
            let n = min(max(Int(v.rounded(.down)), 200), 8192)
            return UInt32(n - n % 4)
        }
        return (clamp(raw.0), clamp(raw.1))
    }
}

/// Windows 側に伝えるキーボード配列
enum KeyboardLayoutOption: String, CaseIterable, Codable, Identifiable {
    case japanese
    case us

    var id: String { rawValue }

    var label: String {
        switch self {
        case .japanese: return "日本語 (JIS)"
        case .us: return "英語 (US)"
        }
    }

    /// (KeyboardLayout, KeyboardType, KeyboardSubType)
    var rdpValues: (layout: UInt32, type: UInt32, subtype: UInt32) {
        switch self {
        case .japanese: return (0x0000_0411, 7, 2)
        case .us: return (0x0000_0409, 4, 0)
        }
    }
}

@Model
final class Connection {
    var id: UUID
    var name: String
    var host: String
    var port: Int
    var username: String
    var domain: String
    var resolutionRaw: String
    var keyboardRaw: String
    var useNLA: Bool
    var createdAt: Date
    var lastConnectedAt: Date?

    init(name: String = "",
         host: String = "",
         port: Int = HostAddress.defaultPort,
         username: String = "",
         domain: String = "",
         resolution: ResolutionMode = .fitScreen,
         keyboard: KeyboardLayoutOption = .japanese,
         useNLA: Bool = true) {
        self.id = UUID()
        self.name = name
        self.host = host
        self.port = port
        self.username = username
        self.domain = domain
        self.resolutionRaw = resolution.rawValue
        self.keyboardRaw = keyboard.rawValue
        self.useNLA = useNLA
        self.createdAt = Date()
    }

    var resolution: ResolutionMode {
        get { ResolutionMode(rawValue: resolutionRaw) ?? .fitScreen }
        set { resolutionRaw = newValue.rawValue }
    }

    var keyboard: KeyboardLayoutOption {
        get { KeyboardLayoutOption(rawValue: keyboardRaw) ?? .japanese }
        set { keyboardRaw = newValue.rawValue }
    }

    var address: HostAddress { HostAddress(host: host, port: port) }

    /// 一覧に表示する名前（未設定ならアドレス）
    var displayName: String { name.isEmpty ? address.displayString : name }
}
