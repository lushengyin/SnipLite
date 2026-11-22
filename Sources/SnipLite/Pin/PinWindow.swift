import AppKit
import SnipLiteCore

/// 悬浮贴图窗口：拖动、滚轮缩放、⌘+滚轮调透明度、右键菜单。
final class PinWindow: NSWindow {
    let pinnedImage: CGImage
    let baseSize: CGSize
    private(set) var zoom: CGFloat = 1
    private(set) var isThumbnail = false
    var group = 1
    private(set) var through = false
    weak var pinController: PinController?

    private var flashTimer: Timer?
    private var flashTicks = 0
    var dragOrigin: NSPoint?
    var dragMouse: NSPoint?

    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    init(image: CGImage, topLeft: NSPoint, scale: CGFloat) {
        pinnedImage = image
        let pixel = CGSize(width: CGFloat(image.width), height: CGFloat(image.height))
        baseSize = CGSize(width: max(1, pixel.width / scale), height: max(1, pixel.height / scale))

        super.init(contentRect: NSRect(origin: .zero, size: baseSize),
                   styleMask: .borderless,
                   backing: .buffered,
                   defer: false)
        isOpaque = false
        backgroundColor = .clear
        hasShadow = SettingsStore.shared.settings.pinShadow
        level = .floating
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        isReleasedWhenClosed = false
        contentView = PinContentView(pin: self)
        setFrameOrigin(NSPoint(x: topLeft.x, y: topLeft.y - baseSize.height))
        clampToScreens()
    }

    override func close() {
        pinController?.pinDidClose(self)
        super.close()
    }

    // MARK: - 缩放 / 透明度

    func applyZoom(_ factor: CGFloat, around screenPoint: NSPoint?) {
        let anchor = screenPoint ?? NSPoint(x: frame.midX, y: frame.midY)
        let ratioX = frame.width > 0 ? (anchor.x - frame.minX) / frame.width : 0.5
        let ratioY = frame.height > 0 ? (anchor.y - frame.minY) / frame.height : 0.5
        let limit = CGFloat(SettingsStore.shared.settings.pinMaxSize)
        let maxZoom = max(0.02, min(8, limit / max(baseSize.width, baseSize.height)))
        zoom = min(max(zoom * factor, 0.02), maxZoom)
        let size = CGSize(width: baseSize.width * zoom, height: baseSize.height * zoom)
        let origin = NSPoint(x: anchor.x - size.width * ratioX,
                             y: anchor.y - size.height * ratioY)
        setFrame(NSRect(origin: origin, size: size), display: true)
    }

    func resetZoom() {
        zoom = 1
        isThumbnail = false
        let size = baseSize
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        setFrame(NSRect(origin: origin, size: size), display: true)
    }

    func toggleThumbnail() {
        if isThumbnail {
            resetZoom()
            return
        }
        let settings = SettingsStore.shared.settings
        let target = CGSize(width: CGFloat(settings.thumbnailWidth), height: CGFloat(settings.thumbnailHeight))
        let factor = min(target.width / baseSize.width, target.height / baseSize.height)
        zoom = factor
        isThumbnail = true
        let size = CGSize(width: baseSize.width * factor, height: baseSize.height * factor)
        let origin = NSPoint(x: frame.midX - size.width / 2, y: frame.midY - size.height / 2)
        setFrame(NSRect(origin: origin, size: size), display: true)
    }

    func adjustOpacity(_ delta: CGFloat) {
        alphaValue = min(max(alphaValue + delta, 0.1), 1)
    }

    func flash() {
        flashTimer?.invalidate()
        flashTicks = 0
        flashTimer = Timer.scheduledTimer(withTimeInterval: 0.12, repeats: true) { [weak self] timer in
            guard let self else { timer.invalidate(); return }
            self.flashTicks += 1
            self.alphaValue = self.flashTicks % 2 == 0 ? 1 : 0.65
            if self.flashTicks >= 6 {
                timer.invalidate()
                self.alphaValue = 1
            }
        }
    }

    // MARK: - 操作

    func copyImage() {
        if OutputService.copyToPasteboard(pinnedImage) {
            Toast.show("已复制贴图")
        }
    }

