// ReceiptParser.swift — SmartCart/Services/ReceiptParser.swift
//
// Converts raw OCR text (from VisionKit) into a list of ParsedReceiptItem values.
// Called by ReceiptScannerView after Vision framework finishes reading the image.
//
// P0-2 Fix: ScanResult enum replaces the old Bool return type.
// This lets ReceiptScannerView show a specific error banner for each failure mode
// instead of a single generic "scan failed" message.
//
// HIGH-4 fix (Task #6):
//   parse() now calls CategoryClassifier.classify(normalisedName:) for each candidate
//   and stores the result in ParsedReceiptItem.suggestedCycleDays.
//   ReplenishmentEngine uses this as the seed cycle for new items until enough
//   purchase history accumulates for inference (>= 3 purchases).
//
// scanReceipt(image:) merged back in (Task #6):
//   Previously lived in ReceiptParser+Fixes.swift (now deleted — compile conflict).
//   Owned by this file going forward. ScanResult cases are canonical here.
//
// Pipeline:
//   1. Split raw text into lines
//   2. Reject noise lines (totals, tax, store headers, barcodes)
//   3. Extract price from the line or adjacent lines
//   4. Normalise item name via NameNormaliser
//   5. Score confidence
//   6. Classify category → suggestedCycleDays via CategoryClassifier
//   7. Return ScanResult.success([ParsedReceiptItem]) or a specific failure case

import UIKit
import Vision
import Foundation

// P0-2: Typed result — ReceiptScannerView switches on this to choose the right banner.
// CANONICAL definition — do not redeclare in any extension file.
enum ScanResult {
    case success([ParsedReceiptItem])  // At least 1 item found
    case noItemsFound                  // OCR ran but 0 products identified
    case imageTooBlurry                // Vision confidence below threshold
    case emptyInput                    // Zero text extracted (black image, etc.)
    case unknownError(String)          // Catch-all with debug description
}

enum ReceiptParser {

    // MARK: - parse(rawText:)
    // Main text-parsing entry point.
    // Call this with the full OCR output string from VNRecognizeTextRequest.
    // Returns a ScanResult — handle every case in ReceiptScannerView.
    static func parse(rawText: String) -> ScanResult {
        let trimmed = rawText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return .emptyInput }

        let lines = trimmed.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        let candidates = lines.enumerated().compactMap { (index, line) -> ParsedReceiptItem? in
            guard !isNoiseLine(line) else { return nil }
            let price      = extractPrice(from: line) ?? extractPrice(fromAdjacentLines: lines, index: index)
            let raw        = stripPrice(from: line)
            guard raw.count >= 3 else { return nil }  // ignore very short strings
            let normalised = NameNormaliser.normalise(raw)
            let confidence = score(name: raw, price: price)

            // HIGH-4: classify returns a category-appropriate cycle in days,
            // or nil if no keyword match (engine will use 14-day default).
            let cycleDays  = CategoryClassifier.classify(normalisedName: normalised)

            return ParsedReceiptItem(
                rawName: raw,
                normalisedName: normalised,
                parsedPrice: price,
                confidence: confidence,
                suggestedCycleDays: cycleDays
            )
        }

        return candidates.isEmpty ? .noItemsFound : .success(candidates)
    }

    // MARK: - scanReceipt(image:)
    // Image-scanning entry point — wraps Vision OCR and delegates to parse(rawText:).
    // Merged back from deleted ReceiptParser+Fixes.swift (Task #6 cleanup).
    // Use this when you have a UIImage; use parse(rawText:) when you already
    // have the OCR string (e.g. in tests or from a live VNRecognizeTextRequest callback).
    //
    // Returns a typed ScanResult:
    //   .imageError  — image.cgImage was nil; can't process
    //   .noItemsFound / .emptyInput — Vision ran but found nothing useful
    //   .success([ParsedReceiptItem]) — at least one item extracted
    static func scanReceipt(image: UIImage) -> ScanResult {
        guard let cgImage = image.cgImage else { return .unknownError("cgImage was nil") }

        var recognisedLines: [String] = []
        let semaphore = DispatchSemaphore(value: 0)

        let request = VNRecognizeTextRequest { request, error in
            defer { semaphore.signal() }
            guard error == nil,
                  let observations = request.results as? [VNRecognizedTextObservation]
            else { return }
            recognisedLines = observations.compactMap { $0.topCandidates(1).first?.string }
        }
        request.recognitionLevel = .accurate

        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])

        // Wait up to 10 seconds for Vision to finish.
        // On a current-generation iPhone the accurate pass takes < 2 s for a full receipt.
        guard semaphore.wait(timeout: .now() + 10) != .timedOut else {
            return .unknownError("Vision timed out after 10 seconds")
        }

        guard !recognisedLines.isEmpty else { return .emptyInput }

        let rawText = recognisedLines.joined(separator: "\n")
        return parse(rawText: rawText)
    }

    // MARK: - Noise detection

    // Returns true for lines that are not grocery products:
    // totals, taxes, cashier lines, barcodes, and purely numeric strings.
    private static func isNoiseLine(_ line: String) -> Bool {
        let upper = line.uppercased()
        let noiseKeywords = ["TOTAL", "TAX", "SUBTOTAL", "CASH", "CHANGE",
                             "DEBIT", "CREDIT", "VISA", "MASTERCARD", "THANK YOU",
                             "CASHIER", "RECEIPT", "STORE #", "TEL:", "HST", "GST", "PST"]
        if noiseKeywords.contains(where: { upper.contains($0) }) { return true }
        // Purely numeric (barcode or store number)
        if line.allSatisfy({ $0.isNumber || $0 == "-" || $0 == "." }) { return true }
        return false
    }

    // MARK: - Price extraction

    // Looks for a dollar amount in the format 0.00 or 0,00 on the same line.
    private static func extractPrice(from line: String) -> Double? {
        let pattern = #"\d+[.,]\d{2}"#
        guard let range = line.range(of: pattern, options: .regularExpression) else { return nil }
        let raw = String(line[range]).replacingOccurrences(of: ",", with: ".")
        return Double(raw)
    }

    // Checks the line above and below when no price is on the product line itself.
    // Some receipt formats print prices on a separate line.
    private static func extractPrice(fromAdjacentLines lines: [String], index: Int) -> Double? {
        let indices = [index - 1, index + 1].filter { $0 >= 0 && $0 < lines.count }
        for i in indices {
            if let p = extractPrice(from: lines[i]) { return p }
        }
        return nil
    }

    // Removes the price portion from a name string so it isn't included in the display name.
    private static func stripPrice(from line: String) -> String {
        let pattern = #"\s*\d+[.,]\d{2}\s*[A-Z]?$"#
        return line.replacingOccurrences(of: pattern, with: "",
                                         options: .regularExpression)
                   .trimmingCharacters(in: .whitespaces)
    }

    // MARK: - Confidence scoring

    // Assigns a ConfidenceLevel based on name length and whether a price was found.
    private static func score(name: String, price: Double?) -> ConfidenceLevel {
        let words = name.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
        if words.count >= 2 && price != nil { return .high }
        if words.count >= 1 && price != nil { return .medium }
        return .low
    }
}
