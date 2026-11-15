import AppKit
import CoreGraphics
import ImageIO
import SnipLiteCore

enum OutputService {
    /// 从剪贴板取图：PNG → TIFF → 文件 URL。
    static func clipboardImage() -> CGImage? {
        let pasteboard = NSPasteboard.general
        if let data = pasteboard.data(forType: .png),
           let source = CGImageSourceCreateWithData(data as CFData, nil) {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        if let data = pasteboard.data(forType: .tiff),
           let rep = NSBitmapImageRep(data: data) {
            return rep.cgImage
        }
        if let string = pasteboard.string(forType: .fileURL),
           let url = URL(string: string),
           let source = CGImageSourceCreateWithURL(url as CFURL, nil) {
            return CGImageSourceCreateImageAtIndex(source, 0, nil)
        }
        return nil
    }

    @discardableResult
    static func copyToPasteboard(_ image: CGImage) -> Bool {
        let rep = NSBitmapImageRep(cgImage: image)
        guard let png = rep.representation(using: .png, properties: [:]) else { return false }
        let item = NSPasteboardItem()
        item.setData(png, forType: .png)
        if let tiff = rep.representation(using: .tiff, properties: [:]) {
            item.setData(tiff, forType: .tiff)
        }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        return pasteboard.writeObjects([item])
    }

    static func pngData(_ image: CGImage) -> Data? {
        NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:])
    }

    static func write(_ image: CGImage, to url: URL, jpegQuality: Int) throws {
        let rep = NSBitmapImageRep(cgImage: image)
        let isJPEG = url.pathExtension.lowercased() == "jpg" || url.pathExtension.lowercased() == "jpeg"
        let data: Data?
        if isJPEG {
            let quality = Double(min(max(jpegQuality, 30), 100)) / 100
            data = rep.representation(using: .jpeg, properties: [.compressionFactor: quality])
        } else {
            data = rep.representation(using: .png, properties: [:])
        }
        guard let data else {
            throw NSError(domain: "SnipLite", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "图片编码失败"])
        }
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }

    /// 快速保存到设置目录，返回最终路径。
    @discardableResult
    static func quickSave(_ image: CGImage, settings: AppSettings) throws -> URL {
        let directory = URL(fileURLWithPath: settings.quickSaveDirectory, isDirectory: true)
        let name = FileNamePattern.fileName(pattern: settings.fileNamePattern, extension: "png")
        let url = uniqueURL(in: directory, name: name)
        try write(image, to: url, jpegQuality: settings.jpegQuality)
        return url
    }

    static func uniqueURL(in directory: URL, name: String) -> URL {
        let base = (name as NSString).deletingPathExtension
        let ext = (name as NSString).pathExtension
        var candidate = directory.appendingPathComponent(name)
        var index = 2
        while FileManager.default.fileExists(atPath: candidate.path) {
            let next = ext.isEmpty ? "\(base) (\(index))" : "\(base) (\(index)).\(ext)"
            candidate = directory.appendingPathComponent(next)
            index += 1
        }
        return candidate
    }

    @MainActor
    static func chooseSaveURL(defaultName: String) -> URL? {
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.png, .jpeg]
        panel.nameFieldStringValue = defaultName
        panel.canCreateDirectories = true
        return panel.runModal() == .OK ? panel.url : nil
    }
}
