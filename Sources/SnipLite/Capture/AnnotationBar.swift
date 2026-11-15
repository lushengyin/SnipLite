import AppKit
import SnipLiteCore

/// 标注工具栏的布局与命中测试。坐标是全局模型坐标（左上原点、point）。
struct AnnotationBarLayout {
    enum Item: Hashable {
        case tool(ToolKind)
        case undo
        case redo
        case close
        case pin
        case save
        case copy
        case ocr
        case translate
        case qr
        case resultCopy
        case srcLang
        case swapLang
        case dstLang
        case provider
        case toggleOriginal
        case retry
        case width
        case brushMode
        case fill
        case arrowStyle
        case opacity
        case blockSize
        case color(Int)
    }

    let frame: CGRect
    let items: [(Item, CGRect)]
    let statusText: String?
    let statusRect: CGRect?

    static func make(selection: CGRect, screen: ScreenInfo, tool: ToolKind?,
                     color: RGBAColor, filled: Bool, arrowStyle: ArrowStyle,
                     lineWidth: CGFloat, opacity: CGFloat, blockSize: CGFloat,
                     rectangular: Bool, canUndo: Bool, canRedo: Bool,
                     status: String?, canCopyResult: Bool,
                     translating: Bool = false) -> AnnotationBarLayout {
        let unit: CGFloat = 30
        let gap: CGFloat = 4
        let group: CGFloat = 10
        let padding: CGFloat = 8
        let swatch: CGFloat = 16
        let swatchGap: CGFloat = 2
        let columns = 11
        let optionWidth: CGFloat = 64

        var items: [(Item, CGRect)] = []
        var x = padding

        func add(_ item: Item, width: CGFloat = unit, row: CGFloat) {
            items.append((item, CGRect(x: x, y: row, width: width, height: unit)))
            x += width + gap
        }

        let row1Y = padding
        for kind in ToolKind.allCases { add(.tool(kind), row: row1Y) }
        x += group - gap
        add(.undo, row: row1Y)
        add(.redo, row: row1Y)
        x += group - gap
        add(.ocr, row: row1Y)
        add(.translate, row: row1Y)
        add(.qr, row: row1Y)
        x += group - gap
        add(.close, row: row1Y)
        add(.pin, row: row1Y)
        add(.save, row: row1Y)
        add(.copy, row: row1Y)
        let row1Width = x - gap + padding

        var row2Width = padding
        var row2Height: CGFloat = 0
        let row2Y = padding + unit + 6

        if let tool {
            var x2 = padding
            func addOption(_ item: Item) {
                items.append((item, CGRect(x: x2, y: row2Y, width: optionWidth, height: unit)))
                x2 += optionWidth + gap
            }
            if tool.supportsWidth { addOption(.width) }
            if tool.supportsBrushMode { addOption(.brushMode) }
            if tool.supportsFill { addOption(.fill) }
            if tool.supportsArrowStyle { addOption(.arrowStyle) }
            if tool.supportsOpacity { addOption(.opacity) }
            if tool.supportsBlockSize { addOption(.blockSize) }
            row2Width = max(row2Width, x2 - gap + padding)
        }

        // 调色板只在选中工具时出现；橡皮/马赛克不显示
        let showPalette = tool != nil && tool != .eraser && tool != .mosaic
        if showPalette {
            var paletteX = padding
            if let tool, tool.supportsWidth || tool.supportsBrushMode || tool.supportsFill
                || tool.supportsArrowStyle || tool.supportsOpacity || tool.supportsBlockSize {
                paletteX = row2Width + group
            }
            for index in 0..<min(columns * 2, RGBAColor.palette.count) {
                let column = index % columns
                let row = index / columns
                let rect = CGRect(x: paletteX + CGFloat(column) * (swatch + swatchGap),
                                  y: row2Y + CGFloat(row) * (swatch + swatchGap),
                                  width: swatch, height: swatch)
                items.append((.color(index), rect))
            }
            row2Width = max(row2Width, paletteX + CGFloat(columns) * (swatch + swatchGap) - swatchGap + padding)
        }

        if tool != nil {
            row2Height = 2 * swatch + swatchGap
            row2Height = max(row2Height, unit)
        }

        var width = max(row1Width, row2Width)
        if status != nil { width = max(width, 460) }

        // 翻译工具条（仅翻译结果存在时）
        var translationRowHeight: CGFloat = 0
        if translating {
            let y = padding + unit + (tool != nil ? 6 + row2Height : 0) + 6
            translationRowHeight = unit
            var x3 = padding
            func addTrans(_ item: Item, width: CGFloat) {
                items.append((item, CGRect(x: x3, y: y, width: width, height: unit)))
                x3 += width + gap
            }
            addTrans(.srcLang, width: 88)
            addTrans(.swapLang, width: unit)
            addTrans(.dstLang, width: 88)
            x3 += group - gap
            addTrans(.provider, width: 90)
            x3 += group - gap
            addTrans(.toggleOriginal, width: 76)
            addTrans(.retry, width: 54)
            width = max(width, x3 - gap + padding)
        }

        let statusHeight: CGFloat = 26
        let statusRowY = padding + unit
            + (tool != nil ? 6 + row2Height : 0)
            + (translating ? 6 + translationRowHeight : 0) + 6
        var statusRectLocal: CGRect?
        if status != nil {
            let copyWidth: CGFloat = canCopyResult ? 76 : 0
            statusRectLocal = CGRect(x: padding, y: statusRowY,
                                     width: width - padding * 2 - copyWidth,
                                     height: statusHeight)
            if canCopyResult {
                items.append((.resultCopy,
                              CGRect(x: width - padding - 64, y: statusRowY,
                                     width: 64, height: statusHeight)))
            }
        }

        let height = padding * 2 + unit
            + (tool != nil ? 6 + row2Height : 0)
            + (translating ? 6 + translationRowHeight : 0)
            + (status != nil ? 6 + statusHeight : 0)

        var origin = CGPoint(x: selection.minX, y: selection.maxY + 10)
        if origin.y + height > screen.frame.maxY {
            origin.y = selection.minY - height - 10
        }
        origin.x = min(max(origin.x, screen.frame.minX + 4), screen.frame.maxX - width - 4)
        origin.y = min(max(origin.y, screen.frame.minY + 4), screen.frame.maxY - height - 4)

        let offset = items.map { ($0.0, $0.1.offsetBy(dx: origin.x, dy: origin.y)) }
        return AnnotationBarLayout(frame: CGRect(x: origin.x, y: origin.y, width: width, height: height),
                                   items: offset,
                                   statusText: status,
                                   statusRect: statusRectLocal?.offsetBy(dx: origin.x, dy: origin.y))
    }

