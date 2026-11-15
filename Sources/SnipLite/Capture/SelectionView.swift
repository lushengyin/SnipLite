import AppKit
import SnipLiteCore

/// 每块屏幕一个遮罩视图：冻结桌面、标注层、遮罩、选区、工具栏、放大镜。
final class SelectionView: NSView {
    private unowned let session: CaptureSession
    private let screen: ScreenInfo
    private var trackingArea: NSTrackingArea?

    private let accent = NSColor(srgbRed: 0, green: 0.5686, blue: 0.9176, alpha: 1)

    init(session: CaptureSession, screen: ScreenInfo) {
        self.session = session
        self.screen = screen
        super.init(frame: NSRect(origin: .zero, size: screen.frame.size))
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

    // MARK: - 绘制

    override func draw(_ dirtyRect: NSRect) {
        drawFrozenDesktop()
        drawTranslationLayer()
        drawAnnotationLayer()
        drawMask()
        drawHoverTarget()
        drawSelection()
        drawOcrHighlights()
        if session.selection == nil {
            drawCrosshair()
            drawMagnifier()
        }
        drawSizeBadge()
        drawTextCaret()
        drawBar()
    }

    private func drawFrozenDesktop() {
        let union = session.geometry.union
        let destination = NSRect(x: -screen.frame.minX,
                                 y: -screen.frame.minY,
                                 width: union.width,
                                 height: union.height)
        drawCanvasImage(session.capturedImage, in: destination,
                        interpolation: .none, blend: .copy)
    }

    /// 在 flipped 视图里绘制整幅画布图像，坐标用视图本地坐标（左上原点）。
    private func drawCanvasImage(_ image: CGImage, in destination: NSRect,
                                 interpolation: CGInterpolationQuality,
                                 fraction: CGFloat = 1,
                                 blend: CGBlendMode = .normal) {
        guard let context = NSGraphicsContext.current?.cgContext else { return }
        context.saveGState()
        context.interpolationQuality = interpolation
        context.setAlpha(fraction)
        context.setBlendMode(blend)
        context.translateBy(x: 0, y: bounds.height)
        context.scaleBy(x: 1, y: -1)
        let flipped = CGRect(x: destination.minX,
                             y: bounds.height - destination.maxY,
                             width: destination.width,
                             height: destination.height)
        context.draw(image, in: flipped)
        context.restoreGState()
    }

    private func drawTranslationLayer() {
        guard !session.showOriginal,
              let layer = session.translationLayer,
              let selection = session.selection else { return }
        drawCanvasImage(layer, in: localRect(selection),
                        interpolation: .high, blend: .normal)
    }

    private func drawAnnotationLayer() {
        guard let layer = session.annotationLayerImage() else { return }
        let union = session.geometry.union
        drawCanvasImage(layer,
                        in: NSRect(x: -screen.frame.minX, y: -screen.frame.minY,
                                   width: union.width, height: union.height),
                        interpolation: .none, blend: .normal)
    }

    private func drawMask() {
        let path = NSBezierPath(rect: bounds)
        if let selection = session.selection {
            path.appendRect(localRect(selection))
            path.windingRule = .evenOdd
        }
        let alpha = CGFloat(session.settings.maskOpacity) / 255.0
        NSColor(srgbRed: 0, green: 0, blue: 0, alpha: alpha).setFill()
        path.fill()
    }

    private func drawHoverTarget() {
        guard session.selection == nil, let target = session.hoverTarget else { return }
        let rect = localRect(target.intersection(session.geometry.union))
        guard !rect.isEmpty else { return }
        let line = 1.0 / screen.scale
        let path = NSBezierPath(rect: rect.insetBy(dx: line / 2, dy: line / 2))
        accent.withAlphaComponent(0.12).setFill()
        path.fill()
        path.lineWidth = line * 2
        accent.setStroke()
        path.stroke()
    }

    private func drawSelection() {
        guard let selection = session.selection, selection.width >= 1, selection.height >= 1 else { return }
        let rect = localRect(selection)
        let line = 1.0 / screen.scale

        let border = NSBezierPath(rect: rect.insetBy(dx: line / 2, dy: line / 2))
        border.lineWidth = line
        accent.setStroke()
        border.stroke()

        guard session.settings.captureAnchors, session.tool == nil, session.textEditing == nil else { return }
        let size: CGFloat = 6
        for (_, center) in SelectionModel(bounds: session.geometry.union).handles(for: selection) {
            let handleRect = CGRect(x: center.x - size / 2, y: center.y - size / 2,
                                    width: size, height: size)
            let path = NSBezierPath(rect: localRect(handleRect))
            NSColor.white.setFill()
            path.fill()
            path.lineWidth = line
            NSColor(white: 0.25, alpha: 1).setStroke()
            path.stroke()
        }
    }

    private func drawOcrHighlights() {
        guard session.ocrActive else { return }
        let rects = session.ocrCharacterRects()
        guard !rects.isEmpty else { return }
        let line = 1.0 / screen.scale
        for (rect, selected) in rects {
            let local = localRect(rect)
            if selected {
                accent.withAlphaComponent(0.38).setFill()
                NSBezierPath(rect: local).fill()
            } else {
                let underline = NSBezierPath()
                underline.move(to: CGPoint(x: local.minX, y: local.maxY - line))
                underline.line(to: CGPoint(x: local.maxX, y: local.maxY - line))
                underline.lineWidth = line
                accent.setStroke()
                underline.stroke()
            }
        }
    }

    private func drawCrosshair() {
        guard session.settings.showCrosshair, let point = session.hoverPoint else { return }
        let local = localPoint(point)
        let line = 1.0 / screen.scale
        let path = NSBezierPath()
        path.move(to: CGPoint(x: bounds.minX, y: local.y))
        path.line(to: CGPoint(x: bounds.maxX, y: local.y))
        path.move(to: CGPoint(x: local.x, y: bounds.minY))
        path.line(to: CGPoint(x: local.x, y: bounds.maxY))
        path.lineWidth = line
        NSColor(white: 1, alpha: 0.75).setStroke()
        path.stroke()
    }

    private func drawMagnifier() {
        guard let point = session.hoverPoint else { return }
        guard session.altPressed || session.settings.autoMagnifier else { return }

        let unit: CGFloat = 168
        let zoom = CGFloat(session.settings.magnifierZoom)
        let sourceHalf = max(1, (unit / zoom / 2).rounded())
        let center = localPoint(point)

        var origin = CGPoint(x: center.x + 24, y: center.y + 24)
        if origin.x + unit > bounds.maxX { origin.x = center.x - 24 - unit }
        if origin.y + unit > bounds.maxY { origin.y = center.y - 24 - unit }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - unit - 4)
        origin.y = min(max(origin.y, bounds.minY + 4), bounds.maxY - unit - 4)
        let destination = CGRect(x: origin.x, y: origin.y, width: unit, height: unit)

        let sourceTopLeft = CGRect(x: point.x - sourceHalf, y: point.y - sourceHalf,
                                   width: sourceHalf * 2, height: sourceHalf * 2)
        let scale = session.geometry.canvasScale
        let sourcePixels = CGRect(x: sourceTopLeft.minX * scale,
                                  y: sourceTopLeft.minY * scale,
                                  width: sourceTopLeft.width * scale,
                                  height: sourceTopLeft.height * scale).integral

        NSGraphicsContext.current?.saveGraphicsState()
        defer { NSGraphicsContext.current?.restoreGraphicsState() }

        NSBezierPath(rect: destination).addClip()
        NSColor.black.setFill()
        destination.fill()
        if let cropped = session.capturedImage.cropping(to: sourcePixels) {
            drawCanvasImage(cropped, in: destination, interpolation: .none, blend: .copy)
        }

        let border = NSBezierPath(rect: destination.insetBy(dx: 0.5, dy: 0.5))
        border.lineWidth = 1
        NSColor(white: 1, alpha: 0.75).setStroke()
        border.stroke()

        let reticle = NSBezierPath()
        reticle.move(to: CGPoint(x: destination.midX - 8, y: destination.midY))
        reticle.line(to: CGPoint(x: destination.midX + 8, y: destination.midY))
        reticle.move(to: CGPoint(x: destination.midX, y: destination.midY - 8))
        reticle.line(to: CGPoint(x: destination.midX, y: destination.midY + 8))
        reticle.lineWidth = 1
        NSColor(white: 0, alpha: 0.8).setStroke()
        reticle.stroke()

        let colorValue = session.formattedColor(session.color(at: point))
        let label = colorValue.isEmpty
            ? "\(Int(point.x.rounded())) , \(Int(point.y.rounded()))"
            : "\(Int(point.x.rounded())), \(Int(point.y.rounded()))  \(colorValue)"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (label as NSString).size(withAttributes: attributes)
        let labelRect = CGRect(x: destination.minX + 6,
                               y: destination.maxY - size.height - 5,
                               width: size.width + 8,
                               height: size.height + 2)
        NSColor(white: 0, alpha: 0.6).setFill()
        NSBezierPath(roundedRect: labelRect, xRadius: 3, yRadius: 3).fill()
        (label as NSString).draw(at: CGPoint(x: labelRect.minX + 4, y: labelRect.minY + 1),
                                 withAttributes: attributes)
    }

