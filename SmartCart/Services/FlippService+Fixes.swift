// FlippService+Fixes.swift
// SmartCart — Services/FlippService+Fixes.swift
//
// P0-3: Dual-shape JSON decoder.
//   • Flipp sometimes returns a root array: [{...}, {...}]
//   • Flipp sometimes returns a wrapper:   {"items": [{...}, {...}]}
//   • current_price is occasionally a String instead of a Double
//   On terminal failure, writes user_settings key "flipp_no_data_{itemID}"
//   so ItemDetailView can show "Price data unavailable — tap to retry".

import Foundation

// Flipp item with tolerant current_price decoding.
struct FlippItem: Decodable {
    let name: String
    let currentPrice: Double
    let validTo: String?
    let storeCode: String?

    enum CodingKeys: String, CodingKey {
        case name
        case currentPrice = "current_price"
        case validTo      = "valid_to"
        case storeCode    = "retailer_name"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name      = try c.decode(String.self, forKey: .name)
        validTo   = try c.decodeIfPresent(String.self, forKey: .validTo)
        storeCode = try c.decodeIfPresent(String.self, forKey: .storeCode)
        // Accept Double or String for current_price.
        if let d = try? c.decode(Double.self, forKey: .currentPrice) {
            currentPrice = d
        } else if let s = try? c.decode(String.self, forKey: .currentPrice), let d = Double(s) {
            currentPrice = d
        } else {
            currentPrice = 0.0
        }
    }
}

// Wrapper shape: { "items": [...] }
private struct FlippResponseWrapper: Decodable { let items: [FlippItem] }

extension FlippService {

    // Try root-array decode first, then wrapper-object fallback.
    // Returns [] and logs on complete failure — never throws to the caller.
    func decodeFlippResponse(_ data: Data) -> [FlippItem] {
        if let items = try? JSONDecoder().decode([FlippItem].self, from: data) { return items }
        if let wrapper = try? JSONDecoder().decode(FlippResponseWrapper.self, from: data) { return wrapper.items }
        print("[FlippService] Unrecognised JSON shape")
        return []
    }

    // Writes a user_settings flag so ItemDetailView shows the unavailable banner.
    // Call this after all retries are exhausted.
    func markFlippUnavailable(itemID: Int64) {
        DatabaseManager.shared.setSetting(
            key: "flipp_no_data_\(itemID)",
            value: ISO8601DateFormatter().string(from: Date())
        )
    }
}
