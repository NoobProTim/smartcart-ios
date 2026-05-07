// ParsedReceiptItem.swift — SmartCart/Models/ParsedReceiptItem.swift
// OCR-extracted line item from a scanned receipt. NOT persisted to SQLite.
// ReceiptReviewView shows a list of these to the user.
// Confirmed items are passed to DatabaseManager.upsertItem().

import Foundation

enum ConfidenceLevel {
    case high    // Strong name + clear price — pre-selected for import
    case medium  // Name or price ambiguous — pre-selected but flagged
    case low     // Likely noise (tax, total, store header) — deselected by default
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
