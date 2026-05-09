// NameNormaliser.swift — SmartCart/Utilities/NameNormaliser.swift
//
// Converts raw OCR product names into a consistent lowercase key used for:
//   1. Deduplication in the `items` table (nameNormalised UNIQUE constraint)
//   2. Flipp API search queries
//
// Why normalise? "Oat Milk OATLY 1L", "OATLY OAT MILK 1 L", and "oat milk oatly 1l"
// are the same product. Without normalisation each receipt scan creates a new item row.
//
// Rules applied (in order):
//   1. Lowercase
//   2. Remove non-alphanumeric characters except spaces
//   3. Expand common abbreviations (tbl → tablespoon, etc.)
//   4. Collapse multiple spaces
//   5. Trim whitespace

import Foundation

enum NameNormaliser {

    // Maps OCR abbreviations to their full forms.
    // Expand this list as new receipt formats are encountered.
    private static let abbreviations: [String: String] = [
        "tbl":  "tablespoon",
        "tsp":  "teaspoon",
        "pkg":  "package",
        "btl":  "bottle",
        "org":  "organic",
        "fz":   "frozen",
        "chkn": "chicken",
        "brf":  "beef"
    ]

    // Main entry point. Pass the raw OCR string; receive a stable lowercase key.
    static func normalise(_ raw: String) -> String {
        var result = raw.lowercased()

        // Remove punctuation and special characters, keep spaces and alphanumerics.
        result = result
            .components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted)
            .joined(separator: " ")

        // Expand abbreviations (whole-word match only).
        var words = result.components(separatedBy: .whitespaces)
        words = words.map { abbreviations[$0] ?? $0 }
        result = words.joined(separator: " ")

        // Collapse multiple spaces and trim.
        result = result
            .components(separatedBy: .whitespaces)
            .filter { !$0.isEmpty }
            .joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)

        return result
    }
}
