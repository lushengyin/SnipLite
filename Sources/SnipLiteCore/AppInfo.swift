import Foundation

public enum AppInfo {
    public static let name = "SnipLite"

    /// 版本号来自 Info.plist；在测试宿主里取不到时回退到开发版本。
    public static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.4.0"
    }

    public static var build: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
    }

    public static var displayVersion: String { "\(version) (\(build))" }
}
