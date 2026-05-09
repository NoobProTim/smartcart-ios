// FlippService.swift — SmartCart/Services/FlippService.swift
//
// Fetches current prices and flyer/sale events from the Flipp
// undocumented web endpoint (backflipp.wishabi.com).
//
// ATLAS Task #1-R1 — Deliverable 3-R1 routing logic:
//   IF valid_to IS NOT NULL AND valid_to >= today → flyer/sale item
//     → write to flyer_sales + write pre_price to price_history
//   ELSE → regular shelf price
//     → write to price_history only
//
// Call FlippService.shared.syncAllItems() from BackgroundSyncManager.

import Foundation

final class FlippService {

    static let shared = FlippService()
    private let db = DatabaseManager.shared
    private let session = URLSession.shared

    // Flipp endpoint base — undocumented, may change.
    // ATLAS Risk R-1: monitor for breakage; per-store scraper is fallback.
    private let baseURL = "https://backflipp.wishabi.com/flipp/items/search"

    private init() {}

    // MARK: - Public entry point

    // Syncs prices for every active user_item against all selected stores.
    // Called from BackgroundSyncManager after BGAppRefreshTask fires.
    func syncAllItems() async {
        let userItems = db.fetchUserItems()
        let stores    = db.fetchSelectedStores()
        guard !userItems.isEmpty, !stores.isEmpty else { return }

        let postalCode = db.getSetting(key: "user_postal_code") ?? ""

        for item in userItems {
            for store in stores {
                await fetchPrice(
                    itemName: item.nameDisplay,
                    itemID: item.itemID,
                    store: store,
                    postalCode: postalCode
                )
            }
        }

        db.setSetting(key: "last_price_refresh", value: ISO8601DateFormatter().string(from: Date()))
    }

    // MARK: - Per-item fetch

    private func fetchPrice(
        itemName: String,
        itemID: Int64,
        store: Store,
        postalCode: String
    ) async {
        guard var components = URLComponents(string: baseURL) else { return }

        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "q",           value: itemName),
            URLQueryItem(name: "locale",      value: "en-CA"),
        ]
        if !postalCode.isEmpty {
            queryItems.append(URLQueryItem(name: "postal_code", value: postalCode))
        }
        if let flippID = store.flippID {
            queryItems.append(URLQueryItem(name: "flyer_merchant_id", value: flippID))
        }
        components.queryItems = queryItems

        guard let url = components.url else { return }

        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("SmartCart/1.0 (iOS)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 15

        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse,
                  (200...299).contains(http.statusCode) else {
                print("[FlippService] Non-2xx for \(itemName) @ \(store.name)")
                return
            }
            try processResponse(data: data, itemID: itemID, storeID: store.id, storeName: store.name)
        } catch {
            print("[FlippService] Fetch error for \(itemName): \(error)")
        }
    }

    // MARK: - Response parsing & routing

    private func processResponse(data: Data, itemID: Int64, storeID: Int64, storeName: String) throws {
        let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
        // Flipp returns { "items": [ { ... }, ... ] }
        guard let items = json?["items"] as? [[String: Any]] else { return }

        let today = Calendar.current.startOfDay(for: Date())
        let isoParser = ISO8601DateFormatter()
        isoParser.formatOptions = [.withFullDate]

        for raw in items {
            // --- Parse core fields ---
            guard let currentPrice = raw["current_price"] as? Double else { continue }

            let prePrice      = raw["pre_price"]    as? Double
            let validFromStr  = raw["valid_from"]   as? String
            let validToStr    = raw["valid_to"]     as? String
            let validFrom     = validFromStr.flatMap { isoParser.date(from: $0) }
            var validTo       = validToStr.flatMap   { isoParser.date(from: $0) }

            // --- ATLAS routing logic (Deliverable 3-R1) ---
            let isSaleItem: Bool
            if let end = validTo, end >= today {
                isSaleItem = true
            } else if validTo == nil && prePrice != nil && prePrice! > currentPrice {
                // ATLAS R-9 fallback: valid_to missing but pre_price present → treat as sale
                // Default sale_end_date to +7 days.
                validTo = Calendar.current.date(byAdding: .day, value: 7, to: validFrom ?? today)
                isSaleItem = true
            } else {
                isSaleItem = false
            }

            if isSaleItem {
                // Write sale event to flyer_sales (INSERT OR IGNORE + refresh fetched_at).
                db.insertFlyerSale(
                    itemID:    itemID,
                    storeID:   storeID,
                    salePrice: currentPrice,
                    startDate: validFrom ?? today,
                    endDate:   validTo,
                    source:    validToStr != nil ? "flipp" : "flipp_estimated_expiry"
                )
                // Write the pre-sale regular price to price_history so the
                // 90-day rolling average is not contaminated by sale prices.
                if let regular = prePrice {
                    db.insertPriceHistory(
                        itemID:  itemID,
                        storeID: storeID,
                        price:   regular,
                        source:  "flipp"
                    )
                }
            } else {
                // Regular shelf price — write to price_history only.
                db.insertPriceHistory(
                    itemID:  itemID,
                    storeID: storeID,
                    price:   currentPrice,
                    source:  "flipp"
                )
            }
        }
    }
}
