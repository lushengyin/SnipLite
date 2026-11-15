import AppKit
import CoreGraphics
import SnipLiteCore

enum CaptureMode: Sendable {
    case capture
    case ocr
    case translation
    case qr
}

@MainActor
final class CaptureSession {
    enum DragMode {
        case none
        case creating
        case moving
        case resizing
        case drawing
        case ocrSelect
    }

    struct TextEditing {
        var origin: CGPoint
        var text: String = ""
        var marked: String = ""
        var isNew: Bool
        var shapeIndex: Int?
        var color: RGBAColor
        var fontSize: CGFloat
        var fontFamily: String = "PingFang SC"
    }

    private(set) static var current: CaptureSession?

    let mode: CaptureMode
    let geometry: ScreenGeometry
    let settings: AppSettings
    let capturedImage: CGImage

    private(set) var selection: CGRect?
    private(set) var hoverPoint: CGPoint?
    private(set) var hoverTarget: CGRect?
    private(set) var dragMode: DragMode = .none
    private(set) var altPressed = false
    private(set) var shiftPressed = false

    private(set) var tool: ToolKind?
    private(set) var colorIndex = 0
    private(set) var lineWidth: CGFloat = 3
    private(set) var arrowStyle: ArrowStyle = .solid
    private(set) var filled = false
    private(set) var markerOpacity: CGFloat = 0.5
    private(set) var mosaicBlock: CGFloat = 12
    private(set) var rectangular = false

    private(set) var shapes: [Shape] = []
    private(set) var textEditing: TextEditing?
    private(set) var currentShape: Shape?

    private(set) var hoveredBarItem: AnnotationBarLayout.Item?

    func setHoveredBarItem(_ item: AnnotationBarLayout.Item?) {
        guard hoveredBarItem != item else { return }
        hoveredBarItem = item
        redraw()
    }

    private(set) var ocrDocument: OcrDocument = .empty
    private(set) var ocrActive = false
    private(set) var ocrAnchor: Int?
    private(set) var ocrEnd: Int?
    private(set) var translationLayer: CGImage?
    private(set) var statusMessage: String?
    private(set) var selectionCreatedAt = Date.distantPast

    func markSelectionCreated() {
        selectionCreatedAt = Date()
    }

    private(set) var copyableResult: String?
    private var ocrOrigin: CGPoint = .zero
    private var ocrScale: CGFloat = 1
    private var currentSource: String
    private var currentTarget: String
    private var currentProvider: TranslationProviderKind
    private var translationBase: CGImage?
    private(set) var translationActive = false
    private(set) var showOriginal = false
    private var recognitionTask: Task<Void, Never>?

    var sourceTitle: String { TranslationServices.title(for: currentSource) }
    var targetTitle: String { TranslationServices.title(for: currentTarget) }
    var providerTitle: String { currentProvider.title }
    var languages: [(code: String, title: String)] { TranslationServices.languages }
    var providers: [TranslationProviderKind] { TranslationProviderKind.allCases }

    private var undoStack: [[Shape]] = []
    private var redoStack: [[Shape]] = []
    private var annotationLayer: CGImage?
    private var layerDirty = true
    private let sampler: BitmapSampler?

    private var model: SelectionModel
    private var windows: [OverlayWindow] = []
    private let preset: CGRect?
    private let autoCopy: Bool
    private var anchor: CGPoint = .zero
    private var originalSelection: CGRect?
    private var activeHandle: SelectionHandle?
    private var pressTarget: CGRect?
    private var lastTargetUpdate = Date.distantPast
    private var didFinish = false

    private init(mode: CaptureMode, desktop: CapturedDesktop, settings: AppSettings,
                 preset: CGRect?, autoCopy: Bool) {
        self.mode = mode
        self.geometry = desktop.geometry
        self.capturedImage = desktop.image
        self.settings = settings
        self.preset = preset
        self.autoCopy = autoCopy
        self.model = SelectionModel(bounds: desktop.geometry.union)
        self.sampler = BitmapSampler(cgImage: desktop.image)
        self.currentSource = settings.translationSourceLanguage
        self.currentTarget = settings.translationTargetLanguage
        self.currentProvider = settings.translationProvider
    }

    // MARK: - 生命周期

    nonisolated static func start(mode: CaptureMode = .capture,
                                  preset: CGRect? = nil,
                                  autoCopy: Bool = false) {
        AppLog.shared.write("请求截图 mode=\(mode)")
        let settings = SettingsStore.shared.settings
        Task { @MainActor in
            guard current == nil else { return }
            do {
                let desktop = try await ScreenCaptureService.capture(settings: settings)
                let session = CaptureSession(mode: mode, desktop: desktop, settings: settings,
                                             preset: preset, autoCopy: autoCopy)
                current = session
                session.present()
            } catch {
                current = nil
                presentError(error)
            }
        }
    }

