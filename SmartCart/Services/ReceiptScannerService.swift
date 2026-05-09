// ReceiptScannerService.swift — SmartCart/Services/ReceiptScannerService.swift
//
// Apple Vision OCR pipeline: camera image → VNRecognizeTextRequest
// → structured ReceiptScanResult { items: [ScannedLineItem], store, date }
//
// ATLAS Task #1 — Deliverable 4: Apple Vision OCR Pipeline
// Confidence threshold: 0.6 (configurable via CONFIDENCE_THRESHOLD)
// Language: English (en-CA)

import Foundation
import Vision
import UIKit

// MARK: - Output types

struct ScannedLineItem {
    let nameRaw: String          // raw OCR text for the item name
    let nameNormalised: String   // lowercased, units/punctuation stripped
    let price: Double
    let confidence: Float
}

struct ReceiptScanResult {
    let items: [ScannedLineItem]
    let storeNameRaw: String?    // first high-confidence line (likely store header)
    let receiptDate: Date?       // parsed from receipt text if found
    let rawLines: [String]       // all recognised lines, for debug / manual review
}

// MARK: - Service

final class ReceiptScannerService {

    static let shared = ReceiptScannerService()
    private init() {}

    /// Minimum Vision confidence score to accept a text observation.
    private let confidenceThreshold: Float = 0.6

    // MARK: - Public API

    /// Runs the full OCR pipeline on a UIImage (from camera or photo library).
    /// Returns a ReceiptScanResult on success, or throws on Vision error.
    func scan(image: UIImage) async throws -> ReceiptScanResult {
        guard let cgImage = image.cgImage else {
            throw ScanError.invalidImage
        }
        let lines = try await recogniseText(in: cgImage)
        return parseReceipt(lines: lines)
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
                // Sort top-to-bottom by bounding box Y origin (receipts read top-down).
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
            request.minimumTextHeight      = 0.01  // ignore tiny artefacts

            let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    // MARK: - Receipt structure parsing

    private func parseReceipt(lines: [RecognisedLine]) -> ReceiptScanResult {
        var scannedItems: [ScannedLineItem] = []
        var storeNameRaw: String? = nil
        var receiptDate: Date? = nil
        let rawLines = lines.map { $0.text }

        // Heuristic: the first non-empty high-confidence line is likely the store name.
        storeNameRaw = lines.first?.text

        // Parse date from any line that matches common receipt date formats.
        receiptDate = extractDate(from: rawLines)

        // Item + price extraction:
        // Receipt lines typically follow: "ITEM NAME   $X.XX" or "ITEM NAME   X.XX"
        // Strategy: look for lines containing a price pattern, extract item name as prefix.
        for line in lines {
            if let item = extractLineItem(from: line) {
                scannedItems.append(item)
            }
        }

        return ReceiptScanResult(
            items: scannedItems,
            storeNameRaw: storeNameRaw,
            receiptDate: receiptDate,
            rawLines: rawLines
        )
    }

    // MARK: - Line-item extraction

    // Matches: optional leading text, then a price at the end of the line.
    // Examples:
    //   "WHOLE MILK 2L           2.99"
    //   "BANANAS                $1.49 B"
    //   "ORG SPINACH            3.99 F"
    private let pricePattern = try! NSRegularExpression(
        pattern: #"^(.+?)\s+\$?([0-9]+\.[0-9]{2})\s*[A-Z]?$"#,
        options: .caseInsensitive
    )

    // Lines to skip — totals, tax, payment lines, headers.
    private let skipKeywords = [
        "subtotal", "sub total", "total", "tax", "hst", "gst",
        "pst", "cash", "change", "debit", "credit", "visa",
        "mastercard", "balance", "savings", "you saved", "points",
        "receipt", "thank you", "cashier", "store #", "tel:", "www."
    ]

    private func extractLineItem(from line: RecognisedLine) -> ScannedLineItem? {
        let text = line.text
        let lower = text.lowercased()

        // Skip non-item lines.
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
        guard nameRaw.count >= 2 else { return nil }  // ignore single-char artefacts

        return ScannedLineItem(
            nameRaw:         nameRaw,
            nameNormalised:  normalise(nameRaw),
            price:           price,
            confidence:      line.confidence
        )
    }

    // MARK: - Name normalisation

    // Lowercases, strips unit suffixes, collapses whitespace.
    // "WHOLE MILK 2L" → "whole milk"
    // "ORG SPINACH 142G" → "org spinach"
    private let unitSuffixPattern = try! NSRegularExpression(
        pattern: #"\s*\d+\s*(ml|l|g|kg|oz|lb|lbs|pk|ct|ea)\b"#,
        options: .caseInsensitive
    )

    private func normalise(_ raw: String) -> String {
        var s = raw.lowercased()
        let r = NSRange(s.startIndex..., in: s)
        s = unitSuffixPattern.stringByReplacingMatches(in: s, range: r, withTemplate: "")
        s = s.trimmingCharacters(in: .whitespacesAndNewlines)
        // Collapse multiple spaces.
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