    private func drawSizeBadge() {
        guard let selection = session.selection,
              selection.width >= 1, selection.height >= 1 else { return }
        // 选区不在本屏时不要画，否则多屏下徽标会被夹到另一块屏幕边缘。
        guard selection.intersects(screen.frame) else { return }
        guard !(selection.width < 2 && session.settings.hideOnePixelHint) else { return }

        let pixel = session.geometry.pixelSize(of: selection)
        let text = "\(Int(pixel.width)) × \(Int(pixel.height))"
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .semibold),
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let rect = localRect(selection)

        var origin = CGPoint(x: rect.minX, y: rect.minY - textSize.height - 10)
        if origin.y < bounds.minY + 2 { origin.y = rect.minY + 6 }
        origin.x = min(max(origin.x, bounds.minX + 2), bounds.maxX - textSize.width - 12)
        let badge = CGRect(x: origin.x, y: origin.y,
                           width: textSize.width + 12, height: textSize.height + 6)

        NSColor(white: 0, alpha: 0.62).setFill()
        NSBezierPath(roundedRect: badge, xRadius: 4, yRadius: 4).fill()
        (text as NSString).draw(at: CGPoint(x: badge.minX + 6, y: badge.minY + 3),
                                withAttributes: attributes)
    }

    private func drawTextCaret() {
        guard let editing = session.textEditing else { return }
        let text = editing.text + editing.marked
        let bounds = AnnotationMetrics.textBounds(text: text, family: editing.fontFamily,
                                                  size: editing.fontSize, bold: false,
                                                  italic: false, origin: editing.origin)
        let caret = localRect(CGRect(x: bounds.maxX + 1, y: editing.origin.y,
                                     width: 1.5, height: editing.fontSize * 1.25))
        accent.setFill()
        NSBezierPath(rect: caret).fill()
    }

    // MARK: - 工具栏

    private var isBarHost: Bool {
        session.barScreen()?.displayID == screen.displayID
    }

    private func drawBar() {
        guard isBarHost, let layout = session.barLayout() else { return }
        let frame = localRect(layout.frame)

        NSColor(white: 0.11, alpha: 0.94).setFill()
        let background = NSBezierPath(roundedRect: frame, xRadius: 8, yRadius: 8)
        background.fill()
        NSColor(white: 1, alpha: 0.08).setStroke()
        background.lineWidth = 1
        background.stroke()

        for (item, rect) in layout.items {
            let local = localRect(rect)
            switch item {
            case .color(let index):
                let color = NSColor(cgColor: RGBAColor.palette[index].cgColor) ?? .red
                let swatch = NSBezierPath(roundedRect: local, xRadius: 3, yRadius: 3)
                color.setFill()
                swatch.fill()
                if index == session.colorIndex {
                    NSColor.white.setStroke()
                    swatch.lineWidth = 2
                    swatch.stroke()
                }
            case .undo:
                drawButton(local, icon: "arrow.uturn.backward", selected: false, enabled: session.canUndo)
            case .redo:
                drawButton(local, icon: "arrow.uturn.forward", selected: false, enabled: session.canRedo)
            case .tool(let kind):
                drawButton(local, icon: BarIcon.image(for: item), selected: session.tool == kind, enabled: true)
                _ = kind
            case .width, .brushMode, .fill, .arrowStyle, .opacity, .blockSize:
                drawOption(local, item: item)
            case .resultCopy:
                drawPill(local, text: "复制")
            case .srcLang:
                drawPill(local, text: session.sourceTitle)
            case .dstLang:
                drawPill(local, text: session.targetTitle)
            case .provider:
                drawPill(local, text: session.providerTitle)
            case .toggleOriginal:
                drawPill(local, text: session.showOriginal ? "显示译文" : "显示原文")
            case .retry:
                drawPill(local, text: "重试")
            default:
                drawButton(local, icon: BarIcon.image(for: item), selected: false, enabled: true)
            }
        }

        if let text = layout.statusText, let rect = layout.statusRect {
            let local = localRect(rect)
            let attributes: [NSAttributedString.Key: Any] = [
                .font: NSFont.systemFont(ofSize: 11, weight: .regular),
                .foregroundColor: NSColor(white: 1, alpha: 0.82)
            ]
            (text as NSString).draw(in: local, withAttributes: attributes)
        }

        if let hovered = session.hoveredBarItem, let rect = layout.rect(for: hovered) {
            drawHint(hovered.hint, above: localRect(rect))
        }
    }

    private func drawHint(_ text: String, above itemRect: CGRect) {
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let textSize = (text as NSString).size(withAttributes: attributes)
        let width = textSize.width + 16
        let height = textSize.height + 8

        var origin = CGPoint(x: itemRect.midX - width / 2, y: itemRect.minY - height - 7)
        if origin.y < bounds.minY + 4 { origin.y = itemRect.maxY + 7 }
        origin.x = min(max(origin.x, bounds.minX + 4), bounds.maxX - width - 4)
        let rect = CGRect(x: origin.x, y: origin.y, width: width, height: height)

        NSColor(white: 0.07, alpha: 0.96).setFill()
        let path = NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5)
        path.fill()
        NSColor(white: 1, alpha: 0.14).setStroke()
        path.lineWidth = 1
        path.stroke()
        (text as NSString).draw(at: CGPoint(x: rect.minX + 8, y: rect.minY + 4),
                                withAttributes: attributes)
    }

    private func drawButton(_ rect: CGRect, icon: String?, selected: Bool, enabled: Bool) {
        if selected {
            accent.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        }
        let image = icon.flatMap { NSImage(systemSymbolName: $0, accessibilityDescription: nil) }
        guard let image else { return }
        let tint = enabled ? NSColor.white : NSColor(white: 1, alpha: 0.28)
        let size: CGFloat = 17
        let target = CGRect(x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size)
        tinted(image, color: tint).draw(in: target)
    }

    private func drawButton(_ rect: CGRect, icon: NSImage?, selected: Bool, enabled: Bool) {
        if selected {
            accent.setFill()
            NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        }
        guard let icon else { return }
        let tint = enabled ? NSColor.white : NSColor(white: 1, alpha: 0.28)
        let size: CGFloat = 17
        let target = CGRect(x: rect.midX - size / 2, y: rect.midY - size / 2, width: size, height: size)
        tinted(icon, color: tint).draw(in: target)
    }

    private func drawPill(_ rect: CGRect, text: String) {
        NSColor(white: 1, alpha: 0.16).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (text as NSString).size(withAttributes: attributes)
        (text as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2,
                                            y: rect.midY - size.height / 2),
                                withAttributes: attributes)
    }

    private func drawOption(_ rect: CGRect, item: AnnotationBarLayout.Item) {
        guard let label = BarIcon.optionLabel(item,
                                             lineWidth: session.lineWidth,
                                             filled: session.filled,
                                             arrowStyle: session.arrowStyle,
                                             opacity: session.markerOpacity,
                                             blockSize: session.mosaicBlock,
                                             rectangular: session.rectangular) else { return }
        NSColor(white: 1, alpha: 0.12).setFill()
        NSBezierPath(roundedRect: rect, xRadius: 5, yRadius: 5).fill()
        let attributes: [NSAttributedString.Key: Any] = [
            .font: NSFont.systemFont(ofSize: 11, weight: .medium),
            .foregroundColor: NSColor.white
        ]
        let size = (label as NSString).size(withAttributes: attributes)
        (label as NSString).draw(at: CGPoint(x: rect.midX - size.width / 2,
                                             y: rect.midY - size.height / 2),
                                 withAttributes: attributes)
    }

    private func tinted(_ image: NSImage, color: NSColor) -> NSImage {
        let result = NSImage(size: image.size)
        result.lockFocus()
        image.draw(in: NSRect(origin: .zero, size: image.size))
        color.set()
        NSRect(origin: .zero, size: image.size).fill(using: .sourceAtop)
        result.unlockFocus()
        return result
    }

    // MARK: - 翻译菜单

    private func showLanguageMenu(source: Bool, from rect: CGRect) {
        let menu = NSMenu()
        for language in session.languages {
            if !source && language.code == "auto" { continue }
            let item = NSMenuItem(title: language.title, action: #selector(pickLanguage(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = language.code
            item.tag = source ? 0 : 1
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: localRect(rect).midX, y: localRect(rect).midY), in: self)
    }

    private func showProviderMenu(from rect: CGRect) {
        let menu = NSMenu()
        for provider in session.providers {
            let item = NSMenuItem(title: provider.title + (provider.isAvailable ? "" : "（未接入）"),
                                  action: #selector(pickProvider(_:)), keyEquivalent: "")
            item.target = self
            item.representedObject = provider.rawValue
            item.isEnabled = provider.isAvailable
            menu.addItem(item)
        }
        menu.popUp(positioning: nil, at: NSPoint(x: localRect(rect).midX, y: localRect(rect).midY), in: self)
    }

    @objc private func pickLanguage(_ sender: NSMenuItem) {
        guard let code = sender.representedObject as? String else { return }
        if sender.tag == 0 {
            session.setSourceLanguage(code)
        } else {
            session.setTargetLanguage(code)
        }
    }

    @objc private func pickProvider(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
              let kind = TranslationProviderKind(rawValue: raw) else { return }
        session.setProvider(kind)
    }

    // MARK: - 坐标

    private func localPoint(_ model: CGPoint) -> CGPoint {
        CGPoint(x: model.x - screen.frame.minX, y: model.y - screen.frame.minY)
    }

    private func localRect(_ model: CGRect) -> CGRect {
        CGRect(x: model.minX - screen.frame.minX,
               y: model.minY - screen.frame.minY,
               width: model.width,
               height: model.height)
    }

    private func modelPoint(_ event: NSEvent) -> CGPoint {
        let local = convert(event.locationInWindow, from: nil)
        return session.modelPoint(local, screen: screen)
    }

    // MARK: - 事件

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = modelPoint(event)

        if isBarHost, let layout = session.barLayout(),
           Date().timeIntervalSince(session.selectionCreatedAt) > 0.2,
           let item = layout.item(at: point) {
            switch item {
            case .srcLang:
                showLanguageMenu(source: true, from: layout.rect(for: item) ?? .zero)
            case .dstLang:
                showLanguageMenu(source: false, from: layout.rect(for: item) ?? .zero)
            case .provider:
                showProviderMenu(from: layout.rect(for: item) ?? .zero)
            default:
                session.handleBarItem(item)
            }
            return
        }
        session.mouseDown(at: point, clickCount: event.clickCount)
    }

    override func mouseDragged(with event: NSEvent) {
        let point = modelPoint(event)
        if isBarHost, let layout = session.barLayout(), layout.frame.contains(point),
           session.dragMode == .none {
            return
        }
        session.mouseDragged(to: point)
    }

    override func mouseUp(with event: NSEvent) {
        session.mouseUp(at: modelPoint(event), clickCount: event.clickCount)
    }

    override func mouseMoved(with event: NSEvent) {
        let point = modelPoint(event)
        if isBarHost, let layout = session.barLayout() {
            session.setHoveredBarItem(layout.item(at: point))
        } else {
            session.setHoveredBarItem(nil)
        }
        session.mouseMoved(to: point)
    }

    override func mouseExited(with event: NSEvent) {
        session.setHoveredBarItem(nil)
    }

    override func rightMouseDown(with event: NSEvent) {
        session.cancel()
    }

    override func otherMouseDown(with event: NSEvent) {
        guard event.buttonNumber == 2 else { return }
        session.middleClick()
    }

    override func keyDown(with event: NSEvent) {
        if session.textEditing != nil {
            switch event.keyCode {
            case 53:
                session.cancelText()
            case 36, 76:
                session.commitText()
            case 51:
                session.deleteBackwardText()
            default:
                interpretKeyEvents([event])
            }
            return
        }
        if !session.keyDown(event) {
            super.keyDown(with: event)
        }
    }

    override func flagsChanged(with event: NSEvent) {
        session.modifiersChanged(event.modifierFlags)
    }

    // MARK: - 追踪区 / 光标

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        if let trackingArea { removeTrackingArea(trackingArea) }
        let area = NSTrackingArea(rect: bounds,
                                  options: [.activeAlways, .mouseMoved, .mouseEnteredAndExited, .inVisibleRect],
                                  owner: self,
                                  userInfo: nil)
        addTrackingArea(area)
        trackingArea = area
    }

    override func resetCursorRects() {
        addCursorRect(bounds, cursor: .crosshair)
    }
}

