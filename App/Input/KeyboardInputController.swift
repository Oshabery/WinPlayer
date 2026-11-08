import UIKit

/// キーボード入力をRDPのキーイベントに変換する。
///
/// - ハードウェアキーボード: 物理キーの位置（HID使用コード）をスキャンコードに変換して送る。
///   Windows側の IME・キーボード配列がそのまま使える。Command は Windows キー、Option は Alt になる。
/// - ソフトウェアキーボード: 入力された文字を Unicode として送る。
/// - 補助キーバー: Ctrl / Alt / Win は「次のキーまで押したまま」にする固定（スティッキー）キー。
final class KeyboardInputController {
    private weak var sink: RemoteInputSink?

    /// 押下中のスキャンコード（キーが押されたまま残らないように管理する）
    private var pressed: Set<UInt16> = []

    /// 補助キーバーで選ばれている修飾キー
    private(set) var stickyModifiers: Set<UInt16> = [] {
        didSet { onStickyModifiersChanged?(stickyModifiers) }
    }
    var onStickyModifiersChanged: ((Set<UInt16>) -> Void)?

    init(sink: RemoteInputSink) {
        self.sink = sink
    }

    // MARK: - ハードウェアキーボード

    /// 処理しなかった press を返す
    func pressesBegan(_ presses: Set<UIPress>) -> Set<UIPress> {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let scancode = scancode(for: press) else {
                unhandled.insert(press)
                continue
            }
            pressed.insert(scancode)
            sink?.key(scancode, down: true)
        }
        return unhandled
    }

    func pressesEnded(_ presses: Set<UIPress>) -> Set<UIPress> {
        var unhandled = Set<UIPress>()
        for press in presses {
            guard let scancode = scancode(for: press) else {
                unhandled.insert(press)
                continue
            }
            if pressed.remove(scancode) != nil {
                sink?.key(scancode, down: false)
            }
        }
        return unhandled
    }

    private func scancode(for press: UIPress) -> UInt16? {
        guard let key = press.key else { return nil }
        return ScancodeMap.scancode(forHIDUsage: key.keyCode.rawValue)
    }

    /// 押されたままのキーをすべて離す（フォーカスを失ったときなど）
    func releaseAllKeys() {
        for scancode in pressed {
            sink?.key(scancode, down: false)
        }
        pressed.removeAll()
    }

    // MARK: - ソフトウェアキーボード・補助キーバー

    func toggleSticky(_ modifier: UInt16) {
        if stickyModifiers.contains(modifier) {
            stickyModifiers.remove(modifier)
        } else {
            stickyModifiers.insert(modifier)
        }
    }

    /// キーを1回押して離す。固定中の修飾キーがあれば一緒に押す。
    func tap(_ scancode: UInt16, extraModifiers: [UInt16] = []) {
        guard let sink else { return }
        let modifiers = Array(stickyModifiers).sorted() + extraModifiers
        for m in modifiers { sink.key(m, down: true) }
        sink.key(scancode, down: true)
        sink.key(scancode, down: false)
        for m in modifiers.reversed() { sink.key(m, down: false) }
        if !stickyModifiers.isEmpty { stickyModifiers.removeAll() }
    }

    func insertText(_ text: String) {
        guard let sink else { return }

        if text == "\n" {
            tap(ScancodeMap.enter)
            return
        }
        if text == "\t" {
            tap(ScancodeMap.tab)
            return
        }

        // 修飾キー固定中の英数字はショートカット（Ctrl+C など）としてキーで送る
        if !stickyModifiers.isEmpty, let mapped = Self.asciiScancode(for: text) {
            tap(mapped.0, extraModifiers: mapped.1 ? [ScancodeMap.leftShift] : [])
            return
        }

        for unit in text.utf16 {
            sink.unicode(unit, down: true)
            sink.unicode(unit, down: false)
        }
    }

    /// Ctrl + Alt + Delete を送る
    func sendCtrlAltDelete() {
        guard let sink else { return }
        let keys = [ScancodeMap.leftControl, ScancodeMap.leftAlt, ScancodeMap.delete]
        for k in keys { sink.key(k, down: true) }
        for k in keys.reversed() { sink.key(k, down: false) }
    }

    /// 英字・数字1文字 → (スキャンコード, Shiftが必要か)
    static func asciiScancode(for text: String) -> (UInt16, Bool)? {
        guard let scalar = text.unicodeScalars.first, text.unicodeScalars.count == 1,
              scalar.isASCII else { return nil }
        let v = Int(scalar.value)
        switch scalar {
        case "a"..."z":
            return ScancodeMap.scancode(forHIDUsage: 0x04 + v - 0x61).map { ($0, false) }
        case "A"..."Z":
            return ScancodeMap.scancode(forHIDUsage: 0x04 + v - 0x41).map { ($0, true) }
        case "1"..."9":
            return ScancodeMap.scancode(forHIDUsage: 0x1E + v - 0x31).map { ($0, false) }
        case "0":
            return ScancodeMap.scancode(forHIDUsage: 0x27).map { ($0, false) }
        case " ":
            return (0x39, false)
        default:
            return nil
        }
    }
}
