import AppKit
import SnipLiteCore

@MainActor
final class PinController {
    static let shared = PinController()

    private(set) var pins: [PinWindow] = []
    private var recoverable: [(image: CGImage, topLeft: NSPoint)] = []
    private var hideAllFlag = false
    private(set) var currentGroup = 1

    private init() {}

    var openCount: Int { pins.count }

    // MARK: - 创建

    func pin(image: CGImage, topLeft: NSPoint) {
        let scale = NSScreen.screens.first { $0.frame.contains(topLeft) }?.backingScaleFactor
            ?? NSScreen.main?.backingScaleFactor ?? 2
        let window = PinWindow(image: image, topLeft: topLeft, scale: scale)
        window.pinController = self
        window.group = currentGroup
        window.orderFrontRegardless()
        if SettingsStore.shared.settings.flashNewPin { window.flash() }
        pins.append(window)
        hideAllFlag = false
    }

    /// F3 / 菜单：优先贴剪贴板图像，其次是文字，最后恢复最近关闭的贴图。
    func pasteFromClipboard() {
        let mouse = NSEvent.mouseLocation
        let topLeft = NSPoint(x: mouse.x - 40, y: mouse.y + 40)

        if let image = OutputService.clipboardImage() {
            pin(image: image, topLeft: topLeft)
            return
        }

        if let text = NSPasteboard.general.string(forType: .string),
           !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !looksLikeFilePath(text),
           let image = TextImageRenderer.render(text: text) {
            pin(image: image, topLeft: topLeft)
            return
        }

        if !restoreLast() {
            Toast.show("剪贴板中没有可贴出的内容")
        }
    }

    private func looksLikeFilePath(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasPrefix("/") || trimmed.hasPrefix("file://") || trimmed.hasPrefix("~") {
            return true
        }
        return FileManager.default.fileExists(atPath: (trimmed as NSString).expandingTildeInPath)
    }

    // MARK: - 生命周期

    func pinDidClose(_ pin: PinWindow) {
        pins.removeAll { $0 === pin }
        let limit = max(0, min(20, SettingsStore.shared.settings.recoverablePins))
        if limit > 0 {
            let topLeft = NSPoint(x: pin.frame.minX, y: pin.frame.maxY)
            recoverable.append((pin.pinnedImage, topLeft))
            while recoverable.count > limit { recoverable.removeFirst() }
        }
    }

    @discardableResult
    func restoreLast() -> Bool {
        guard let last = recoverable.popLast() else { return false }
        pin(image: last.image, topLeft: last.topLeft)
        return true
    }

    func closeAll() {
        for pin in pins { pin.close() }
        pins.removeAll()
    }

    func hideAll() {
        hideAllFlag = true
        pins.forEach { $0.orderOut(nil) }
    }

    func showAll() {
        hideAllFlag = false
        pins.forEach { $0.orderFrontRegardless() }
    }

    func toggleAll() {
        if hideAllFlag || pins.allSatisfy({ !$0.isVisible }) {
            showAll()
        } else {
            hideAll()
        }
    }

    var isHidingAll: Bool { hideAllFlag }

    func switchGroup() {
        currentGroup = currentGroup % 3 + 1
        for pin in pins {
            if pin.group == currentGroup {
                pin.orderFrontRegardless()
                pin.flash()
            } else {
                pin.orderOut(nil)
            }
        }
        hideAllFlag = false
        Toast.show("贴图分组 \(currentGroup)")
    }

    func move(_ pin: PinWindow, to group: Int) {
        pin.group = group
        if group != currentGroup {
            pin.orderOut(nil)
        }
    }
}
