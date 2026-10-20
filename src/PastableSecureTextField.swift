import AppKit

final class PastableSecureTextField: NSSecureTextField {
    static func handlesCommandKeyEquivalent(_ characters: String) -> Bool {
        characters == "v" || characters == "a"
    }

    override func performKeyEquivalent(with event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags == .command,
            let chars = event.charactersIgnoringModifiers,
            Self.handlesCommandKeyEquivalent(chars)
        {
            switch chars {
            case "v":
                if NSApp.sendAction(#selector(NSText.paste(_:)), to: nil, from: self) {
                    return true
                }

            case "a":
                if NSApp.sendAction(#selector(NSText.selectAll(_:)), to: nil, from: self) {
                    return true
                }
            default:
                break
            }
        }
        return super.performKeyEquivalent(with: event)
    }
}