    private func present() {
        AppLog.shared.write("遮罩显示 screens=\(geometry.screens.count)")
        let mouse = NSEvent.mouseLocation
        let modelMouse = geometry.toModel(mouse)
        var keyView: SelectionView?

        for screen in geometry.screens {
            let window = OverlayWindow(frame: geometry.cocoaFrame(for: screen))
            let view = SelectionView(session: self, screen: screen)
            window.contentView = view
            window.orderFrontRegardless()
            windows.append(window)
            if screen.frame.contains(modelMouse) { keyView = view }
        }

        NSApp.activate(ignoringOtherApps: true)
        let target = keyView ?? windows.first?.contentView as? SelectionView
        if let target {
            target.window?.makeKey()
            target.window?.makeFirstResponder(target)
        }
        applyPresetIfNeeded()
    }

    private func applyPresetIfNeeded() {
        guard let preset else { return }
        let rect = model.clamped(preset)
        guard rect.width >= 1, rect.height >= 1 else { return }
        selection = rect
        markSelectionCreated()
        redraw()
        if mode != .capture {
            switch mode {
            case .ocr: recognizeText(translate: false)
            case .translation: recognizeText(translate: true)
            case .qr: recognizeQR()
            case .capture: break
            }
        }
        if autoCopy { perform(.copy, exit: true) }
    }

    func close() {
        guard !didFinish else { return }
        didFinish = true
        closeOcrPanel()
        closeTranslation()
        AppLog.shared.write("关闭截图遮罩")
        windows.forEach { $0.orderOut(nil) }
        windows.removeAll()
        if CaptureSession.current === self { CaptureSession.current = nil }
        NSCursor.arrow.set()
    }

    private func hideOverlay() { windows.forEach { $0.orderOut(nil) } }

    private func showOverlay() {
        for window in windows { window.orderFrontRegardless() }
        if let view = windows.first?.contentView {
            view.window?.makeKey()
            view.window?.makeFirstResponder(view)
        }
    }

    func redraw() {
        for window in windows { window.contentView?.needsDisplay = true }
    }

    // MARK: - 标注状态

    var canUndo: Bool { !undoStack.isEmpty }
    var canRedo: Bool { !redoStack.isEmpty }
    var currentColor: RGBAColor { RGBAColor.palette[min(max(colorIndex, 0), RGBAColor.palette.count - 1)] }

    func barLayout() -> AnnotationBarLayout? {
        guard let selection,
              let screen = geometry.screen(at: CGPoint(x: selection.minX, y: selection.maxY)) else {
            return nil
        }
        return AnnotationBarLayout.make(selection: selection, screen: screen, tool: tool,
                                        color: currentColor, filled: filled,
                                        arrowStyle: arrowStyle, lineWidth: lineWidth,
                                        opacity: markerOpacity, blockSize: mosaicBlock,
                                        rectangular: rectangular,
                                        canUndo: canUndo, canRedo: canRedo,
                                        status: statusMessage,
                                        canCopyResult: copyableResult != nil,
                                        translating: translationActive)
    }

    func barScreen() -> ScreenInfo? {
        guard let selection else { return nil }
        return geometry.screen(at: CGPoint(x: selection.minX, y: selection.maxY))
    }

    func handleBarItem(_ item: AnnotationBarLayout.Item) {
        AppLog.shared.write("点击工具栏 \(item)", level: .debug)
        switch item {
        case .tool(let kind):
            selectTool(tool == kind ? nil : kind)
        case .undo:
            undo()
        case .redo:
            redo()
        case .close:
            cancel()
        case .pin:
            perform(.pin, exit: true)
        case .save:
            saveAs()
        case .copy:
            perform(.copy, exit: false)        case .width:
            let widths: [CGFloat] = [2, 3, 4, 6, 8, 12, 16, 24]
            let index = widths.firstIndex(of: lineWidth) ?? 0
            lineWidth = widths[(index + 1) % widths.count]
        case .brushMode:
            rectangular.toggle()
        case .fill:
            filled.toggle()
        case .arrowStyle:
            let all = ArrowStyle.allCases
            let index = all.firstIndex(of: arrowStyle) ?? 0
            arrowStyle = all[(index + 1) % all.count]
        case .opacity:
            let values: [CGFloat] = [1, 0.75, 0.5, 0.25]
            let index = values.firstIndex(of: markerOpacity) ?? 2
            markerOpacity = values[(index + 1) % values.count]
        case .blockSize:
            let values: [CGFloat] = [8, 12, 16, 24, 32]
            let index = values.firstIndex(of: mosaicBlock) ?? 1
            mosaicBlock = values[(index + 1) % values.count]
        case .color(let index):
            colorIndex = index
        case .ocr:
            recognizeText(translate: false)
        case .translate:
            recognizeText(translate: true)
        case .qr:
            recognizeQR()
        case .resultCopy:
            copyResult()
        case .swapLang:
            swapLanguages()
        case .toggleOriginal:
            toggleOriginal()
        case .retry:
            retranslate()
        case .srcLang, .dstLang, .provider:
            break // 由视图弹出菜单
        }
        redraw()
    }

