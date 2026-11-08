import UIKit

/// 指（とApple Pencil）による操作をマウス操作に変換する。
///
/// - 1本指タップ: 左クリック
/// - 2本指タップ: 右クリック
/// - 長押ししてドラッグ: 左ボタンを押したままドラッグ（範囲選択やウィンドウ移動）
/// - 1本指で動かす: マウスカーソルの移動
/// - 2本指で動かす: スクロール
/// - ピンチ: 拡大・縮小
/// - 3本指で動かす: 拡大中の表示位置の移動
final class TouchInputController: NSObject, UIGestureRecognizerDelegate {
    private unowned let view: RemoteDesktopView
    private var sink: RemoteInputSink { view.session }

    private var scrollRemainder = CGPoint.zero
    private var isDragging = false

    /// スクロール量の係数（1ノッチ = 120）
    static let wheelPerPoint: CGFloat = 2.5

    init(view: RemoteDesktopView) {
        self.view = view
    }

    func install() {
        let direct = [UITouch.TouchType.direct, .pencil].map { NSNumber(value: $0.rawValue) }

        let tap = UITapGestureRecognizer(target: self, action: #selector(handleTap(_:)))
        let twoFingerTap = UITapGestureRecognizer(target: self, action: #selector(handleTwoFingerTap(_:)))
        twoFingerTap.numberOfTouchesRequired = 2

        let longPress = UILongPressGestureRecognizer(target: self, action: #selector(handleLongPress(_:)))
        longPress.minimumPressDuration = 0.35

        let movePan = UIPanGestureRecognizer(target: self, action: #selector(handleMovePan(_:)))
        movePan.minimumNumberOfTouches = 1
        movePan.maximumNumberOfTouches = 1

        let scrollPan = UIPanGestureRecognizer(target: self, action: #selector(handleScrollPan(_:)))
        scrollPan.minimumNumberOfTouches = 2
        scrollPan.maximumNumberOfTouches = 2

        let viewportPan = UIPanGestureRecognizer(target: self, action: #selector(handleViewportPan(_:)))
        viewportPan.minimumNumberOfTouches = 3
        viewportPan.maximumNumberOfTouches = 3

        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))

        for recognizer in [tap, twoFingerTap, longPress, movePan, scrollPan, viewportPan, pinch] as [UIGestureRecognizer] {
            recognizer.allowedTouchTypes = direct
            recognizer.delegate = self
            view.addGestureRecognizer(recognizer)
        }
    }

    // MARK: - ハンドラ

    @objc private func handleTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, let p = view.remotePoint(for: g.location(in: view)) else { return }
        sink.mouseMove(to: p)
        sink.mouseButton(DL_MOUSE_LEFT, down: true, at: p)
        sink.mouseButton(DL_MOUSE_LEFT, down: false, at: p)
    }

    @objc private func handleTwoFingerTap(_ g: UITapGestureRecognizer) {
        guard g.state == .ended, let p = view.remotePoint(for: g.location(in: view)) else { return }
        sink.mouseMove(to: p)
        sink.mouseButton(DL_MOUSE_RIGHT, down: true, at: p)
        sink.mouseButton(DL_MOUSE_RIGHT, down: false, at: p)
    }

    @objc private func handleLongPress(_ g: UILongPressGestureRecognizer) {
        guard let p = view.remotePoint(for: g.location(in: view)) else { return }
        switch g.state {
        case .began:
            UIImpactFeedbackGenerator(style: .medium).impactOccurred()
            sink.mouseMove(to: p)
            sink.mouseButton(DL_MOUSE_LEFT, down: true, at: p)
            isDragging = true
        case .changed:
            sink.mouseMove(to: p)
        case .ended, .cancelled, .failed:
            if isDragging {
                sink.mouseButton(DL_MOUSE_LEFT, down: false, at: p)
                isDragging = false
            }
        default:
            break
        }
    }

    @objc private func handleMovePan(_ g: UIPanGestureRecognizer) {
        guard g.state == .began || g.state == .changed,
              let p = view.remotePoint(for: g.location(in: view)) else { return }
        sink.mouseMove(to: p)
    }

    @objc private func handleScrollPan(_ g: UIPanGestureRecognizer) {
        Self.sendScroll(g, in: view, sink: sink, remainder: &scrollRemainder)
    }

    @objc private func handleViewportPan(_ g: UIPanGestureRecognizer) {
        guard g.state == .changed else { return }
        view.pan(by: g.translation(in: view))
        g.setTranslation(.zero, in: view)
    }

    @objc private func handlePinch(_ g: UIPinchGestureRecognizer) {
        guard g.state == .changed else { return }
        view.setZoom(view.zoom * g.scale, anchor: g.location(in: view))
        g.scale = 1
    }

    /// パン操作の移動量をホイール量に変換して送る（指・トラックパッド共通）。
    /// 指の動きに画面がついてくる「ナチュラル」な向きにする。
    static func sendScroll(_ g: UIPanGestureRecognizer, in view: RemoteDesktopView,
                           sink: RemoteInputSink, remainder: inout CGPoint) {
        switch g.state {
        case .began:
            remainder = .zero
        case .changed:
            let t = g.translation(in: view)
            g.setTranslation(.zero, in: view)
            guard let p = view.remotePoint(for: g.location(in: view)) else { return }

            remainder.y += t.y * wheelPerPoint
            remainder.x += -t.x * wheelPerPoint
            let dy = Int(remainder.y), dx = Int(remainder.x)
            remainder.y -= CGFloat(dy)
            remainder.x -= CGFloat(dx)
            if dy != 0 { sink.mouseWheel(dy, horizontal: false, at: p) }
            if dx != 0 { sink.mouseWheel(dx, horizontal: true, at: p) }
        default:
            break
        }
    }

    // MARK: - UIGestureRecognizerDelegate

    func gestureRecognizer(_ g: UIGestureRecognizer,
                           shouldRecognizeSimultaneouslyWith other: UIGestureRecognizer) -> Bool {
        // ピンチと3本指パンは同時に使えるようにする
        let pair = [g, other]
        return pair.contains { $0 is UIPinchGestureRecognizer }
            && pair.contains { ($0 as? UIPanGestureRecognizer)?.minimumNumberOfTouches == 3 }
    }
}