    func saveImage() {
        let name = FileNamePattern.fileName(pattern: SettingsStore.shared.settings.fileNamePattern,
                                            extension: "png")
        guard let url = OutputService.chooseSaveURL(defaultName: name) else { return }
        do {
            try OutputService.write(pinnedImage, to: url,
                                    jpegQuality: SettingsStore.shared.settings.jpegQuality)
            Toast.show("已保存：\(url.lastPathComponent)")
        } catch {
            Toast.show("保存失败")
        }
    }

    func recognizeText() {
        Toast.show("正在识别…")
        Task {
            do {
                let document = try await Task.detached(priority: .userInitiated) {
                    try VisionOcrEngine.recognize(self.pinnedImage)
                }.value
                guard !document.isEmpty else {
                    Toast.show("未识别到文字")
                    return
                }
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(document.text, forType: .string)
                Toast.show("文字已复制")
            } catch {
                Toast.show("识别失败")
            }
        }
    }

    func recognizeCode() {
        Task {
            do {
                let value = try await Task.detached(priority: .userInitiated) {
                    try VisionBarcodeScanner.scan(self.pinnedImage)
                }.value
                guard let value, !value.isEmpty else {
                    Toast.show("未检测到二维码 / 条码")
                    return
                }
                let alert = NSAlert()
                alert.messageText = "识别成功"
                alert.informativeText = value
                alert.addButton(withTitle: "复制内容")
                alert.addButton(withTitle: "关闭")
                if alert.runModal() == .alertFirstButtonReturn {
                    let pasteboard = NSPasteboard.general
                    pasteboard.clearContents()
                    pasteboard.setString(value, forType: .string)
                }
            } catch {
                Toast.show("识别失败")
            }
        }
    }