// MARK: - 文字输入（支持中文输入法）

extension SelectionView: NSTextInputClient {
    func insertText(_ string: Any, replacementRange: NSRange) {
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        session.appendText(text)
    }

    override func doCommand(by selector: Selector) {
        switch selector {
        case #selector(NSResponder.deleteBackward(_:)):
            session.deleteBackwardText()
        case #selector(NSResponder.insertNewline(_:)):
            session.commitText()
        case #selector(NSResponder.cancelOperation(_:)):
            session.cancelText()
        default:
            break
        }
    }

    func setMarkedText(_ string: Any, selectedRange: NSRange, replacementRange: NSRange) {
        let text = (string as? String) ?? (string as? NSAttributedString)?.string ?? ""
        session.updateMarkedText(text)
    }

    func unmarkText() {
        session.updateMarkedText("")
    }

    func selectedRange() -> NSRange {
        NSRange(location: session.editingTextLength, length: 0)
    }

    func markedRange() -> NSRange {
        guard let editing = session.textEditing, !editing.marked.isEmpty else {
            return NSRange(location: NSNotFound, length: 0)
        }
        let start = (editing.text as NSString).length
        return NSRange(location: start, length: (editing.marked as NSString).length)
    }

    func hasMarkedText() -> Bool {
        !(session.textEditing?.marked.isEmpty ?? true)
    }

    func attributedSubstring(forProposedRange range: NSRange,
                              actualRange: NSRangePointer?) -> NSAttributedString? {
        nil
    }

    func validAttributesForMarkedText() -> [NSAttributedString.Key] {
        [.underlineStyle, .font, .foregroundColor]
    }

    func firstRect(forCharacterRange range: NSRange, actualRange: NSRangePointer?) -> NSRect {
        guard let editing = session.textEditing else { return .zero }
        let bounds = AnnotationMetrics.textBounds(text: editing.text,
                                                  family: editing.fontFamily,
                                                  size: editing.fontSize,
                                                  bold: false, italic: false,
                                                  origin: editing.origin)
        let local = localRect(CGRect(x: bounds.maxX + 1, y: editing.origin.y,
                                     width: 1, height: editing.fontSize * 1.2))
        guard let window else { return .zero }
        return window.convertToScreen(convert(local, to: nil))
    }

    func characterIndex(for point: NSPoint) -> Int {
        0
    }
}
