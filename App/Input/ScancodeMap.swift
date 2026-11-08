import Foundation

/// USB HID キーボード使用コード（UIKey.keyCode の rawValue）→ RDP スキャンコード（セット1）の変換表。
/// 拡張キー（E0 プレフィックス）は 0x100 を付与して表す（FreeRDP の RDP_SCANCODE と同じ形式）。
///
/// UIKit に依存しないので単体テストしやすい。
enum ScancodeMap {
    static let extended: UInt16 = 0x100

    // 特殊キー（補助キーバーなどから使う）
    static let escape: UInt16 = 0x01
    static let backspace: UInt16 = 0x0E
    static let tab: UInt16 = 0x0F
    static let enter: UInt16 = 0x1C
    static let leftControl: UInt16 = 0x1D
    static let leftShift: UInt16 = 0x2A
    static let leftAlt: UInt16 = 0x38
    static let delete: UInt16 = 0x53 | extended
    static let leftWindows: UInt16 = 0x5B | extended
    static let up: UInt16 = 0x48 | extended
    static let down: UInt16 = 0x50 | extended
    static let left: UInt16 = 0x4B | extended
    static let right: UInt16 = 0x4D | extended
    static let home: UInt16 = 0x47 | extended
    static let end: UInt16 = 0x4F | extended
    static let pageUp: UInt16 = 0x49 | extended
    static let pageDown: UInt16 = 0x51 | extended

    /// F1〜F12（n は 1〜12）
    static func function(_ n: Int) -> UInt16? {
        switch n {
        case 1...10: return UInt16(0x3B + n - 1)
        case 11: return 0x57
        case 12: return 0x58
        default: return nil
        }
    }

    /// HID 使用コードからスキャンコードを返す。対応しないキーは nil。
    static func scancode(forHIDUsage usage: Int) -> UInt16? {
        table[usage]
    }

    private static let table: [Int: UInt16] = {
        var t: [Int: UInt16] = [:]

        // 英字 a〜z (HID 0x04〜0x1D)
        let letters: [UInt16] = [
            0x1E, 0x30, 0x2E, 0x20, 0x12, 0x21, 0x22, 0x23, 0x17, 0x24, 0x25, 0x26, 0x32, // a〜m
            0x31, 0x18, 0x19, 0x10, 0x13, 0x1F, 0x14, 0x16, 0x2F, 0x11, 0x2D, 0x15, 0x2C, // n〜z
        ]
        for (i, code) in letters.enumerated() { t[0x04 + i] = code }

        // 数字 1〜0 (HID 0x1E〜0x27) → 0x02〜0x0B
        for i in 0..<10 { t[0x1E + i] = UInt16(0x02 + i) }

        t[0x28] = enter
        t[0x29] = escape
        t[0x2A] = backspace
        t[0x2B] = tab
        t[0x2C] = 0x39 // Space
        t[0x2D] = 0x0C // - (JIS: -)
        t[0x2E] = 0x0D // = (JIS: ^)
        t[0x2F] = 0x1A // [ (JIS: @)
        t[0x30] = 0x1B // ] (JIS: [)
        t[0x31] = 0x2B // \ (JIS: ])
        t[0x32] = 0x2B // Non-US # (JIS: ])
        t[0x33] = 0x27 // ; (JIS: ;)
        t[0x34] = 0x28 // ' (JIS: :)
        t[0x35] = 0x29 // ` (JIS: 半角/全角)
        t[0x36] = 0x33 // ,
        t[0x37] = 0x34 // .
        t[0x38] = 0x35 // /
        t[0x39] = 0x3A // Caps Lock

        // F1〜F12 (HID 0x3A〜0x45)
        for n in 1...12 { t[0x3A + n - 1] = function(n) }

        t[0x46] = 0x37 | extended // Print Screen
        t[0x47] = 0x46            // Scroll Lock
        t[0x48] = 0x46 | extended // Pause
        t[0x49] = 0x52 | extended // Insert
        t[0x4A] = home
        t[0x4B] = pageUp
        t[0x4C] = delete          // Delete (Forward)
        t[0x4D] = end
        t[0x4E] = pageDown
        t[0x4F] = right
        t[0x50] = left
        t[0x51] = down
        t[0x52] = up

        // テンキー
        t[0x53] = 0x45            // Num Lock
        t[0x54] = 0x35 | extended // KP /
        t[0x55] = 0x37            // KP *
        t[0x56] = 0x4A            // KP -
        t[0x57] = 0x4E            // KP +
        t[0x58] = 0x1C | extended // KP Enter
        let keypad: [UInt16] = [0x4F, 0x50, 0x51, 0x4B, 0x4C, 0x4D, 0x47, 0x48, 0x49, 0x52] // 1〜9, 0
        for (i, code) in keypad.enumerated() { t[0x59 + i] = code }
        t[0x63] = 0x53            // KP .
        t[0x64] = 0x56            // Non-US \ (ISO配列)
        t[0x65] = 0x5D | extended // Application (メニュー)

        // 日本語キーボード
        t[0x87] = 0x73 // International1: ろ / _
        t[0x88] = 0x70 // International2: カタカナ/ひらがな
        t[0x89] = 0x7D // International3: ¥
        t[0x8A] = 0x79 // International4: 変換
        t[0x8B] = 0x7B // International5: 無変換
        t[0x90] = 0x70 // LANG1: Mac の「かな」キー → ひらがな
        t[0x91] = 0x29 // LANG2: Mac の「英数」キー → 半角/全角（IMEの切り替え）

        // 修飾キー
        t[0xE0] = leftControl
        t[0xE1] = leftShift
        t[0xE2] = leftAlt          // Option → Alt
        t[0xE3] = leftWindows      // Command → Windows
        t[0xE4] = 0x1D | extended  // Right Control
        t[0xE5] = 0x36             // Right Shift
        t[0xE6] = 0x38 | extended  // Right Option → Right Alt
        t[0xE7] = 0x5C | extended  // Right Command → Right Windows

        return t
    }()
}
