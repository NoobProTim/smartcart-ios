// FlippService.swift — SmartCart/Services/FlippService.swift
// Fetches flyer and price data from the Flipp API.
// Primary endpoint: backflipp.wishabi.com/flipp/items/search
// Uses postal code from user_settings to localise results.

import Foundation

final class FlippService {
    static let shared = FlippService()
    private init() {}

    private let baseURL = "https://backflipp.wishabi.com/flipp/items/search"
    private let session = URLSession.shared

    // ─────────────────────────────────────────────
    // MARK: - Flipp response model
    // ─────────────────────────────────────────────

    struct FlippItem: Decodable {
        let name: String
        let currentPrice: Double
        let validTo: String?
        let storeCode: String?
        enum CodingKeys: String, CodingKey {
            case name
            case currentPrice = "current_price"
            case validTo = "valid_to"
            case storeCode = "retailer_name"
        }
        // Custom decoder handles Flipp returning currentPrice as either Double or String
        init(from decoder: Decoder) throws {
            let c = try decoder.container(keyedBy: CodingKeys.self)
            name = try c.decode(String.self, forKey: .name)
            validTo = try c.decodeIfPresent(String.self, forKey: .validTo)
            storeCode = try c.decodeIfPresent(String.self, forKey: .storeCode)
            if let d = try? c.decode(Double.self, forKey: .currentPrice) {
                currentPrice = d
            } else if let s = try? c.decode(String.self, forKey: .currentPrice), let d = Double(s) {
                currentPrice = d
            } else {
                currentPrice = 0.0
            }
        }
    }

    // Flipp sometimes wraps the array in {"items": [...]}
    private struct FlippResponseWrapper: Decodable { let items: [FlippItem] }

    /// Tries root-array decode first, then wrapped-object fallback.
    func decodeFlippResponse(_ data: Data) -> [FlippItem] {
        if let items = try? JSONDecoder().decode([FlippItem].self, from: data) { return items }
        if let wrapper = try? JSONDecoder().decode(FlippResponseWrapper.self, from: data) { return wrapper.items }
        print("[FlippService] Unrecognised JSON shape")
        return []
    }

    // ─────────────────────────────────────────────
    // MARK: - Fetch
    // ─────────────────────────────────────────────

    /// Fetches Flipp prices for a list of user items. Writes results to price_history and flyer_sales.
    func fetchPrices(for userItems: [UserItem]) async {
        let postalCode = DatabaseManager.shared.getSetting(key: "user_postal_code") ?? ""
        let stores = DatabaseManager.shared.fetchSelectedStores()

        for userItem in userItems {
            await fetchPrice(for: userItem, postalCode: postalCode, stores: stores)
        }
    }

    private func fetchPrice(for userItem: UserItem, postalCode: String, stores: [Store]) async {
        let searchTerms = buildSearchTerms(for: userItem.nameDisplay)
        var foundResults = false

        for term in searchTerms {
            guard var components = URLComponents(string: baseURL) else { continue }
            components.queryItems = [
                URLQueryItem(name: "locale", value: "en-CA"),
                URLQueryItem(name: "postal_code", value: postalCode),
                URLQueryItem(name: "q", value: term)
            ]
            guard let url = components.url else { continue }

            do {
                let (data, _) = try await session.data(from: url)
                let items = decodeFlippResponse(data)
                let matched = items.filter { item in
                    NameNormaliser.matchScore(
                        receiptName: userItem.nameDisplay,
                        flippName: item.name
                    ) >= Constants.flippMatchThreshold
                }
                if !matched.isEmpty {
                    processFlippResults(matched, for: userItem, stores: stores)
                    foundResults = true
                    break
                }
            } catch {
                print("[FlippService] Fetch error for \(term): \(error)")
            }
        }

        if !foundResults {
            markFlippUnavailable(itemID: userItem.itemID)
        }
    }

    /// Writes matched Flipp results to the database.
    private func processFlippResults(_ items: [FlippItem], for userItem: UserItem, stores: [Store]) {
        let db = DatabaseManager.shared
        for item in items {
            // Skip zero prices (produce/deli items priced by weight) — would cause false alerts
            guard item.currentPrice > 0.01 else { continue }

            // Match Flipp retailer name to a stored store row
            guard let store = stores.first(where: {
                $0.name.lowercased().contains(item.storeCode?.lowercased() ?? "")
            }) else { continue }

            if let validToString = item.validTo, !validToString.isEmpty {
                // It's a sale — write to flyer_sales
                let formatter = ISO8601DateFormatter()
                let endDate = formatter.date(from: validToString)
                let startDate = Date()
                db.insertFlyerSale(
                    itemID: userItem.itemID, storeID: store.id,
                    salePrice: item.currentPrice, startDate: startDate,
                    endDate: endDate ?? Calendar.current.date(byAdding: .day,
                        value: Constants.flyerSaleExpiryFallbackDays, to: startDate),
                    source: endDate == nil ? "flipp_estimated_expiry" : "flipp"
                )
            } else {
                // Regular shelf price — write to price_history
                db.insertPriceHistory(
                    itemID: userItem.itemID, storeID: store.id,
                    price: item.currentPrice, source: "flipp"
                )
            }
        }
    }

    /// Builds 3 search term variants for fallback matching.
    private func buildSearchTerms(for displayName: String) -> [String] {
        let normalised = NameNormaliser.normalise(displayName)
        let tokens = normalised.split(separator: " ").map(String.init)
        var terms = [normalised]
        if let first = tokens.first { terms.append(first) }
        if tokens.count > 1 { terms.append(tokens.prefix(2).joined(separator: " ")) }
        return Array(NSOrderedSet(array: terms)) as! [String]
    }

    /// Writes a flag to user_settings when all Flipp search variants fail.
    /// Surfaced as 'Price data unavailable' in ItemDetailView.
    func markFlippUnavailable(itemID: Int64) {
        DatabaseManager.shared.setSetting(
            key: "flipp_no_data_\(itemID)",
            value: ISO8601DateFormatter().string(from: Date())
        )
    }
}
