import Foundation

/// 文件名模板展开，行为对齐 Windows 版 AppSettings：
/// 支持 `$yyyy-MM-dd_HH-mm-ss$`、`$yyyy$`、`$MM$`（月）、`$dd$`、`$HH$`、`$mm$`（分）、`$ss$`。
/// 结果为空时回退 "SnipLite"。
public enum FileNamePattern {
    public static func expand(_ pattern: String, date: Date = Date(), timeZone: TimeZone = .current) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let components = calendar.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)

        let year = String(format: "%04d", components.year ?? 0)
        let month = String(format: "%02d", components.month ?? 0)
        let day = String(format: "%02d", components.day ?? 0)
        let hour = String(format: "%02d", components.hour ?? 0)
        let minute = String(format: "%02d", components.minute ?? 0)
        let second = String(format: "%02d", components.second ?? 0)

        var result = pattern
            .replacingOccurrences(of: "$yyyy-MM-dd_HH-mm-ss$",
                                  with: "\(year)-\(month)-\(day)_\(hour)-\(minute)-\(second)")
            .replacingOccurrences(of: "$yyyy$", with: year)
            .replacingOccurrences(of: "$MM$", with: month)
            .replacingOccurrences(of: "$dd$", with: day)
            .replacingOccurrences(of: "$HH$", with: hour)
            .replacingOccurrences(of: "$mm$", with: minute)
            .replacingOccurrences(of: "$ss$", with: second)

        result = sanitize(result)
        return result.isEmpty ? "SnipLite" : result
    }

    /// 对齐原版的非法字符处理；macOS 上额外允许 `/` 之外的大多数字符，但保持与 Windows 一致更可预期。
    public static func sanitize(_ name: String) -> String {
        let illegal = CharacterSet(charactersIn: "\\/:*?\"<>|")
        return name
            .components(separatedBy: illegal)
            .joined(separator: "_")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// 按扩展名生成最终文件名；模板自带扩展名时替换，否则追加。同名冲突从 (2) 开始递增由调用方处理。
    public static func fileName(pattern: String, extension ext: String, date: Date = Date()) -> String {
        let base = expand(pattern, date: date)
        let normalizedExt = ext.hasPrefix(".") ? ext : "." + ext
        let lower = base.lowercased()
        if lower.hasSuffix(".png") || lower.hasSuffix(".jpg") || lower.hasSuffix(".jpeg") {
            let stem = (base as NSString).deletingPathExtension
            return stem + normalizedExt
        }
        return base + normalizedExt
    }
}
