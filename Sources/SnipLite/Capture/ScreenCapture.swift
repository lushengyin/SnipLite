import AppKit
import CoreGraphics
import ScreenCaptureKit
import SnipLiteCore

struct CapturedDesktop {
    let image: CGImage
    let geometry: ScreenGeometry
    let scale: CGFloat
}

enum ScreenCaptureError: LocalizedError {
    case permissionDenied
    case unavailable(String)

    var errorDescription: String? {
        switch self {
        case .permissionDenied:
            return "需要「屏幕录制」权限才能截图"
        case .unavailable(let reason):
            return "抓屏失败：\(reason)"
        }
    }
}

enum ScreenCaptureService {
    /// 抓取所有显示器并合成到一张虚拟画布。
    /// 必须在显示遮罩之前调用，否则会把自己的窗口拍进去。
    @MainActor
    static func capture(settings: AppSettings) async throws -> CapturedDesktop {
        guard CGPreflightScreenCaptureAccess() else {
            CGRequestScreenCaptureAccess()
            throw ScreenCaptureError.permissionDenied
        }

        let entries: [(frame: CGRect, scale: CGFloat, displayID: UInt32)] = NSScreen.screens.compactMap { screen in
            guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else {
                return nil
            }
            return (screen.frame, screen.backingScaleFactor, number.uint32Value)
        }
        guard !entries.isEmpty else { throw ScreenCaptureError.unavailable("没有可用显示器") }

        let geometry = ScreenGeometry(cocoaFrames: entries)

        let content: SCShareableContent
        do {
            content = try await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: true)
        } catch {
            throw ScreenCaptureError.unavailable(error.localizedDescription)
        }

        // 边抓边画进画布：不再把所有屏幕的位图同时留在内存里，
        // 两块 4K 屏能省下一整屏的副本。
        let scale = geometry.canvasScale
        let width = Int((geometry.union.width * scale).rounded(.up))
        let height = Int((geometry.union.height * scale).rounded(.up))
        guard width > 0, height > 0,
              let space = CGColorSpace(name: CGColorSpace.sRGB),
              let context = CGContext(data: nil,
                                      width: width,
                                      height: height,
                                      bitsPerComponent: 8,
                                      bytesPerRow: 0,
                                      space: space,
                                      bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
            throw ScreenCaptureError.unavailable("创建画布失败")
        }
        context.setFillColor(NSColor.black.cgColor)
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        context.interpolationQuality = .none

        for screen in geometry.screens {
            guard let display = content.displays.first(where: { $0.displayID == screen.displayID }) else { continue }
            let filter = SCContentFilter(display: display, excludingWindows: [])
            let configuration = SCStreamConfiguration()
            // display.width/height 是逻辑点数，按 1:1 抓会得到半分辨率内容，
            // 再合成到 2x 画布就会被放大变糊。用 pointPixelScale 抓原生像素。
            let pixelScale = CGFloat(filter.pointPixelScale)
            configuration.width = Int((filter.contentRect.width * pixelScale).rounded())
            configuration.height = Int((filter.contentRect.height * pixelScale).rounded())
            configuration.showsCursor = settings.captureCursor
            let image: CGImage
            do {
                image = try await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                )
            } catch {
                throw ScreenCaptureError.unavailable(error.localizedDescription)
            }
            // 模型坐标是左上原点，CGContext 是左下原点。
            let rect = CGRect(
                x: screen.frame.minX * scale,
                y: (geometry.union.height - screen.frame.maxY) * scale,
                width: screen.frame.width * scale,
                height: screen.frame.height * scale
            )
            context.draw(image, in: rect)
        }

        guard let canvas = context.makeImage() else {
            throw ScreenCaptureError.unavailable("合成画布失败")
        }
        return CapturedDesktop(image: canvas, geometry: geometry, scale: scale)
    }
}
