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

    override var intrinsicContentSize: NSSize { NSSize(width: 180, height: 26) }

    override func draw(_ dirtyRect: NSRect) {
        let path = NSBezierPath(roundedRect: bounds.insetBy(dx: 1, dy: 1), xRadius: 5, yRadius: 5)
        NSColor.controlBackgroundColor.setFill()
        path.fill()
        (isInvalid ? NSColor.systemRed : NSColor.separatorColor).setStroke()
        path.lineWidth = editing ? 2 : 1
        path.stroke()

        let text = editing ? "按下快捷键…" : binding.displayText
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 12),
            .foregroundColor: editing ? NSColor.secondaryLabelColor : NSColor.labelColor
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: NSPoint(x: 8, y: (bounds.height - size.height) / 2),
                                withAttributes: attributes)
    }

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