    func selectTool(_ kind: ToolKind?) {
        tool = kind
        if let kind { lineWidth = kind.defaultWidth }
        redraw()
    }

    // MARK: - 撤销

    private func saveUndo() {
        undoStack.append(shapes)
        redoStack.removeAll()
        if undoStack.count > 50 { undoStack.removeFirst() }
    }

    func undo() {
        guard let last = undoStack.popLast() else { return }
        redoStack.append(shapes)
        shapes = last
        invalidateLayer()
    }

    func redo() {
        guard let next = redoStack.popLast() else { return }
        undoStack.append(shapes)
        shapes = next
        invalidateLayer()
    }

    private func invalidateLayer() {
        layerDirty = true
        redraw()
    }

    func annotationLayerImage() -> CGImage? {
        if layerDirty {
            annotationLayer = AnnotationRenderer.renderLayer(shapes: renderedShapes,
                                                            geometry: geometry,
                                                            sampler: sampler)
            layerDirty = false
        }
        return annotationLayer
    }

    /// 正在绘制/编辑的对象也参与渲染，保证所见即所得。
    private var renderedShapes: [Shape] {
        var result = shapes
        if let currentShape { result.append(currentShape) }
        if let textEditing, !textEditing.text.isEmpty || !textEditing.marked.isEmpty {
            var shape = Shape(kind: .text, color: textEditing.color, lineWidth: 1)
            shape.text = textEditing.text + textEditing.marked
            shape.textOrigin = textEditing.origin
            shape.fontSize = textEditing.fontSize
            shape.fontFamily = textEditing.fontFamily
            result.append(shape)
        }
        return result
    }

    // MARK: - 输入

    func modelPoint(_ viewPoint: CGPoint, screen: ScreenInfo) -> CGPoint {
        CGPoint(x: viewPoint.x + screen.frame.minX, y: viewPoint.y + screen.frame.minY)
    }

    func mouseDown(at point: CGPoint, clickCount: Int) {
        guard !didFinish else { return }
        AppLog.shared.write("mouseDown click=\(clickCount) point=\(Int(point.x)),\(Int(point.y)) 已有选区=\(selection != nil)", level: .debug)
        if textEditing != nil { commitText() }

        if ocrActive, !ocrDocument.isEmpty, tool == nil {
            let local = ocrLocalPoint(point)
            let index = ocrDocument.hitTest(local, nearest: false, tolerance: 16 * ocrScale)
            if index >= 0 {
                ocrAnchor = index
                ocrEnd = index
                dragMode = .ocrSelect
                redraw()
                return
            }
        }

        if let selection {
            if let handle = model.handle(at: point) {
                dragMode = .resizing
                activeHandle = handle
                originalSelection = selection
                return
            }
            if selection.contains(point) {
                if let tool {
                    if tool == .text {
                        if let index = shapes.lastIndex(where: { $0.hitTest(point) }) {
                            beginEditingExistingText(at: index)
                        } else {
                            beginNewText(at: point)
                        }
                        return
                    }
                    dragMode = .drawing
                    beginShape(at: point)
                    return
                }
                // 双击动作推迟到 mouseUp 判断，避免"点一下就复制关闭"。
                dragMode = .moving
                anchor = point
                originalSelection = selection
                return
            }
        }

        dragMode = .creating
        anchor = model.clampedPoint(point)
        originalSelection = nil
        activeHandle = nil
        pressTarget = TargetResolver.windowFrame(at: point, excludingPID: getpid())
        selection = nil
        statusMessage = nil
        copyableResult = nil
        translationLayer = nil
        closeTranslation()
        ocrDocument = .empty
        ocrActive = false
        ocrAnchor = nil
        ocrEnd = nil
        closeOcrPanel()
        clearAnnotations()
        redraw()
    }

    func mouseDragged(to point: CGPoint) {
        guard !didFinish else { return }
        switch dragMode {
        case .creating:
            selection = model.normalized(anchor, point)
        case .moving:
            if let originalSelection {
                let delta = CGSize(width: point.x - anchor.x, height: point.y - anchor.y)
                selection = model.moved(originalSelection, by: delta)
            }
        case .resizing:
            if let activeHandle {
                selection = model.resized(activeHandle, to: point)
            }
        case .drawing:
            currentShape?.update(to: point)
            layerDirty = true
        case .ocrSelect:
            ocrEnd = ocrDocument.hitTest(ocrLocalPoint(point), nearest: true, tolerance: 16 * ocrScale)
            redraw()
            return
        case .none:
            break
        }
        hoverPoint = point
        redraw()
    }