    func menu() -> NSMenu {
        let menu = NSMenu()
        func add(_ title: String, _ action: Selector?, key: String = "") {
            let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
            item.target = self
            menu.addItem(item)
        }
        add("复制图像", #selector(menuCopy), key: "c")
        add("另存为…", #selector(menuSave), key: "s")
        add("识别文字", #selector(menuOCR))
        add("识别二维码", #selector(menuQR))
        menu.addItem(.separator())
        add("原始大小", #selector(menuReset), key: "0")
        add("快速缩略图", #selector(menuThumbnail))
        add("恢复 100% 不透明度", #selector(menuOpacity))
        add("鼠标穿透", #selector(menuThrough))

        let groupMenu = NSMenu()
        for index in 1...3 {
            let item = NSMenuItem(title: "分组 \(index)", action: #selector(menuMoveGroup(_:)), keyEquivalent: "")
            item.tag = index
            item.target = self
            groupMenu.addItem(item)
        }
        let groupItem = NSMenuItem(title: "移动到分组", action: nil, keyEquivalent: "")
        groupItem.submenu = groupMenu
        menu.addItem(groupItem)
        menu.addItem(.separator())
        add("关闭", #selector(menuClose), key: "w")
        add("关闭全部贴图", #selector(menuCloseAll))
        add("隐藏 / 显示所有贴图", #selector(menuToggleAll))
        return menu
    }

    @objc private func menuCopy() { copyImage() }
    @objc private func menuSave() { saveImage() }
    @objc private func menuOCR() { recognizeText() }
    @objc private func menuQR() { recognizeCode() }
    @objc private func menuReset() { resetZoom() }
    @objc private func menuThumbnail() { toggleThumbnail() }
    @objc private func menuOpacity() { alphaValue = 1 }

    @objc private func menuThrough() {
        through.toggle()
        ignoresMouseEvents = through
        Toast.show(through ? "已开启鼠标穿透，用菜单关闭全部贴图即可恢复" : "已关闭鼠标穿透")
    }

    @objc private func menuMoveGroup(_ sender: NSMenuItem) {
        pinController?.move(self, to: sender.tag)
    }
    @objc private func menuClose() { close() }
    @objc private func menuCloseAll() { pinController?.closeAll() }
    @objc private func menuToggleAll() { pinController?.toggleAll() }
}

extension PinWindow {
    func clampToScreens() {
        let screens = NSScreen.screens.map(\.visibleFrame)
        let frame = self.frame
        guard !screens.isEmpty else { return }
        if screens.contains(where: { $0.intersects(frame) }) { return }

        // 完全在屏外时拉回主屏中部
        guard let main = NSScreen.main?.visibleFrame else { return }
        let origin = NSPoint(x: main.midX - frame.width / 2, y: main.midY - frame.height / 2)
        setFrameOrigin(origin)
    }

    /// 以鼠标所在屏幕为基准做限制：贴图可以大部分移出屏幕，
    /// 但至少保留一小段可见边缘；跨屏拖动时随鼠标切换到另一块屏幕。
    func clampOrigin(_ origin: NSPoint, cursor: NSPoint) -> NSPoint {
        let screen = NSScreen.screens.first { $0.frame.contains(cursor) }?.visibleFrame
            ?? NSScreen.main?.visibleFrame
        guard let screen else { return origin }
        let point = DragBounds.clamp(origin: origin, size: frame.size, within: screen)
        return NSPoint(x: point.x, y: point.y)
    }
}

final class PinContentView: NSView {
    private weak var pin: PinWindow?

    init(pin: PinWindow) {
        self.pin = pin
        super.init(frame: NSRect(origin: .zero, size: pin.baseSize))
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var acceptsFirstResponder: Bool { true }
    override var isFlipped: Bool { true }

    override func draw(_ dirtyRect: NSRect) {
        guard let pin, let context = NSGraphicsContext.current?.cgContext else { return }
        NSColor.black.setFill()
        bounds.fill()
        context.saveGState()
        context.interpolationQuality = SettingsStore.shared.settings.pinSmoothScaling ? .high : .none
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        context.draw(pin.pinnedImage, in: CGRect(origin: .zero, size: bounds.size))
        context.restoreGState()
    }

    override func mouseDown(with event: NSEvent) {
        guard let pin else { return }
        window?.makeFirstResponder(self)
        if event.clickCount == 2 {
            if event.modifierFlags.contains(.shift) {
                pin.toggleThumbnail()
            } else {
                pin.close()
            }
            return
        }
        pin.dragMouse = NSEvent.mouseLocation
        pin.dragOrigin = pin.frame.origin
    }

    private var draggingFile = false

    override func mouseDragged(with event: NSEvent) {
        guard let pin else { return }
        if event.modifierFlags.contains(.option) {
            if !draggingFile {
                draggingFile = true
                startFileDrag(event)
            }
            return
        }
        guard let dragOrigin = pin.dragOrigin, let dragMouse = pin.dragMouse else { return }
        let current = NSEvent.mouseLocation
        let delta = NSPoint(x: current.x - dragMouse.x, y: current.y - dragMouse.y)
        let origin = NSPoint(x: dragOrigin.x + delta.x, y: dragOrigin.y + delta.y)
        pin.setFrameOrigin(pin.clampOrigin(origin, cursor: current))
    }

    override func mouseUp(with event: NSEvent) {
        guard let pin else { return }
        pin.dragOrigin = nil
        pin.dragMouse = nil
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        pin?.resetZoom()
    }

    override func scrollWheel(with event: NSEvent) {
        guard let pin else { return }
        if event.modifierFlags.contains(.command) {
            pin.adjustOpacity(event.scrollingDeltaY > 0 ? 0.1 : -0.1)
        } else if SettingsStore.shared.settings.pinWheelZoom {
            let factor = event.scrollingDeltaY > 0 ? 1.1 : 0.9
            pin.applyZoom(factor, around: NSEvent.mouseLocation)
        }
    }

    override func rightMouseDown(with event: NSEvent) {
        guard let pin else { return }
        NSMenu.popUpContextMenu(pin.menu(), with: event, for: self)
    }

    private func startFileDrag(_ event: NSEvent) {
        guard let pin, let data = OutputService.pngData(pin.pinnedImage) else { return }
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("SnipLite-\(UUID().uuidString).png")
        do {
            try data.write(to: url)
        } catch {
            return
        }
        let item = NSDraggingItem(pasteboardWriter: url as NSURL)
        item.setDraggingFrame(bounds, contents: NSImage(cgImage: pin.pinnedImage, size: bounds.size))
        beginDraggingSession(with: [item], event: event, source: self)
    }

    override func keyDown(with event: NSEvent) {
        guard let pin else { return }
        switch event.keyCode {
        case 53:
            pin.close()
        default:
            if event.modifierFlags.contains(.command) {
                switch event.charactersIgnoringModifiers?.lowercased() {
                case "c": pin.copyImage()
                case "s": pin.saveImage()
                case "0": pin.resetZoom()
                default: break
                }
            }
        }
    }
}


extension PinContentView: NSDraggingSource {
    func draggingSession(_ session: NSDraggingSession, sourceOperationMaskFor context: NSDraggingContext) -> NSDragOperation {
        .copy
    }
}
