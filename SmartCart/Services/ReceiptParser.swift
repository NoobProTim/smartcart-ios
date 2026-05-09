// ReceiptParser.swift — SmartCart/Services/ReceiptParser.swift
//
// Converts raw OCR text (from VisionKit) into a list of ParsedReceiptItem values.
// Called by ReceiptScannerView after Vision framework finishes reading the image.
//
// P0-2 Fix: ScanResult enum replaces the old Bool return type.
// This lets ReceiptScannerView show a specific error banner for each failure mode
// instead of a single generic “scan failed” message.
//
// Pipeline:
//   1. Split raw text into lines
//   2. Reject noise lines (totals, tax, store headers, barcodes)
//   3. Extract price from the line or adjacent lines
//   4. Normalise item name via NameNormaliser
//   5. Score confidence
//   6. Return ScanResult.success([ParsedReceiptItem]) or a specific failure case

import Foundation

// P0-2: Typed result — ReceiptScannerView switches on this to choose the right banner.
enum ScanResult {
    case success([ParsedReceiptItem])  // At least 1 item found
    case noItemsFound                  // OCR ran but 0 products identified
    case imageTooBlurry                // Vision confidence below threshold
    case emptyInput                    // Zero text extracted (black image, etc.)
    case unknownError(String)          // Catch-all with debug description
}

enum ReceiptParser {

    // MARK: - Main entry point

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
            let price = extractPrice(from: line) ?? extractPrice(fromAdjacentLines: lines, index: index)
            let raw = stripPrice(from: line)
            guard raw.count >= 3 else { return nil }  // ignore very short strings
            let normalised = NameNormaliser.normalise(raw)
            let confidence = score(name: raw, price: price)
            return ParsedReceiptItem(rawName: raw, normalisedName: normalised,
                                     parsedPrice: price, confidence: confidence)
        }

        return candidates.isEmpty ? .noItemsFound : .success(candidates)
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

    // Removes the price portion from a name string so it isn’t included in the display name.
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
