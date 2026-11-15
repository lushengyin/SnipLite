import AppKit
import SnipLiteCore

/// 轻量提示条：非激活、置顶、自动消失。截图过程中出现也不能抢焦点。
final class Toast {
    private static var live: [Toast] = []

    private let panel: NSPanel

    private init(message: String) {
        let label = NSTextField(labelWithString: message)
        label.font = .systemFont(ofSize: 13, weight: .medium)
        label.textColor = .white
        label.alignment = .center
        label.lineBreakMode = .byTruncatingTail
        let textSize = label.sizeThatFits(NSSize(width: 520, height: 200))

        let width = min(max(textSize.width + 36, 120), 560)
        let height = textSize.height + 20

        let container = NSView(frame: NSRect(x: 0, y: 0, width: width, height: height))
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.black.withAlphaComponent(0.82).cgColor
        container.layer?.cornerRadius = 10
        container.layer?.masksToBounds = true

        label.frame = NSRect(x: 18, y: 10, width: width - 36, height: textSize.height)
        container.addSubview(label)

        panel = NSPanel(contentRect: NSRect(x: 0, y: 0, width: width, height: height),
                        styleMask: [.borderless, .nonactivatingPanel],
                        backing: .buffered,
                        defer: false)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .statusBar
        panel.ignoresMouseEvents = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = container
        panel.alphaValue = 0
    }

    static func show(_ message: String, duration: TimeInterval = 1.6) {
        guard SettingsStore.shared.settings.showToast else { return }
        let toast = Toast(message: message)
        toast.positionNearCursor()
        toast.panel.orderFrontRegardless()
        live.append(toast)

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            toast.panel.animator().alphaValue = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + duration) {
            NSAnimationContext.runAnimationGroup({ context in
                context.duration = 0.2
                toast.panel.animator().alphaValue = 0
            }, completionHandler: {
                toast.panel.orderOut(nil)
                live.removeAll { $0 === toast }
            })
        }
    }

    private func positionNearCursor() {
        let mouse = NSEvent.mouseLocation
        let screen = NSScreen.screens.first { $0.frame.contains(mouse) } ?? NSScreen.main
        guard let visible = screen?.visibleFrame else { return }
        let size = panel.frame.size
        let origin = NSPoint(x: visible.midX - size.width / 2,
                             y: visible.minY + 96)
        panel.setFrameOrigin(origin)
    }
}
