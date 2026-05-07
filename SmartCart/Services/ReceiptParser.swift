// ReceiptParser.swift — SmartCart/Services/ReceiptParser.swift
// Runs Apple Vision OCR on a captured receipt image and extracts grocery line items.
// Returns a typed ScanResult so the caller always knows why a scan succeeded or failed.

import Foundation
import Vision
import UIKit

// Typed result — callers switch on this instead of checking for empty arrays.
enum ScanResult {
    case success([ParsedReceiptItem])
    case empty      // OCR ran but found no grocery items
    case timeout    // Vision took longer than 10 seconds
    case imageError // cgImage conversion failed
}

struct ReceiptParser {

    /// Runs synchronous OCR on the provided image and returns a typed ScanResult.
    func parse(image: UIImage) -> ScanResult {
        guard let cgImage = image.cgImage else { return .imageError }

        var recognisedLines: [String] = []
        let semaphore = DispatchSemaphore(value: 0)

        let request = VNRecognizeTextRequest { request, error in
            defer { semaphore.signal() }
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation] else { return }
            recognisedLines = observations.compactMap { $0.topCandidates(1).first?.string }
        }
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = false  // OFF: grocery shorthand breaks spell-check

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        guard semaphore.wait(timeout: .now() + 10) != .timedOut else { return .timeout }

        let items = filterGroceryLines(recognisedLines)
        guard !items.isEmpty else { return .empty }
        return .success(items)
    }

    /// Filters raw OCR lines down to likely grocery items.
    /// Skips headers, totals, tax lines, and lines with no price nearby.
    private func filterGroceryLines(_ lines: [String]) -> [ParsedReceiptItem] {
        var results: [ParsedReceiptItem] = []
        let pricePattern = try? NSRegularExpression(pattern: #"\$?\d+\.\d{2}"#)

        for (index, line) in lines.enumerated() {
            let upper = line.uppercased()

            // Skip lines that are clearly not grocery items
            if upper.contains("TOTAL") || upper.contains("TAX") ||
               upper.contains("SUBTOTAL") || upper.contains("CHANGE") ||
               upper.contains("CASH") || upper.contains("DEBIT") ||
               upper.contains("VISA") || upper.contains("MASTERCARD") {
                continue
            }

            // Look for a price on this line or the next 2 lines
            let searchRange = lines[index..<min(index+3, lines.count)].joined(separator: " ")
            let range = NSRange(searchRange.startIndex..., in: searchRange)
            let hasPrice = pricePattern?.firstMatch(in: searchRange, range: range) != nil

            let normalisedName = NameNormaliser.normalise(line)
            guard normalisedName.count >= 3 else { continue } // Skip very short lines

            // Extract price if present
            var parsedPrice: Double? = nil
            if hasPrice, let match = pricePattern?.firstMatch(in: searchRange, range: range),
               let priceRange = Range(match.range, in: searchRange) {
                let priceStr = searchRange[priceRange].replacingOccurrences(of: "$", with: "")
                parsedPrice = Double(priceStr)
            }

            let confidence: ConfidenceLevel = hasPrice ? .high : .medium
            results.append(ParsedReceiptItem(
                rawName: line,
                normalisedName: normalisedName,
                parsedPrice: parsedPrice,
                confidence: confidence
            ))
        }
        return results
    }
}
