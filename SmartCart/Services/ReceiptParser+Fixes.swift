// ReceiptParser+Fixes.swift
// SmartCart — Services/ReceiptParser+Fixes.swift
//
// P0-2: Replaces the original parse() return type with a typed ScanResult enum.
// Silent failures (nil cgImage, Vision timeout, empty item list) now return
// distinct cases so ReceiptScannerView can show the right error message.

import UIKit
import Vision

// What happened when we tried to scan the receipt image.
enum ScanResult {
    case success([ParsedReceiptItem]) // At least one item extracted — proceed to review
    case empty                        // Vision ran fine but found no grocery lines
    case timeout                      // Vision semaphore exceeded 10-second limit
    case imageError                   // image.cgImage was nil — can't process
}

extension ReceiptParser {

    // Typed replacement for parse(image:) — use this version everywhere.
    // Only call showReview = true when result is .success with ≥ 1 item.
    func scanReceipt(image: UIImage) -> ScanResult {
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
        let handler = VNImageRequestHandler(cgImage: cgImage, options: [:])
        try? handler.perform([request])
        guard semaphore.wait(timeout: .now() + 10) != .timedOut else { return .timeout }
        let items = filterGroceryLines(recognisedLines)
        guard !items.isEmpty else { return .empty }
        return .success(items)
    }
}