    func item(at point: CGPoint) -> Item? {
        items.first { $0.1.contains(point) }?.0
    }

    func rect(for item: Item) -> CGRect? {
        items.first { $0.0 == item }?.1
    }
}

extension AnnotationBarLayout.Item {
    /// 悬浮提示文案。
    var hint: String {
        switch self {
        case .tool(.rectangle): return "矩形（R）"
        case .tool(.ellipse): return "椭圆（E）"
        case .tool(.arrow): return "箭头（A）"
        case .tool(.pen): return "铅笔（P）"
        case .tool(.marker): return "马克笔（M）"
        case .tool(.mosaic): return "马赛克（X）"
        case .tool(.text): return "文字（T）"
        case .tool(.eraser): return "橡皮（H）"
        case .undo: return "撤销（⌘Z）"
        case .redo: return "重做（⇧⌘Z）"
        case .ocr: return "文字识别（识别选区文字）"
        case .translate: return "截图翻译（原位覆盖译文）"
        case .qr: return "二维码识别"
        case .close: return "关闭（Esc）"
        case .pin: return "贴图（⌘T）"
        case .save: return "另存为（⌘S）"
        case .copy: return "复制（⌘C）"
        case .width: return "线宽"
        case .brushMode: return "涂抹 / 框选"
        case .fill: return "实心 / 空心"
        case .arrowStyle: return "箭头样式"
        case .opacity: return "透明度"
        case .blockSize: return "马赛克块大小"
        case .color: return "颜色"
        case .resultCopy: return "复制识别结果"
        case .srcLang: return "源语言"
        case .swapLang: return "交换语言"
        case .dstLang: return "目标语言"
        case .provider: return "翻译服务"
        case .toggleOriginal: return "切换原文 / 译文"
        case .retry: return "重新翻译"
        }
    }
}

enum BarIcon {    static func image(for item: AnnotationBarLayout.Item) -> NSImage? {
        let name: String
        switch item {
        case .tool(.rectangle): name = "rectangle"
        case .tool(.ellipse): name = "circle"
        case .tool(.arrow): name = "arrow.up.right"
        case .tool(.pen): name = "pencil"
        case .tool(.marker): name = "highlighter"
        case .tool(.mosaic): name = "square.grid.3x3.fill"
        case .tool(.text): name = "textformat"
        case .tool(.eraser): name = "eraser"
        case .undo: name = "arrow.uturn.backward"
        case .redo: name = "arrow.uturn.forward"
        case .close: name = "xmark"
        case .pin: name = "pin"
        case .save: name = "square.and.arrow.down"
        case .copy: name = "doc.on.doc"
        case .ocr: name = "text.viewfinder"
        case .translate: name = "character.bubble"
        case .qr: name = "qrcode"
        case .resultCopy: return nil
        case .width: name = "lineweight"
        case .brushMode: name = "scribble"
        case .fill: name = "square.fill"
        case .arrowStyle: name = "arrowshape.right"
        case .opacity: name = "circle.lefthalf.filled"
        case .blockSize: name = "square.grid.2x2"
        case .swapLang: name = "arrow.left.arrow.right"
        case .retry: name = "arrow.clockwise"
        case .srcLang, .dstLang, .provider, .toggleOriginal: return nil
        case .color: return nil
        }
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
        image?.isTemplate = true
        return image
    }

    static func optionLabel(_ item: AnnotationBarLayout.Item,
                            lineWidth: CGFloat, filled: Bool, arrowStyle: ArrowStyle,
                            opacity: CGFloat, blockSize: CGFloat, rectangular: Bool) -> String? {
        switch item {
        case .width: return "\(Int(lineWidth)) px"
        case .brushMode: return rectangular ? "框选" : "涂抹"
        case .fill: return filled ? "实心" : "空心"
        case .arrowStyle: return arrowStyle.title
        case .opacity: return "\(Int(opacity * 100))%"
        case .blockSize: return "\(Int(blockSize)) px"
        default: return nil
        }
    }
}
