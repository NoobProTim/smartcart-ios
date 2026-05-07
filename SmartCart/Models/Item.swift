// Item.swift — SmartCart/Models/Item.swift
// Canonical grocery product. Maps to `items` table.
// nameNormalised is the deduplication key — two receipt lines with the same
// normalised name resolve to the same Item row.

import Foundation

struct Item: Identifiable, Hashable {
    let id: Int64              // Primary key
    let nameNormalised: String // Dedup + Flipp search key. e.g. "oatly oat milk 1l"
    let nameDisplay: String    // UI label. e.g. "Oat Milk — Oatly 1L"
    let category: String?      // nil until CategoryClassifier runs (post-MVP)
    let unit: String?          // e.g. "each", "100g", "L"
    let createdAt: Date
}