    func mouseUp(at point: CGPoint, clickCount: Int = 1) {
        guard !didFinish else { return }
        AppLog.shared.write("mouseUp click=\(clickCount) drag=\(dragMode)", level: .debug)
        if clickCount >= 2, dragMode == .moving, let selection, originalSelection != nil,
           hypot(point.x - anchor.x, point.y - anchor.y) < 3 {
            AppLog.shared.write("双击选区 → 执行 \(settings.doubleClickAction.rawValue)")
            perform(settings.doubleClickAction, exit: settings.doubleClickExit)
            return
        }
        switch dragMode {
        case .creating:
            let current = selection ?? .zero
            if current.width < 3 || current.height < 3 {
                if let target = pressTarget?.intersection(geometry.union),
                   target.width >= 3, target.height >= 3 {
                    selection = target
                } else {
                    selection = nil
                }
            }
            if let selection, selection.width >= 3, selection.height >= 3 {
                switch mode {
                case .ocr: recognizeText(translate: false)
                case .translation: recognizeText(translate: true)
                case .qr: recognizeQR()
                case .capture: break
                }
                if autoCopy { perform(.copy, exit: true) }
            }
        case .drawing:
            commitShape()
        default:
            break
        }
        dragMode = .none
        activeHandle = nil
        originalSelection = nil
        pressTarget = nil
        if selection != nil { markSelectionCreated() }
        redraw()
    }

    func mouseMoved(to point: CGPoint) {
        guard !didFinish else { return }
        hoverPoint = point
        let now = Date()
        if now.timeIntervalSince(lastTargetUpdate) > 0.1 {
            lastTargetUpdate = now
            hoverTarget = TargetResolver.windowFrame(at: point, excludingPID: getpid())
        }
        redraw()
    }

    func middleClick() {
        perform(settings.middleClickAction, exit: settings.middleClickExit)
    }

    func modifiersChanged(_ flags: NSEvent.ModifierFlags) {
        let alt = flags.contains(.option)
        let shift = flags.contains(.shift)
        if alt != altPressed || shift != shiftPressed {
            altPressed = alt
            shiftPressed = shift
            redraw()
        }
    }

    func color(at model: CGPoint) -> RGBAColor? {
        let pixel = CGPoint(x: model.x * geometry.canvasScale, y: model.y * geometry.canvasScale)
        return sampler?.color(at: pixel)
    }

    func formattedColor(_ color: RGBAColor?) -> String {
        guard let color else { return "" }
        let r = Int((color.r * 255).rounded())
        let g = Int((color.g * 255).rounded())
        let b = Int((color.b * 255).rounded())
        if shiftPressed {
            return String(format: "#%02X%02X%02X", r, g, b)
        }
        return "\(r), \(g), \(b)"
    }

    func copyColorAtCursor() {
        guard let point = hoverPoint, let color = color(at: point) else { return }
        let text = formattedColor(color)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Toast.show("颜色已复制：\(text)")
    }

    func keyDown(_ event: NSEvent) -> Bool {
        guard !didFinish else { return false }
        if textEditing != nil { return false }
        AppLog.shared.write("keyDown code=\(event.keyCode) chars=\(event.charactersIgnoringModifiers ?? "-")", level: .debug)

        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)

        if flags.contains(.command) {
            switch event.charactersIgnoringModifiers?.lowercased() {
            case "z":
                if flags.contains(.shift) { redo() } else { undo() }
                return true
            case "c":
                if copyableResult != nil { copyResult() } else { perform(.copy, exit: false) }
                return true
            case "s":
                if flags.contains(.shift) { perform(.quickSave, exit: false) } else { saveAs() }
                return true
            case "a":
                if ocrActive { selectAllOcr() } else { selection = geometry.union; redraw() }
                return true
            case "t": perform(.pin, exit: true); return true
            default: return false
            }
        }

        switch event.keyCode {
        case 53:
            if ocrActive { clearOcr(); return true }
            cancel()
            return true
        case 36, 76: perform(settings.enterAction, exit: settings.enterExit); return true
        case 48: cycleRegion(backwards: flags.contains(.shift)); return true
        default: break
        }

