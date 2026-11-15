import AppKit
import SnipLiteCore

/// OCR 结果面板：可阅读、可用鼠标选中部分文字后复制。
final class OcrResultPanel: NSPanel {
    var onClose: (() -> Void)?

    private let textView = OcrTextView()

    override var canBecomeKey: Bool { true }

    init(text: String) {
        super.init(contentRect: NSRect(x: 0, y: 0, width: 400, height: 260),
                   styleMask: [.titled, .closable, .resizable],
                   backing: .buffered,
                   defer: false)
        title = "识别结果"
        level = .screenSaver
        isReleasedWhenClosed = false
        collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        buildUI(text)
    }

    override func close() {
        let handler = onClose
        onClose = nil
        super.close()
        handler?()
    }

    private func buildUI(_ text: String) {
        guard let content = contentView else { return }

        let scroll = NSScrollView(frame: NSRect(x: 10, y: 46, width: 380, height: 200))
        scroll.autoresizingMask = [.width, .height]
        scroll.hasVerticalScroller = true
        scroll.borderType = .bezelBorder
        scroll.drawsBackground = true

        textView.isEditable = false
        textView.isSelectable = true
        textView.isRichText = false
        textView.font = .systemFont(ofSize: 13)
        textView.string = text
        textView.textContainerInset = NSSize(width: 6, height: 6)
        textView.autoresizingMask = [.width]
        textView.minSize = NSSize(width: 0, height: 0)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude,
                                  height: CGFloat.greatestFiniteMagnitude)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.frame = NSRect(x: 0, y: 0, width: 360, height: 190)
        textView.onEscape = { [weak self] in self?.close() }
        scroll.documentView = textView

        content.addSubview(scroll)

        let copySelection = NSButton(title: "复制选中", target: self, action: #selector(copySelection))
        copySelection.frame = NSRect(x: 10, y: 10, width: 90, height: 28)
        copySelection.autoresizingMask = [.maxYMargin]
        content.addSubview(copySelection)

        let copyAll = NSButton(title: "复制全部", target: self, action: #selector(copyAll))
        copyAll.frame = NSRect(x: 106, y: 10, width: 90, height: 28)
        copyAll.autoresizingMask = [.maxYMargin]
        content.addSubview(copyAll)

        let close = NSButton(title: "关闭", target: self, action: #selector(closePanel))
        close.frame = NSRect(x: 300, y: 10, width: 90, height: 28)
        close.autoresizingMask = [.minXMargin, .maxYMargin]
        content.addSubview(close)
    }

    func selectAllText() {
        textView.selectAll(nil)
    }

    @objc private func copySelection() {
        let range = textView.selectedRange()
        let string = textView.string as NSString
        let text = range.length > 0 ? string.substring(with: range) : textView.string
        copy(text)
    }

    @objc private func copyAll() {
        copy(textView.string)
    }

    private func copy(_ text: String) {
        guard !text.isEmpty else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        Toast.show("已复制")
    }

    @objc private func closePanel() {
        close()
    }
}

final class OcrTextView: NSTextView {
    var onEscape: (() -> Void)?

    override func keyDown(with event: NSEvent) {
        if event.keyCode == 53 {
            onEscape?()
            return
        }
        super.keyDown(with: event)
    }
}
