// ParsedReceiptItem.swift — SmartCart/Models/ParsedReceiptItem.swift
// OCR-extracted line item from a scanned receipt. NOT persisted to SQLite.
// ReceiptReviewView shows a list of these to the user.

import Foundation

enum ConfidenceLevel {
    case high
    case medium
    case low
}

struct ParsedReceiptItem: Identifiable {
    let id: UUID
    let rawName: String
    let normalisedName: String
    let parsedPrice: Double?
    let confidence: ConfidenceLevel
    var isIncluded: Bool

    init(rawName: String, normalisedName: String, parsedPrice: Double?,
         confidence: ConfidenceLevel) {
        self.id = UUID()
        self.rawName = rawName
        self.normalisedName = normalisedName
        self.parsedPrice = parsedPrice
        self.confidence = confidence
        self.isIncluded = confidence != .low
    }
}
