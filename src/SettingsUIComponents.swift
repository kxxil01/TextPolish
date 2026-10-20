import AppKit

/// Small building blocks shared by the settings sections.
enum SettingsUI {
    /// Rounded card that groups related rows. Its dynamic colors follow light and dark mode.
    static func makeCard(frame: NSRect) -> NSBox {
        let card = NSBox(frame: frame)
        card.boxType = .custom
        card.cornerRadius = 10
        card.borderColor = cardBorderColor
        card.borderWidth = 1
        card.fillColor = cardFillColor
        card.titlePosition = .noTitle
        card.contentViewMargins = NSSize(width: 16, height: 12)
        card.autoresizingMask = [.width, .minYMargin]
        return card
    }

    static let cardFillColor = resolvedPerAppearance { NSColor.windowBackgroundColor.withAlphaComponent(0.4) }
    static let cardBorderColor = resolvedPerAppearance { NSColor.separatorColor.withAlphaComponent(0.4) }

    /// Alpha variants of system colors can stay fixed to the appearance they were first resolved under,
    /// so wrap them in a color that resolves again for every appearance.
    private static func resolvedPerAppearance(_ make: @escaping () -> NSColor) -> NSColor {
        NSColor(name: nil) { appearance in
            var resolved = NSColor.clear
            appearance.performAsCurrentDrawingAppearance {
                let color = make()
                resolved = color.usingColorSpace(.sRGB) ?? color
            }
            return resolved
        }
    }

    /// Small header shown above a card, e.g. "General".
    static func makeSectionHeader(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 12, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.autoresizingMask = [.width, .minYMargin]
        return label
    }

    /// Secondary explanatory text, e.g. allowed ranges next to a field.
    static func makeHint(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = NSFont.systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.lineBreakMode = .byTruncatingTail
        return label
    }
}

/// Borderless button styled as a hyperlink, with a pointing-hand cursor.
final class SettingsLinkButton: NSButton {
    convenience init(title: String, fontSize: CGFloat, target: AnyObject?, action: Selector?) {
        self.init(frame: .zero)
        isBordered = false
        setButtonType(.momentaryChange)
        attributedTitle = NSAttributedString(
            string: title,
            attributes: [
                .foregroundColor: NSColor.linkColor,
                .font: NSFont.systemFont(ofSize: fontSize),
            ]
        )
        alignment = .left
        self.target = target
        self.action = action
        setAccessibilityRole(.link)
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .pointingHand)
    }
}

/// Window background that reports light/dark changes so layer-backed colors can be refreshed.
final class SettingsBackgroundView: NSVisualEffectView {
    var onAppearanceChange: (() -> Void)?

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        onAppearanceChange?()
    }
}
