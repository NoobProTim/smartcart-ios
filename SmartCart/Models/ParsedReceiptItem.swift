// ParsedReceiptItem.swift — SmartCart/Models/ParsedReceiptItem.swift
// OCR-extracted line item from a scanned receipt. NOT persisted to SQLite.
// ReceiptReviewView shows a list of these to the user.
// Confirmed items are passed to DatabaseManager.upsertItem() which creates
// or updates the canonical Item + UserItem rows.
//
// HIGH-4 addition (Task #6):
//   suggestedCycleDays — populated by CategoryClassifier.classify(normalisedName:)
//   inside ReceiptParser.parse(). Nil means the classifier found no match and
//   ReplenishmentEngine will fall back to Constants.defaultReplenishmentDays (14 days).
//   ReceiptReviewViewModel passes this value to DatabaseManager when confirming import
//   so new items start with a category-appropriate cycle instead of the universal default.

import Foundation

// How confident ReceiptParser is that this line is a real grocery product.
// Controls pre-selection and row highlight colour in ReceiptReviewView.
enum ConfidenceLevel {
    case high    // Strong name + clear price — pre-selected for import
    case medium  // Name or price ambiguous — pre-selected but flagged
    case low     // Likely noise (tax, total, store header) — deselected by default
}

struct ParsedReceiptItem: Identifiable {
    let id: UUID              // Stable ID for SwiftUI diffing — not a DB key
    let rawName: String       // Raw OCR text before normalisation
    let normalisedName: String
    let parsedPrice: Double?  // nil if no price found within ±2 lines of the name
    let confidence: ConfidenceLevel
    let suggestedCycleDays: Int? // Category-based cycle hint from CategoryClassifier.
                                 // nil = no category match; engine uses default 14 days.
    var isIncluded: Bool      // Toggled in ReceiptReviewView; starts true for high/medium

    // suggestedCycleDays defaults to nil so existing call sites that don't
    // pass a classifier result compile without changes.
    init(rawName: String, normalisedName: String, parsedPrice: Double?,
         confidence: ConfidenceLevel, suggestedCycleDays: Int? = nil) {
        self.id                = UUID()
        self.rawName           = rawName
        self.normalisedName    = normalisedName
        self.parsedPrice       = parsedPrice
        self.confidence        = confidence
        self.suggestedCycleDays = suggestedCycleDays
        self.isIncluded        = confidence != .low
    }
}
