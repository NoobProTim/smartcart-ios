// NameNormaliser.swift — SmartCart/Utilities/NameNormaliser.swift
// Converts raw OCR receipt text into a clean, lowercase key used for deduplication
// and Flipp search queries.
// Example: "SALTED BTR 454G" → "salted btr 454g"

import Foundation

enum NameNormaliser {

    /// Lowercases, strips non-alphanumeric characters (except spaces), collapses whitespace.
    static func normalise(_ raw: String) -> String {
        var s = raw.lowercased()
        s = s.components(separatedBy: .alphanumerics.union(.whitespaces).inverted).joined()
        s = s.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        return s.trimmingCharacters(in: .whitespaces)
    }

    /// Computes a name-match score between a normalised receipt name and a Flipp product name.
    /// Score = overlapping token count / max token count of either string.
    /// Returns 0.0–1.0. Use Constants.flippMatchThreshold (0.5) as the minimum acceptable score.
    static func matchScore(receiptName: String, flippName: String) -> Double {
        let a = Set(normalise(receiptName).split(separator: " ").map(String.init))
        let b = Set(normalise(flippName).split(separator: " ").map(String.init))
        guard !a.isEmpty, !b.isEmpty else { return 0 }
        let intersection = a.intersection(b).count
        let maxCount = max(a.count, b.count)
        return Double(intersection) / Double(maxCount)
    }
}
