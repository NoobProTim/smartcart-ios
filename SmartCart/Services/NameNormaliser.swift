// NameNormaliser.swift
// SmartCart — Services/NameNormaliser.swift
//
// Converts raw grocery item names into a consistent lowercase token set
// used for deduplication and Flipp price matching.
//
// WHY THIS FILE EXISTS:
// Receipt OCR and Flipp return wildly different name formats for the same
// product (e.g. "OATLY OAT MLK 1L" vs "Oatly Oat Milk 1 Litre").
// This normaliser strips noise so comparisons are fair.
//
// NEW IN TASK #3 (P1-1):
// Added nameMatchScore(_:_:) — computes how similar two item names are
// based on token overlap. Used by FlippService to reject Flipp results
// that don't actually match the item being searched (e.g. "Ariel Pods"
// should NOT write prices to an item named "Ariel Liquid").

import Foundation

struct NameNormaliser {

    // MARK: - Stop Words
    // Common English/French words that carry no product meaning.
    // Stripped during normalisation so "Bag of Chips" and "Chips" match.
    private static let stopWords: Set<String> = [
        "a", "an", "the", "of", "with", "and", "or", "for", "in",
        "at", "to", "on", "by", "from", "into", "de", "du", "le",
        "la", "les", "et", "un", "une", "des", "bag", "pack",
        "case", "set", "box", "each", "pk", "ct"
    ]

    // MARK: - normalise(_:)
    // Converts a raw name to a lowercase, punctuation-stripped,
    // whitespace-normalised string. This is the canonical storage key.
    // Example: "OATLY Oat Milk 1L!" → "oatly oat milk 1l"
    static func normalise(_ input: String) -> String {
        var result = input.lowercased()
        result = result.components(separatedBy: CharacterSet.alphanumerics.union(.whitespaces).inverted).joined()
        result = result.components(separatedBy: .whitespaces).filter { !$0.isEmpty }.joined(separator: " ")
        return result
    }

    // MARK: - tokenise(_:)
    // Splits a normalised string into individual tokens (words).
    // Example: "oatly oat milk 1l" → ["oatly", "oat", "milk", "1l"]
    static func tokenise(_ normalisedName: String) -> [String] {
        return normalisedName.components(separatedBy: .whitespaces).filter { !$0.isEmpty }
    }

    // MARK: - tokeniseWithoutStopWords(_:)
    // Returns tokens from a normalised name with stop words removed.
    // Used for the third variant in FlippService term-variant retry (P1-3).
    // Example: "bag of chips" → ["chips"]
    static func tokeniseWithoutStopWords(_ normalisedName: String) -> [String] {
        return tokenise(normalisedName).filter { !stopWords.contains($0) }
    }

    // MARK: - nameMatchScore(_:_:) — ADDED P1-1
    // Computes how similar two item names are on a scale of 0.0 to 1.0.
    //
    // HOW: Normalise both names → tokenise → count shared tokens (intersection)
    // → divide by the larger token set (max). A result of 1.0 = identical tokens.
    //
    // Example: "ariel pods 42ct" vs "ariel liquid 1l"
    //   Intersection: {"ariel"} = 1 shared token
    //   Score: 1 / max(3, 3) = 0.33 → below threshold → SKIP
    //
    // Example: "oatly oat milk 1l" vs "oatly oat milk 946ml"
    //   Intersection: {"oatly", "oat", "milk"} = 3 shared tokens
    //   Score: 3 / max(4, 4) = 0.75 → above threshold → ALLOW
    static func nameMatchScore(_ a: String, _ b: String) -> Double {
        let tokensA = Set(tokenise(normalise(a)))
        let tokensB = Set(tokenise(normalise(b)))
        guard !tokensA.isEmpty, !tokensB.isEmpty else { return 0.0 }
        let intersectionCount = Double(tokensA.intersection(tokensB).count)
        let maxCount = Double(max(tokensA.count, tokensB.count))
        return intersectionCount / maxCount
    }
}
