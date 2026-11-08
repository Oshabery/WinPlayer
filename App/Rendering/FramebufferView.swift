import QuartzCore
import UIKit

/// リモート画面を表示し、タッチ・ポインタ・キーボード入力を受け取るビュー。
final class RemoteDesktopView: UIView, UIKeyInput {
    let session: RDPSession

    private let contentLayer = CALayer()
    private var displayLink: CADisplayLink?

    /// 1.0 = 画面に収まる大きさ
    private(set) var zoom: CGFloat = 1
    /// 中央からのずれ（ポイント）
    private var panOffset: CGPoint = .zero

    private lazy var touchInput = TouchInputController(view: self)
    private lazy var pointerInput = PointerInputController(view: self)
    lazy var keyboardInput = KeyboardInputController(sink: session)

    init(session: RDPSession) {
        self.session = session
        super.init(frame: .zero)
        backgroundColor = .black
        isMultipleTouchEnabled = true

        contentLayer.magnificationFilter = .linear
        contentLayer.minificationFilter = .trilinear
        contentLayer.contentsGravity = .resize
        contentLayer.actions = ["contents": NSNull(), "bounds": NSNull(), "position": NSNull()]
        layer.addSublayer(contentLayer)

        touchInput.install()
        pointerInput.install()
        // 描画は CADisplayLink で毎フレーム Framebuffer の更新有無を確認して行う
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        displayLink?.invalidate()
        displayLink = nil
        if window != nil {
            let link = CADisplayLink(target: DisplayLinkProxy(self), selector: #selector(DisplayLinkProxy.tick))
            link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
            link.add(to: .main, forMode: .common)
            displayLink = link
        }
    }

    fileprivate func refresh() {
        if let image = session.framebuffer.takeImageIfDirty() {
            contentLayer.contents = image
            setNeedsLayout()
        }
    }

    // MARK: - レイアウトと座標変換

    var remoteSize: CGSize {
        CGSize(width: session.framebuffer.width, height: session.framebuffer.height)
    }

    /// 画面に収めるための倍率
    private var fitScale: CGFloat {
        let size = remoteSize
        guard size.width > 0, size.height > 0, bounds.width > 0, bounds.height > 0 else { return 1 }
        return min(bounds.width / size.width, bounds.height / size.height)
    }

    /// リモート画面がビュー上に描かれる矩形
    var contentFrame: CGRect {
        let size = remoteSize
        let scale = fitScale * zoom
        let w = size.width * scale, h = size.height * scale
        let origin = CGPoint(x: (bounds.width - w) / 2 + panOffset.x,
                             y: (bounds.height - h) / 2 + panOffset.y)
        return CGRect(origin: origin, size: CGSize(width: w, height: h))
    }

    override func layoutSubviews() {
        super.layoutSubviews()
        clampPan()
        contentLayer.frame = contentFrame
    }

    /// ビュー上の点 → リモート座標（画面外は端に丸める）
    func remotePoint(for viewPoint: CGPoint) -> RemotePoint? {
        let frame = contentFrame
        let size = remoteSize
        guard frame.width > 0, frame.height > 0 else { return nil }
        let x = (viewPoint.x - frame.minX) / frame.width * size.width
        let y = (viewPoint.y - frame.minY) / frame.height * size.height
        let cx = min(max(x, 0), size.width - 1)
        let cy = min(max(y, 0), size.height - 1)
        return RemotePoint(x: UInt16(cx), y: UInt16(cy))
    }

    func setZoom(_ newZoom: CGFloat, anchor: CGPoint) {
        let clamped = min(max(newZoom, 1), 6)
        guard clamped != zoom else { return }
        // anchor（ビュー座標）の下にある画面上の点が動かないようにずらす
        let center = CGPoint(x: bounds.midX, y: bounds.midY)
        let ratio = clamped / zoom
        panOffset = CGPoint(x: (panOffset.x - (anchor.x - center.x)) * ratio + (anchor.x - center.x),
                            y: (panOffset.y - (anchor.y - center.y)) * ratio + (anchor.y - center.y))
        zoom = clamped
        setNeedsLayout()
    }

    func pan(by translation: CGPoint) {
        panOffset.x += translation.x
        panOffset.y += translation.y
        setNeedsLayout()
    }

    func resetZoom() {
        zoom = 1
        panOffset = .zero
        setNeedsLayout()
    }

    /// 拡大中に画面の外へ出過ぎないようにする
    private func clampPan() {
        let size = remoteSize
        let scale = fitScale * zoom
        let maxX = max(0, (size.width * scale - bounds.width) / 2)
        let maxY = max(0, (size.height * scale - bounds.height) / 2)
        panOffset.x = min(max(panOffset.x, -maxX), maxX)
        panOffset.y = min(max(panOffset.y, -maxY), maxY)
    }

    // MARK: - ポインタ（トラックパッド／マウス）のクリック

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !pointerInput.touchesBegan(touches, with: event) { super.touchesBegan(touches, with: event) }
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !pointerInput.touchesMoved(touches, with: event) { super.touchesMoved(touches, with: event) }
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !pointerInput.touchesEnded(touches, with: event) { super.touchesEnded(touches, with: event) }
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        if !pointerInput.touchesEnded(touches, with: event) { super.touchesCancelled(touches, with: event) }
    }

    // MARK: - ハードウェアキーボード

    override var canBecomeFirstResponder: Bool { true }

    override func pressesBegan(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = keyboardInput.pressesBegan(presses)
        if !rest.isEmpty { super.pressesBegan(rest, with: event) }
    }

    override func pressesEnded(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = keyboardInput.pressesEnded(presses)
        if !rest.isEmpty { super.pressesEnded(rest, with: event) }
    }

    override func pressesCancelled(_ presses: Set<UIPress>, with event: UIPressesEvent?) {
        let rest = keyboardInput.pressesEnded(presses)
        if !rest.isEmpty { super.pressesCancelled(rest, with: event) }
    }

    override func resignFirstResponder() -> Bool {
        keyboardInput.releaseAllKeys()
        return super.resignFirstResponder()
    }

    // MARK: - ソフトウェアキーボード (UIKeyInput)

    var hasText: Bool { true }
    func insertText(_ text: String) { keyboardInput.insertText(text) }
    func deleteBackward() { keyboardInput.tap(ScancodeMap.backspace) }

    var autocorrectionType: UITextAutocorrectionType = .no
    var autocapitalizationType: UITextAutocapitalizationType = .none
    var spellCheckingType: UITextSpellCheckingType = .no
    var smartQuotesType: UITextSmartQuotesType = .no
    var smartDashesType: UITextSmartDashesType = .no
    var smartInsertDeleteType: UITextSmartInsertDeleteType = .no

    private lazy var extraKeysBar = ExtraKeysBar(keyboard: keyboardInput)
    override var inputAccessoryView: UIView? { extraKeysBar }
}

/// CADisplayLink がビューを強参照しないための中継
private final class DisplayLinkProxy: NSObject {
    weak var view: RemoteDesktopView?
    init(_ view: RemoteDesktopView) { self.view = view }
    @objc func tick() { view?.refresh() }
}