        switch event.charactersIgnoringModifiers?.lowercased() {
        case "c":
            copyColorAtCursor()
            return true
        case "r": selectTool(.rectangle)
        case "e": selectTool(.ellipse)
        case "a": selectTool(.arrow)
        case "p": selectTool(.pen)
        case "m": selectTool(.marker)
        case "x": selectTool(.mosaic)
        case "t": selectTool(.text)
        case "h": selectTool(.eraser)
        default: return false
        }
        return true
    }

    func cancel() {
        guard !didFinish else { return }
        AppLog.shared.write("取消截图")
        if textEditing != nil { cancelText(); return }
        if settings.confirmEscape, selection != nil {
            let alert = NSAlert()
            alert.messageText = "退出当前截图？"
            alert.informativeText = "当前选区不会被保存。"
            alert.addButton(withTitle: "退出")
            alert.addButton(withTitle: "继续截图")
            alert.window.level = .screenSaver
            NSApp.activate(ignoringOtherApps: true)
            if alert.runModal() != .alertFirstButtonReturn { return }
        }
        close()
    }

    // MARK: - 形状

    private func beginShape(at point: CGPoint) {
        guard let tool else { return }
        saveUndo()
        var shape = Shape.make(tool: tool, at: point, color: currentColor,
                               lineWidth: lineWidth, fontSize: 16)
        shape.arrowStyle = arrowStyle
        shape.filled = filled
        shape.opacity = markerOpacity
        shape.blockSize = mosaicBlock
        shape.rectangular = rectangular
        currentShape = shape
        layerDirty = true
    }

    private func commitShape() {
        guard let shape = currentShape else { return }
        currentShape = nil
        if shape.isEmpty {
            if !undoStack.isEmpty { undoStack.removeLast() }
        } else if shape.kind == .text {
            shapes.append(shape)
        } else {
            shapes.append(shape)
        }
        layerDirty = true
    }

    private func clearAnnotations() {
        shapes.removeAll()
        undoStack.removeAll()
        redoStack.removeAll()
        currentShape = nil
        textEditing = nil
        layerDirty = true
    }

    // MARK: - 文字

    private func beginEditingExistingText(at index: Int) {
        saveUndo()
        let shape = shapes[index]
        textEditing = TextEditing(origin: shape.textOrigin, text: shape.text, isNew: false,
                                  shapeIndex: index, color: shape.color,
                                  fontSize: shape.fontSize, fontFamily: shape.fontFamily)
        redraw()
    }

    func beginNewText(at point: CGPoint) {
        saveUndo()
        textEditing = TextEditing(origin: point, isNew: true, shapeIndex: nil,
                                  color: currentColor, fontSize: 16)
        redraw()
    }

    func updateText(_ text: String) {
        textEditing?.text = text
        layerDirty = true
        redraw()
    }

    func updateMarkedText(_ marked: String) {
        textEditing?.marked = marked
        layerDirty = true
        redraw()
    }

    func commitText() {
        guard let editing = textEditing else { return }
        textEditing = nil
        let text = editing.text
        if let index = editing.shapeIndex {
            if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                shapes.remove(at: index)
            } else {
                shapes[index].text = text
            }
        } else if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            var shape = Shape(kind: .text, color: editing.color, lineWidth: 1)
            shape.text = text
            shape.textOrigin = editing.origin
            shape.fontSize = editing.fontSize
            shape.fontFamily = editing.fontFamily
            shapes.append(shape)
        } else if !undoStack.isEmpty {
            undoStack.removeLast()
        }
        layerDirty = true
        redraw()
    }

    func cancelText() {
        guard let editing = textEditing else { return }
        textEditing = nil
        if editing.isNew, !undoStack.isEmpty { undoStack.removeLast() }
        layerDirty = true
        redraw()
    }

    // MARK: - 识别 / 翻译

    func cropImage(includeAnnotations: Bool) -> CGImage? {
        guard let selection else { return nil }
        let rect = geometry.canvasRect(for: selection).integral
        let bounds = CGRect(x: 0, y: 0, width: capturedImage.width, height: capturedImage.height)
        let crop = rect.intersection(bounds)
        guard crop.width >= 1, crop.height >= 1 else { return nil }
        if includeAnnotations {
            return ImageComposer.composite(base: capturedImage, layer: annotationLayerImage(), crop: crop)
        }
        return capturedImage.cropping(to: crop)
    }

    func recognizeText(translate: Bool) {
        guard let selection, let crop = cropImage(includeAnnotations: !translate) else { return }
        recognitionTask?.cancel()
        statusMessage = "正在识别文字…"
        copyableResult = nil
        translationLayer = nil
        redraw()

        let origin = selection.origin
        let scale = geometry.canvasScale
        AppLog.shared.write("OCR 开始 \(crop.width)×\(crop.height)")
        recognitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let document = try await Task.detached(priority: .userInitiated) {
                    try VisionOcrEngine.recognize(crop)
                }.value
                guard !Task.isCancelled else { return }
                AppLog.shared.write("OCR 完成 字数=\(document.characters.count)")
                self.ocrDocument = document
                self.ocrOrigin = origin
                self.ocrScale = scale
                if document.isEmpty {
                    self.statusMessage = "未识别到文字，请调整选区"
                    self.copyableResult = nil
                } else {
                    self.ocrActive = !translate
                    self.ocrAnchor = nil
                    self.ocrEnd = nil
                    self.statusMessage = translate
                        ? "识别到 \(document.characters.count) 字"
                        : "识别到 \(document.characters.count) 字 · 拖动选字 · ⌘A 全选 · ⌘C 复制"
                    self.copyableResult = document.text
                }
                self.redraw()
                if translate, !document.isEmpty {
                    self.startTranslation(base: crop)
                } else if !document.isEmpty {
                    self.showOcrPanel(document.text)
                }
            } catch {
                guard !Task.isCancelled else { return }
                AppLog.shared.writeError("OCR 失败", error: error)
                self.statusMessage = "识别失败：\(error.localizedDescription)"
                self.redraw()
            }
        }
    }

    private func startTranslation(base: CGImage) {
        let blocks = TranslationOverlayBuilder.blocks(from: ocrDocument)
        guard !blocks.isEmpty else { return }
        translationBase = base
        translationActive = true
        showOriginal = false
        statusMessage = "正在翻译…"
        redraw()

        let source = currentSource
        let target = currentTarget
        let provider = TranslationServices.make(currentProvider)
        recognitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let results = try await Self.translateBlocks(blocks,
                                                             provider: provider,
                                                             source: source,
                                                             target: target)
                guard !Task.isCancelled else { return }
                let sampler = BitmapSampler(cgImage: base)
                self.translationLayer = TranslationOverlayRenderer.render(base: base,
                                                                         blocks: blocks,
                                                                         translations: results,
                                                                         sampler: sampler)
                self.statusMessage = "已翻译 · ⌘C 复制译文"
                self.copyableResult = results.joined(separator: "\n")
                self.redraw()
            } catch {
                guard !Task.isCancelled else { return }
                self.statusMessage = error.localizedDescription
                self.redraw()
            }
        }
    }

    /// 最多两个 block 并发翻译，保持顺序。
    nonisolated private static func translateBlocks(_ blocks: [TranslationBlock],
                                                    provider: TranslationProvider,
                                                    source: String,
                                                    target: String) async throws -> [String] {
        var results = [String](repeating: "", count: blocks.count)
        try await withThrowingTaskGroup(of: (Int, String).self) { group in
            var next = 0
            let limit = 2

            func addTask(_ index: Int) {
                let text = blocks[index].text
                group.addTask {
                    if text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        return (index, "")
                    }
                    let result = try await provider.translate(text, source: source, target: target)
                    return (index, result.text)
                }
            }

            while next < blocks.count && next < limit {
                addTask(next)
                next += 1
            }
            while let (index, text) = try await group.next() {
                results[index] = text
                if next < blocks.count {
                    addTask(next)
                    next += 1
                }
            }
        }
        return results
    }

    func recognizeQR() {
        guard let crop = cropImage(includeAnnotations: true) else { return }
        recognitionTask?.cancel()
        statusMessage = "正在识别二维码…"
        copyableResult = nil
        translationLayer = nil
        redraw()

        recognitionTask = Task { @MainActor [weak self] in
            guard let self else { return }
            do {
                let value = try await Task.detached(priority: .userInitiated) {
                    try VisionBarcodeScanner.scan(crop)
                }.value
                guard !Task.isCancelled else { return }
                if let value, !value.isEmpty {
                    self.statusMessage = "二维码：\(value)"
                    self.copyableResult = value
                } else {
                    self.statusMessage = "未检测到二维码 / 条码"
                    self.copyableResult = nil
                }
                self.redraw()
            } catch {
                self.statusMessage = "识别失败：\(error.localizedDescription)"
                self.redraw()
            }
        }
    }

    func copyResult() {
        let text = selectedOcrText.flatMap { $0.isEmpty ? nil : $0 } ?? copyableResult
        guard let text else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        statusMessage = selectedOcrText?.isEmpty == false ? "已复制选中文字" : "已复制"
        redraw()
    }

    // MARK: - OCR 划词

    private func ocrLocalPoint(_ model: CGPoint) -> CGPoint {
        CGPoint(x: (model.x - ocrOrigin.x) * ocrScale,
                y: (model.y - ocrOrigin.y) * ocrScale)
    }

    var ocrSelectionRange: ClosedRange<Int>? {
        guard let anchor = ocrAnchor, let end = ocrEnd, !ocrDocument.characters.isEmpty else { return nil }
        let start = min(anchor, end)
        let finish = max(anchor, end)
        guard start >= 0, finish < ocrDocument.characters.count else { return nil }
        return start...finish
    }

    var selectedOcrText: String? {
        guard let range = ocrSelectionRange else { return nil }
        return ocrDocument.getText(from: range.lowerBound, to: range.upperBound)
    }

    func ocrCharacterRects() -> [(rect: CGRect, selected: Bool)] {
        guard !ocrDocument.isEmpty else { return [] }
        let range = ocrSelectionRange
        return ocrDocument.characters.enumerated().map { index, character in
            let bounds = character.bounds
            let rect = CGRect(x: ocrOrigin.x + bounds.minX / ocrScale,
                              y: ocrOrigin.y + bounds.minY / ocrScale,
                              width: bounds.width / ocrScale,
                              height: bounds.height / ocrScale)
            return (rect, range?.contains(index) ?? false)
        }
    }

    func selectAllOcr() {
        guard !ocrDocument.isEmpty else { return }
        ocrAnchor = 0
        ocrEnd = ocrDocument.characters.count - 1
        redraw()
    }

    func clearOcr() {
        ocrActive = false
        ocrDocument = .empty
        ocrAnchor = nil
        ocrEnd = nil
        copyableResult = nil
        statusMessage = nil
        redraw()
    }

    // MARK: - 翻译控件

    func setSourceLanguage(_ code: String) {
        currentSource = code
        persistTranslationSettings()
        retranslate()
    }

    func setTargetLanguage(_ code: String) {
        guard code != "auto" else { return }
        currentTarget = code
        persistTranslationSettings()
        retranslate()
    }

    func setProvider(_ kind: TranslationProviderKind) {
        currentProvider = kind
        persistTranslationSettings()
        retranslate()
    }

    func swapLanguages() {
        let source = currentSource == "auto" ? "en" : currentSource
        currentSource = currentTarget
        currentTarget = source
        persistTranslationSettings()
        retranslate()
    }

    func toggleOriginal() {
        showOriginal.toggle()
        redraw()
    }

    func retranslate() {
        guard let base = translationBase else {
            recognizeText(translate: true)
            return
        }
        startTranslation(base: base)
    }

    func closeTranslation() {
        translationLayer = nil
        translationBase = nil
        translationActive = false
        showOriginal = false
    }

    private func persistTranslationSettings() {
        let source = currentSource
        let target = currentTarget
        let provider = currentProvider
        SettingsStore.shared.update {
            $0.translationSourceLanguage = source
            $0.translationTargetLanguage = target
            $0.translationProvider = provider
        }
    }

    private var ocrPanel: OcrResultPanel?

    private func showOcrPanel(_ text: String) {
        closeOcrPanel()
        let panel = OcrResultPanel(text: text)
        panel.onClose = { [weak self] in
            guard let self else { return }
            self.ocrPanel = nil
            self.focusOverlay()
        }
        if let layout = barLayout() {
            let cocoa = geometry.toCocoa(CGPoint(x: layout.frame.minX, y: layout.frame.maxY + 8))
            panel.setFrameTopLeftPoint(cocoa)
            if let screen = NSScreen.screens.first(where: { $0.frame.contains(cocoa) }) {
                var origin = panel.frame.origin
                origin.x = min(max(origin.x, screen.visibleFrame.minX + 8),
                               screen.visibleFrame.maxX - panel.frame.width - 8)
                origin.y = min(max(origin.y, screen.visibleFrame.minY + 8),
                               screen.visibleFrame.maxY - panel.frame.height - 8)
                panel.setFrameOrigin(origin)
            }
        }
        panel.makeKeyAndOrderFront(nil)
        ocrPanel = panel
    }

    private func closeOcrPanel() {
        guard let panel = ocrPanel else { return }
        ocrPanel = nil
        panel.onClose = nil
        panel.close()
    }

    private func focusOverlay() {
        // 面板关闭后恢复遮罩窗口的布局，避免内容视图被系统改小。
        for window in windows {
            guard let view = window.contentView else { continue }
            let expected = window.contentLayoutRect.size
            if view.frame.size != expected {
                view.frame = NSRect(origin: .zero, size: expected)
            }
            view.needsDisplay = true
        }
        guard let view = windows.first?.contentView else { return }
        view.window?.makeKey()
        view.window?.makeFirstResponder(view)
    }

    // MARK: - 输出

    func perform(_ action: CaptureAction, exit: Bool) {
        guard !didFinish else { return }
        if action == .copy {
            let frames = Thread.callStackSymbols.prefix(8).joined(separator: " <- ")
            AppLog.shared.write("copy 调用栈：\(frames)", level: .debug)
        }
        AppLog.shared.write("执行输出动作 \(action.rawValue) exit=\(exit)")
        if textEditing != nil { commitText() }
        guard action != .none else {
            if exit { close() }
            return
        }
        guard let selection, let image = croppedImage() else { return }

        CaptureHistory.shared.add(image: image, bounds: selection)
        if exit { close() }
        remember(selection)

        switch action {
        case .copy:
            if OutputService.copyToPasteboard(image) {
                Toast.show("已复制到剪贴板，可继续编辑（Esc 退出）")
            } else {
                Toast.show("复制失败")
            }
        case .quickSave:
            do {
                let url = try OutputService.quickSave(image, settings: settings)
                Toast.show("已保存：\(url.lastPathComponent)")
            } catch {
                AppLog.shared.writeError("快速保存失败", error: error)
                Toast.show("保存失败")
            }
        case .pin:
            let topLeft = geometry.toCocoa(CGPoint(x: selection.minX, y: selection.minY))
            PinController.shared.pin(image: image, topLeft: topLeft)
            Toast.show("已贴图 · 右键更多操作")
        case .none:
            break
        }
    }

    private func saveAs() {
        guard let selection, let image = croppedImage() else { return }
        let defaultName = FileNamePattern.fileName(pattern: settings.fileNamePattern, extension: "png")

        hideOverlay()
        defer { if !didFinish { showOverlay() } }
        guard let url = OutputService.chooseSaveURL(defaultName: defaultName) else { return }
        do {
            try OutputService.write(image, to: url, jpegQuality: settings.jpegQuality)
            remember(selection)
            close()
            Toast.show("已保存：\(url.lastPathComponent)")
        } catch {
            AppLog.shared.writeError("保存失败", error: error)
            Toast.show("保存失败")
        }
    }

    func croppedImage() -> CGImage? {
        guard let selection, selection.width >= 1, selection.height >= 1 else { return nil }
        let canvasRect = geometry.canvasRect(for: selection).integral
        let imageBounds = CGRect(x: 0, y: 0, width: capturedImage.width, height: capturedImage.height)
        let crop = canvasRect.intersection(imageBounds)
        guard crop.width >= 1, crop.height >= 1,
              let base = capturedImage.cropping(to: crop) else { return nil }

        var layers: [CGImage] = []
        if let translationLayer { layers.append(translationLayer) }
        if let annotation = annotationLayerImage()?.cropping(to: crop) { layers.append(annotation) }
        return ImageComposer.overlay(base: base, layers: layers)
    }

    private func remember(_ selection: CGRect) {
        SettingsStore.shared.update { $0.rememberRegion(CaptureRegion(rect: selection)) }
    }

    private func cycleRegion(backwards: Bool) {
        let regions = settings.recentRegions
        guard !regions.isEmpty else { return }
        let currentIndex = selection.flatMap { current in
            regions.firstIndex { $0.rect.equalTo(current) }
        }
        var next: Int
        if let currentIndex {
            next = backwards ? currentIndex - 1 : currentIndex + 1
            if next < 0 { next = settings.cycleHistoryRegions ? regions.count - 1 : 0 }
            if next >= regions.count { next = settings.cycleHistoryRegions ? 0 : regions.count - 1 }
        } else {
            next = 0
        }
        selection = model.clamped(regions[next].rect)
        clearAnnotations()
        redraw()
    }

    // MARK: - 错误

    private static func presentError(_ error: Error) {
        let alert = NSAlert()
        alert.messageText = "无法截图"
        alert.informativeText = error.localizedDescription
        alert.addButton(withTitle: "打开屏幕录制设置")
        alert.addButton(withTitle: "好")
        alert.window.level = .screenSaver

        NSApp.activate(ignoringOtherApps: true)
        if alert.runModal() == .alertFirstButtonReturn {
            Permissions.openScreenRecordingSettings()
        }
    }
}

private extension CGRect {
    func equalTo(_ other: CGRect) -> Bool {
        minX.rounded() == other.minX.rounded()
            && minY.rounded() == other.minY.rounded()
            && width.rounded() == other.width.rounded()
            && height.rounded() == other.height.rounded()
    }
}

extension CaptureSession {
    var editingTextLength: Int { (textEditing?.text ?? "").utf16.count }

    func appendText(_ text: String) {
        guard var editing = textEditing else { return }
        editing.text += text
        editing.marked = ""
        textEditing = editing
        layerDirty = true
        redraw()
    }

    func deleteBackwardText() {
        guard var editing = textEditing else { return }
        if !editing.marked.isEmpty {
            editing.marked = ""
        } else if !editing.text.isEmpty {
            editing.text.removeLast()
        }
        textEditing = editing
        layerDirty = true
        redraw()
    }
}
