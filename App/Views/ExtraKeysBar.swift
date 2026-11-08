import UIKit

/// ソフトウェアキーボードの上に表示する補助キーの列。
/// iPad のキーボードにない Esc / Tab / Ctrl / Alt / Win / 矢印 / F1〜F12 などを送れる。
final class ExtraKeysBar: UIInputView {
    private unowned let keyboard: KeyboardInputController
    private var stickyButtons: [UInt16: UIButton] = [:]

    init(keyboard: KeyboardInputController) {
        self.keyboard = keyboard
        super.init(frame: CGRect(x: 0, y: 0, width: 0, height: 52), inputViewStyle: .keyboard)
        allowsSelfSizing = true
        buildLayout()
        keyboard.onStickyModifiersChanged = { [weak self] active in
            self?.updateStickyButtons(active)
        }
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("init(coder:) is not supported") }

    override var intrinsicContentSize: CGSize {
        CGSize(width: UIView.noIntrinsicMetric, height: 52)
    }

    private enum Item {
        case key(String, UInt16)
        case sticky(String, UInt16)
        case separator
    }

    private func buildLayout() {
        var items: [Item] = [
            .key("Esc", ScancodeMap.escape),
            .key("Tab", ScancodeMap.tab),
            .sticky("Ctrl", ScancodeMap.leftControl),
            .sticky("Alt", ScancodeMap.leftAlt),
            .sticky("Win", ScancodeMap.leftWindows),
            .separator,
            .key("←", ScancodeMap.left),
            .key("↑", ScancodeMap.up),
            .key("↓", ScancodeMap.down),
            .key("→", ScancodeMap.right),
            .separator,
            .key("Home", ScancodeMap.home),
            .key("End", ScancodeMap.end),
            .key("PgUp", ScancodeMap.pageUp),
            .key("PgDn", ScancodeMap.pageDown),
            .key("Del", ScancodeMap.delete),
            .separator,
        ]
        for n in 1...12 {
            if let code = ScancodeMap.function(n) { items.append(.key("F\(n)", code)) }
        }

        let stack = UIStackView()
        stack.axis = .horizontal
        stack.spacing = 6
        stack.alignment = .center
        stack.translatesAutoresizingMaskIntoConstraints = false

        for item in items {
            switch item {
            case let .key(title, code):
                stack.addArrangedSubview(makeButton(title) { [weak self] in self?.keyboard.tap(code) })
            case let .sticky(title, code):
                let button = makeButton(title) { [weak self] in self?.keyboard.toggleSticky(code) }
                stickyButtons[code] = button
                stack.addArrangedSubview(button)
            case .separator:
                let spacer = UIView()
                spacer.widthAnchor.constraint(equalToConstant: 8).isActive = true
                stack.addArrangedSubview(spacer)
            }
        }

        let scroll = UIScrollView()
        scroll.showsHorizontalScrollIndicator = false
        scroll.translatesAutoresizingMaskIntoConstraints = false
        scroll.addSubview(stack)
        addSubview(scroll)

        NSLayoutConstraint.activate([
            scroll.leadingAnchor.constraint(equalTo: leadingAnchor),
            scroll.trailingAnchor.constraint(equalTo: trailingAnchor),
            scroll.topAnchor.constraint(equalTo: topAnchor),
            scroll.bottomAnchor.constraint(equalTo: bottomAnchor),

            stack.leadingAnchor.constraint(equalTo: scroll.contentLayoutGuide.leadingAnchor, constant: 10),
            stack.trailingAnchor.constraint(equalTo: scroll.contentLayoutGuide.trailingAnchor, constant: -10),
            stack.topAnchor.constraint(equalTo: scroll.contentLayoutGuide.topAnchor),
            stack.bottomAnchor.constraint(equalTo: scroll.contentLayoutGuide.bottomAnchor),
            stack.heightAnchor.constraint(equalTo: scroll.frameLayoutGuide.heightAnchor),
        ])
    }

    private func makeButton(_ title: String, action: @escaping () -> Void) -> UIButton {
        var config = UIButton.Configuration.gray()
        config.title = title
        config.cornerStyle = .medium
        config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
        let button = UIButton(configuration: config, primaryAction: UIAction { _ in
            UIDevice.current.playInputClick()
            action()
        })
        button.heightAnchor.constraint(equalToConstant: 38).isActive = true
        return button
    }

    private func updateStickyButtons(_ active: Set<UInt16>) {
        for (code, button) in stickyButtons {
            var config = active.contains(code) ? UIButton.Configuration.filled() : UIButton.Configuration.gray()
            config.title = button.configuration?.title
            config.cornerStyle = .medium
            config.contentInsets = NSDirectionalEdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12)
            button.configuration = config
        }
    }
}

extension ExtraKeysBar: UIInputViewAudioFeedback {
    var enableInputClicksWhenVisible: Bool { true }
}
