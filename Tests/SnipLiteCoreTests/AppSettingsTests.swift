import XCTest
@testable import SnipLiteCore

final class AppSettingsTests: XCTestCase {
    func testDefaultsFollowMacConventions() {
        let settings = AppSettings()
        XCTAssertEqual(settings.captureHotkey.displayText, "⌃⌥A")
        XCTAssertEqual(settings.pinHotkey.displayText, "⌃⌥S")
        XCTAssertEqual(settings.ocrHotkey.displayText, "⌃⌥O")
        XCTAssertEqual(settings.qrHotkey.displayText, "⌃⌥Q")
        XCTAssertEqual(settings.translationHotkey.displayText, "⌃⌥T")
        XCTAssertTrue(settings.copyAfterCapture)
        XCTAssertEqual(settings.enterAction, .copy)
        XCTAssertEqual(settings.middleClickAction, .pin)
    }

    func testNormalizeClampsOutOfRangeValues() {
        var settings = AppSettings()
        settings.maskOpacity = 999
        settings.magnifierZoom = 0
        settings.captureBorderWidth = -3
        settings.jpegQuality = 1
        settings.historyRegionLimit = 3
        settings.recentRegions = (0..<10).map {
            CaptureRegion(x: Double($0), y: 0, width: 10, height: 10)
        }

        settings.normalize()

        XCTAssertEqual(settings.maskOpacity, 200)
        XCTAssertEqual(settings.magnifierZoom, 2)
        XCTAssertEqual(settings.captureBorderWidth, 1)
        XCTAssertEqual(settings.jpegQuality, 30)
        XCTAssertEqual(settings.recentRegions.count, 3)
    }

    func testMissingKeysFallBackToDefaults() throws {
        let json = #"{"maskOpacity": 50, "captureHotkey": {"modifiers": ["command"]}}"#
        let data = try XCTUnwrap(json.data(using: .utf8))
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)

        XCTAssertEqual(decoded.maskOpacity, 50)
        XCTAssertNil(decoded.captureHotkey.key)
        XCTAssertEqual(decoded.pinHotkey.displayText, "⌃⌥S")
        XCTAssertEqual(decoded.fileNamePattern, "SnipLite_$yyyy-MM-dd_HH-mm-ss$")
    }

    func testRoundTripKeepsValues() throws {
        var settings = AppSettings()
        settings.maskOpacity = 77
        settings.captureHotkey = HotkeyBinding(key: "F1", modifiers: [.option])

        let data = try JSONEncoder().encode(settings)
        let decoded = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(decoded.maskOpacity, 77)
        XCTAssertEqual(decoded.captureHotkey, HotkeyBinding(key: "F1", modifiers: [.option]))
    }

    func testRememberRegionDeduplicatesAndCaps() {
        var settings = AppSettings()
        settings.historyRegionLimit = 2
        let a = CaptureRegion(x: 0, y: 0, width: 10, height: 10)
        let b = CaptureRegion(x: 20, y: 20, width: 10, height: 10)
        let c = CaptureRegion(x: 40, y: 40, width: 10, height: 10)

        settings.rememberRegion(a)
        settings.rememberRegion(b)
        settings.rememberRegion(a)
        XCTAssertEqual(settings.recentRegions, [a, b])

        settings.rememberRegion(c)
        XCTAssertEqual(settings.recentRegions, [c, a])
    }

    func testInvalidRegionIsIgnored() {
        var settings = AppSettings()
        settings.rememberRegion(CaptureRegion(x: 0, y: 0, width: 0, height: 10))
        XCTAssertTrue(settings.recentRegions.isEmpty)
    }
}

final class FileNamePatternTests: XCTestCase {
    private var date: Date {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 7
        components.hour = 9
        components.minute = 5
        components.second = 4
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar.date(from: components)!
    }

    func testDefaultPattern() {
        let name = FileNamePattern.expand("SnipLite_$yyyy-MM-dd_HH-mm-ss$",
                                          date: date, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(name, "SnipLite_2026-03-07_09-05-04")
    }

    func testSingleTokens() {
        let name = FileNamePattern.expand("$yyyy$-$MM$-$dd$-$HH$-$mm$-$ss$",
                                          date: date, timeZone: TimeZone(identifier: "UTC")!)
        XCTAssertEqual(name, "2026-03-07-09-05-04")
    }

    func testIllegalCharactersAreReplaced() {
        XCTAssertEqual(FileNamePattern.expand("a/b:c", date: date), "a_b_c")
    }

    func testEmptyPatternFallsBack() {
        XCTAssertEqual(FileNamePattern.expand("", date: date), "SnipLite")
        // 与原版一致：非法字符替换成下划线，替换结果非空就不再回退。
        XCTAssertEqual(FileNamePattern.expand("///", date: date), "___")
    }

    func testFileNameReplacesExistingExtension() {
        let name = FileNamePattern.fileName(pattern: "shot.png", extension: "jpg", date: date)
        XCTAssertEqual(name, "shot.jpg")
    }

    func testFileNameAppendsExtension() {
        let name = FileNamePattern.fileName(pattern: "shot", extension: ".png", date: date)
        XCTAssertEqual(name, "shot.png")
    }
}
