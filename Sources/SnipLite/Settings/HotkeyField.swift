import AppKit
import SnipLiteCore

/// 热键录制控件：点击后按下组合键即可。
final class HotkeyField: NSView {
    var binding: HotkeyBinding = .unset {
        didSet { needsDisplay = true }
    }
    var onChange: ((HotkeyBinding) -> Void)?
    var isInvalid = false {
        didSet { needsDisplay = true }
    }

    private var editing = false

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 28) }

    override func draw(_ dirtyRect: NSRect) {
        let dark = effectiveAppearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 0.75, dy: 0.75), xRadius: 8, yRadius: 8)
        (dark ? NSColor.white.withAlphaComponent(0.06)
              : NSColor.labelColor.withAlphaComponent(0.045)).setFill()
        path.fill()

        if isInvalid {
            NSColor.systemRed.setStroke()
            path.lineWidth = 1.6
        } else if editing {
            NSColor.controlAccentColor.setStroke()
            path.lineWidth = 1.6
        } else {
            (dark ? NSColor.white.withAlphaComponent(0.09)
                  : NSColor.separatorColor.withAlphaComponent(0.22)).setStroke()
            path.lineWidth = 1
        }
        path.stroke()

        let text = editing ? "按下快捷键…" : binding.displayText
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 13),
            .foregroundColor: editing ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: 10, y: (bounds.height - size.height) / 2),
                                withAttributes: attributes)
    }

    override func viewDidChangeEffectiveAppearance() { needsDisplay = true }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        editing = true
        needsDisplay = true
    }

    override func resignFirstResponder() -> Bool {
        editing = false
        needsDisplay = true
        return true
    }

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 { // Esc
            editing = false
            window?.makeFirstResponder(nil)
            needsDisplay = true
            return
        }
        if event.keyCode == 51 || event.keyCode == 117 { // Delete
            binding = .unset
            onChange?(binding)
            editing = false
            window?.makeFirstResponder(nil)
            needsDisplay = true
            return
        }

        guard let characters = event.charactersIgnoringModifiers, !characters.isEmpty else { return }
        let flags = event.modifierFlags
        var modifiers: [HotkeyBinding.Modifier] = []
        if flags.contains(.control) { modifiers.append(.control) }
        if flags.contains(.option) { modifiers.append(.option) }
        if flags.contains(.shift) { modifiers.append(.shift) }
        if flags.contains(.command) { modifiers.append(.command) }

        let key = characters.uppercased()
        binding = HotkeyBinding(key: key, modifiers: modifiers)
        onChange?(binding)
        editing = false
        window?.makeFirstResponder(nil)
        needsDisplay = true
    }
}
