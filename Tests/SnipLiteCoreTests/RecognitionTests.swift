import XCTest
@testable import SnipLiteCore

final class OcrDocumentTests: XCTestCase {
    private func makeDocument() -> OcrDocument {
        OcrDocument(characters: [
            RecognizedCharacter(text: "中", bounds: CGRect(x: 0, y: 0, width: 10, height: 10)),
            RecognizedCharacter(text: "文", bounds: CGRect(x: 10, y: 0, width: 10, height: 10)),
            RecognizedCharacter(text: "A", bounds: CGRect(x: 0, y: 20, width: 10, height: 10), prefix: "\n"),
            RecognizedCharacter(text: "B", bounds: CGRect(x: 12, y: 20, width: 10, height: 10), prefix: " ")
        ])
    }

    func testTextPreservesPrefixes() {
        XCTAssertEqual(makeDocument().text, "中文\nA B")
    }

    func testGetTextSupportsReverseSelection() {
        let document = makeDocument()
        XCTAssertEqual(document.getText(from: 2, to: 1), "文\nA")
        XCTAssertEqual(document.getText(from: 3, to: 4), " B")
    }

    func testHitTestPrefersContainingCharacter() {
        let document = makeDocument()
        XCTAssertEqual(document.hitTest(CGPoint(x: 31, y: 5), nearest: false, tolerance: 16), 1)
        XCTAssertEqual(document.hitTest(CGPoint(x: 5, y: 5), nearest: false, tolerance: 16), 0)
        XCTAssertEqual(document.hitTest(CGPoint(x: 5, y: 60), nearest: false, tolerance: 16), -1)
        XCTAssertNotEqual(document.hitTest(CGPoint(x: 5, y: 60), nearest: true, tolerance: 16), -1)
    }

    func testEmptyDocument() {
        XCTAssertTrue(OcrDocument.empty.isEmpty)
        XCTAssertEqual(OcrDocument.empty.text, "")
        XCTAssertEqual(OcrDocument.empty.getText(from: 0, to: 1), "")
    }
}

final class TranslationOverlayBuilderTests: XCTestCase {
    func testMergesWrappedLinesButKeepsSeparateColumns() {
        // 两行紧邻、左边界对齐 → 合并；第三行左边界差很远 → 独立成块
        let document = OcrDocument(characters: [
            RecognizedCharacter(text: "Hello", bounds: CGRect(x: 0, y: 0, width: 50, height: 12)),
            RecognizedCharacter(text: "world", bounds: CGRect(x: 0, y: 13, width: 50, height: 12), prefix: "\n"),
            RecognizedCharacter(text: "Side", bounds: CGRect(x: 200, y: 0, width: 30, height: 12), prefix: "\n")
        ])
        let blocks = TranslationOverlayBuilder.blocks(from: document)
        XCTAssertEqual(blocks.count, 2)
        XCTAssertEqual(blocks[0].text, "Helloworld")
        XCTAssertEqual(blocks[1].text, "Side")
    }

    func testEmptyDocumentProducesNoBlocks() {
        XCTAssertTrue(TranslationOverlayBuilder.blocks(from: .empty).isEmpty)
    }
}
