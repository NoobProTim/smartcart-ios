// ReceiptScannerService.swift — SmartCart/Services/ReceiptScannerService.swift
//
// Apple Vision OCR pipeline: camera image → VNRecognizeTextRequest
// → structured ReceiptScanResult { id, items, store, date }
//
// P1-H fix: ReceiptScanResult now carries `let id: UUID` set at scan time.
// Identifiable conformance relies on this UUID — no String.hash used anywhere.

import Foundation
import Vision
import UIKit

// MARK: - Output types

struct ScannedLineItem {
    let nameRaw: String
    let nameNormalised: String
    let price: Double
    let confidence: Float
}

// P1-H: id is a stable UUID assigned once in ReceiptScannerService.scan().
// .sheet(item: $scanResult) uses this id for identity — no hash collision possible.
struct ReceiptScanResult: Identifiable {
    let id: UUID                 // P1-H: stable scan identity
    let items: [ScannedLineItem]
    let storeNameRaw: String?
    let receiptDate: Date?
    let rawLines: [String]
}

// MARK: - Service

final class ReceiptScannerService {

    static let shared = ReceiptScannerService()
    private init() {}

    private let confidenceThreshold: Float = 0.6

    // MARK: - Public API

    func scan(image: UIImage) async throws -> ReceiptScanResult {
        guard let cgImage = image.cgImage else {
            throw ScanError.invalidImage
        }
        let lines = try await recogniseText(in: cgImage)
        // P1-H: UUID generated here, once, at scan time.
        return parseReceipt(lines: lines, id: UUID())
    }

    // MARK: - Vision text recognition

    private func recogniseText(in cgImage: CGImage) async throws -> [RecognisedLine] {
        try await withCheckedThrowingContinuation { continuation in
            let request = VNRecognizeTextRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }
                let observations = request.results as? [VNRecognizedTextObservation] ?? []
                let sorted = observations.sorted {
                    $0.boundingBox.origin.y > $1.boundingBox.origin.y
                }
                let lines: [RecognisedLine] = sorted.compactMap { obs in
                    guard let top = obs.topCandidates(1).first,
                          top.confidence >= self.confidenceThreshold else { return nil }
                    return RecognisedLine(
                        text: top.string,
                        confidence: top.confidence,
                        boundingBox: obs.boundingBox
                    )
                }
                continuation.resume(returning: lines)
            }
            request.recognitionLevel       = .accurate
            request.recognitionLanguages   = ["en-CA", "en-US"]
            request.usesLanguageCorrection = true
            request.minimumTextHeight      = 0.01

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Receipt structure parsing

    private func parseReceipt(lines: [RecognisedLine], id: UUID) -> ReceiptScanResult {
        var scannedItems: [ScannedLineItem] = []
        var storeNameRaw: String? = nil
        var receiptDate: Date? = nil
        let rawLines = lines.map { $0.text }

        storeNameRaw = lines.first?.text
        receiptDate  = extractDate(from: rawLines)

        for line in lines {
            if let item = extractLineItem(from: line) {
                scannedItems.append(item)
            }
        }

        return ReceiptScanResult(
            id:           id,
            items:        scannedItems,
            storeNameRaw: storeNameRaw,
            receiptDate:  receiptDate,
            rawLines:     rawLines
        )
    }

    // MARK: - Line-item extraction

    private let pricePattern = try! NSRegularExpression(
        pattern: #"^(.+?)\s+\$?([0-9]+\.[0-9]{2})\s*[A-Z]?$"#,
        options: .caseInsensitive
    )

    private let skipKeywords = [
        "subtotal", "sub total", "total", "tax", "hst", "gst",
        "pst", "cash", "change", "debit", "credit", "visa",
        "mastercard", "balance", "savings", "you saved", "points",
        "receipt", "thank you", "cashier", "store #", "tel:", "www."
    ]

    private func extractLineItem(from line: RecognisedLine) -> ScannedLineItem? {
        let text  = line.text
        let lower = text.lowercased()
        for keyword in skipKeywords {
            if lower.contains(keyword) { return nil }
        }
        let range = NSRange(text.startIndex..., in: text)
        guard let match = pricePattern.firstMatch(in: text, range: range),
              match.numberOfRanges >= 3 else { return nil }
        guard let nameRange  = Range(match.range(at: 1), in: text),
              let priceRange = Range(match.range(at: 2), in: text),
              let price = Double(text[priceRange]) else { return nil }
        let nameRaw = String(text[nameRange]).trimmingCharacters(in: .whitespaces)
        guard nameRaw.count >= 2 else { return nil }
        return ScannedLineItem(
            nameRaw:        nameRaw,
            nameNormalised: normalise(nameRaw),
            price:          price,
            confidence:     line.confidence
        )
    }

    // MARK: - Name normalisation

    private let unitSuffixPattern = try! NSRegularExpression(
        pattern: #"\s*\d+\s*(ml|l|g|kg|oz|lb|lbs|pk|ct|ea)\b"#,
        options: .caseInsensitive
    )

    private func normalise(_ raw: String) -> String {
        var s = raw.lowercased()
        let r = NSRange(s.startIndex..., in: s)
        s = unitSuffixPattern.stringByReplacingMatches(in: s, range: r, withTemplate: "")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        while s.contains("  ") { s = s.replacingOccurrences(of: "  ", with: " ") }
        return s
    }

    // MARK: - Date extraction

    private let dateFormats = [
        "MM/dd/yyyy", "dd/MM/yyyy", "yyyy-MM-dd",
        "MMM dd yyyy", "MMMM dd, yyyy", "MM-dd-yyyy"
    ]

    private func extractDate(from lines: [String]) -> Date? {
        let datePattern = try! NSRegularExpression(
            pattern: #"(\d{1,2}[/-]\d{1,2}[/-]\d{2,4}|\w+ \d{1,2},? \d{4})"#
        )
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_CA")
        for line in lines {
            let range = NSRange(line.startIndex..., in: line)
            guard let match = datePattern.firstMatch(in: line, range: range),
                  let matchRange = Range(match.range(at: 1), in: line) else { continue }
            let candidate = String(line[matchRange])
            for fmt in dateFormats {
                formatter.dateFormat = fmt
                if let date = formatter.date(from: candidate) { return date }
            }
        }
        return nil
    }

    // MARK: - Errors

    enum ScanError: LocalizedError {
        case invalidImage
        var errorDescription: String? {
            switch self {
            case .invalidImage: return "Could not read the image. Please try again."
            }
        }
    }
}

// MARK: - Internal helper

private struct RecognisedLine {
    let text: String
    let confidence: Float
    let boundingBox: CGRect
}
