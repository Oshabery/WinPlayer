import UIKit

/// トラックパッド・マウス（Magic Keyboard など）の操作をそのままマウス操作として送る。
///
/// - ポインタの移動: ホバー
/// - クリック: 左ボタン、副ボタン（2本指クリック）: 右ボタン、3番目のボタン: 中ボタン
/// - 2本指スクロール／ホイール: スクロール
///
/// クリックを `.indirectPointer` のタッチとして受け取るため、
/// Info.plist の UIApplicationSupportsIndirectInputEvents を YES にしている。
final class PointerInputController: NSObject {
    private unowned let view: RemoteDesktopView
    private var sink: RemoteInputSink { view.session }

    private var pressedButton: DLMouseButton?
    private var scrollRemainder = CGPoint.zero

    init(view: RemoteDesktopView) {
        self.view = view
    }

    func install() {
        let hover = UIHoverGestureRecognizer(target: self, action: #selector(handleHover(_:)))
        view.addGestureRecognizer(hover)

        let scroll = UIPanGestureRecognizer(target: self, action: #selector(handleScroll(_:)))
        scroll.allowedScrollTypesMask = .all
        scroll.allowedTouchTypes = [] // 指のタッチは受け取らず、スクロール入力だけを受け取る
        view.addGestureRecognizer(scroll)
    }

    @objc private func handleHover(_ g: UIHoverGestureRecognizer) {
        guard g.state == .began || g.state == .changed,
              let p = view.remotePoint(for: g.location(in: view)) else { return }
        sink.mouseMove(to: p)
    }

    @objc private func handleScroll(_ g: UIPanGestureRecognizer) {
        TouchInputController.sendScroll(g, in: view, sink: sink, remainder: &scrollRemainder)
    }

    // MARK: - クリック（RemoteDesktopView の touches〜 から呼ばれる）

    /// 処理した場合は true
    func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) -> Bool {
        guard let touch = touches.first(where: { $0.type == .indirectPointer }),
              let p = view.remotePoint(for: touch.location(in: view)) else { return false }

        let mask = event?.buttonMask ?? .primary
        let button: DLMouseButton
        if mask.contains(.secondary) {
            button = DL_MOUSE_RIGHT
        } else if mask.contains(UIEvent.ButtonMask.button(3)) {
            button = DL_MOUSE_MIDDLE
        } else if event?.modifierFlags.contains(.control) == true {
            button = DL_MOUSE_RIGHT // control + クリック = 右クリック（Macと同じ）
        } else {
            button = DL_MOUSE_LEFT
        }

        if let previous = pressedButton {
            sink.mouseButton(previous, down: false, at: p)
        }
        pressedButton = button
        sink.mouseMove(to: p)
        sink.mouseButton(button, down: true, at: p)
        return true
    }

    func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) -> Bool {
        guard let touch = touches.first(where: { $0.type == .indirectPointer }),
              let p = view.remotePoint(for: touch.location(in: view)) else { return false }
        sink.mouseMove(to: p)
        return true
    }

    func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) -> Bool {
        guard let touch = touches.first(where: { $0.type == .indirectPointer }),
              let p = view.remotePoint(for: touch.location(in: view)) else { return false }
        if let button = pressedButton {
            sink.mouseButton(button, down: false, at: p)
            pressedButton = nil
        }
        return true
    }
}
