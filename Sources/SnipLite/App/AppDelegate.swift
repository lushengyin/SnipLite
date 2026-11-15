import AppKit
import SnipLiteCore

final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItemController: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        AppLog.shared.level = SettingsStore.shared.settings.logLevel
        AppLog.shared.write("启动 SnipLite \(AppInfo.displayVersion)")

        statusItemController = StatusItemController()
        HotkeyCenter.shared.apply(SettingsStore.shared.settings)

        SettingsStore.shared.onChange = { settings in
            AppLog.shared.level = settings.logLevel
            HotkeyCenter.shared.apply(settings)
        }

        // 调试入口：`open SnipLite.app --args --capture`
        if CommandLine.arguments.contains("--capture") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) {
                CaptureSession.start(mode: .capture)
            }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppLog.shared.write("退出 SnipLite")
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }
}
