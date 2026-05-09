// ParsedReceiptItem.swift — SmartCart/Models/ParsedReceiptItem.swift
// OCR-extracted line item from a scanned receipt. NOT persisted to SQLite.
// ReceiptReviewView shows a list of these to the user.
// Confirmed items are passed to DatabaseManager.upsertItem() which creates
// or updates the canonical Item + UserItem rows.

import Foundation

// How confident ReceiptParser is that this line is a real grocery product.
// Controls pre-selection and row highlight colour in ReceiptReviewView.
enum ConfidenceLevel {
    case high    // Strong name + clear price — pre-selected for import
    case medium  // Name or price ambiguous — pre-selected but flagged
    case low     // Likely noise (tax, total, store header) — deselected by default
}

struct ParsedReceiptItem: Identifiable {
    let id: UUID             // Stable ID for SwiftUI diffing — not a DB key
    let rawName: String      // Raw OCR text before normalisation
    let normalisedName: String
    let parsedPrice: Double? // nil if no price found within ±2 lines of the name
    let confidence: ConfidenceLevel
    var isIncluded: Bool     // Toggled in ReceiptReviewView; starts true for high/medium

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
