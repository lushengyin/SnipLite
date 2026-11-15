import CoreGraphics
import Foundation

/// 指针下的窗口（窗口级框选）。元素级（AX）留到后续阶段，缺失权限时也走这里。
enum TargetResolver {
    static func windowFrame(at point: CGPoint, excludingPID pid: pid_t) -> CGRect? {
        guard let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements],
                                                    kCGNullWindowID) as? [[String: Any]] else {
            return nil
        }

        for info in list {
            guard let layer = info[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let alpha = info[kCGWindowAlpha as String] as? Double, alpha > 0.01 else { continue }
            guard let ownerPID = info[kCGWindowOwnerPID as String] as? Int32, ownerPID != pid else { continue }
            guard let bounds = info[kCGWindowBounds as String] as? [String: Any],
                  let frame = CGRect(dictionaryRepresentation: bounds as CFDictionary) else { continue }
            guard frame.width > 1, frame.height > 1 else { continue }
            if frame.contains(point) { return frame }
        }
        return nil
    }
}
