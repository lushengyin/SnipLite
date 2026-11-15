import AppKit
import SnipLiteCore
import Vision

enum VisionOcrEngine {
    static func recognize(_ image: CGImage, languages: [String] = ["zh-Hans", "en-US"]) throws -> OcrDocument {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.recognitionLanguages = languages
        request.usesLanguageCorrection = true
        if #available(macOS 13.0, *) {
            request.automaticallyDetectsLanguage = false
        }

        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        return build(request.results ?? [], image: image)
    }

    private static func build(_ observations: [VNRecognizedTextObservation], image: CGImage) -> OcrDocument {
        let width = CGFloat(image.width)
        let height = CGFloat(image.height)

        var lines: [(rect: CGRect, text: VNRecognizedText)] = []
        for observation in observations {
            guard let candidate = observation.topCandidates(1).first else { continue }
            let box = observation.boundingBox
            let rect = CGRect(x: box.minX * width,
                              y: (1 - box.maxY) * height,
                              width: box.width * width,
                              height: box.height * height)
            lines.append((rect, candidate))
        }
        lines.sort {
            abs($0.rect.minY - $1.rect.minY) < 1
                ? $0.rect.minX < $1.rect.minX
                : $0.rect.minY < $1.rect.minY
        }

        var characters: [RecognizedCharacter] = []
        var lineBounds: [CGRect] = []

        for (lineIndex, line) in lines.enumerated() {
            lineBounds.append(line.rect)
            let string = line.text.string
            let graphemes = Array(string)
            guard !graphemes.isEmpty else { continue }

            var index = string.startIndex
            for (charIndex, character) in graphemes.enumerated() {
                let next = string.index(after: index)
                var box: CGRect
                if let observation = try? line.text.boundingBox(for: index..<next) {
                    let sub = observation.boundingBox
                    box = CGRect(x: sub.minX * width,
                                 y: (1 - sub.maxY) * height,
                                 width: sub.width * width,
                                 height: sub.height * height)
                    if box.width < 0.5 || box.height < 0.5 { box = fallbackBox(line.rect, index: charIndex, count: graphemes.count) }
                } else {
                    box = fallbackBox(line.rect, index: charIndex, count: graphemes.count)
                }
                let prefix = (charIndex == 0 && lineIndex > 0) ? "\n" : ""
                characters.append(RecognizedCharacter(text: String(character), bounds: box, prefix: prefix))
                index = next
            }
        }

        return OcrDocument(characters: characters, lineBounds: lineBounds)
    }

    private static func fallbackBox(_ line: CGRect, index: Int, count: Int) -> CGRect {
        guard count > 0 else { return line }
        let width = line.width / CGFloat(count)
        return CGRect(x: line.minX + width * CGFloat(index),
                      y: line.minY,
                      width: width,
                      height: line.height)
    }
}

enum VisionBarcodeScanner {
    static func scan(_ image: CGImage) throws -> String? {
        let request = VNDetectBarcodesRequest()
        let handler = VNImageRequestHandler(cgImage: image, options: [:])
        try handler.perform([request])
        let results = request.results ?? []
        return results.compactMap { $0.payloadStringValue }.first
    }
}
