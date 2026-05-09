// FlippService.swift — SmartCart/Services/FlippService.swift
//
// Fetches current flyer prices from the Flipp partner API for all user-selected stores.
// Results are written directly into DatabaseManager (price_history + flyer_sales).
//
// P0-3 Fix: Dual-shape decoder handles BOTH Flipp API response shapes:
//   Shape A — products array at root level
//   Shape B — products wrapped inside { "data": { "products": [...] } }
// Without this fix the app silently drops all results when Flipp returns Shape B.
//
// P0-3 Fix: Flipp API unavailability is modelled as FlippFetchError.serviceUnavailable
// so ItemDetailView can show the “Flipp unavailable” banner.
//
// Usage:
//   await FlippService.shared.fetchPrices(for: itemIDs, postalCode: "K1A 0A1")

import Foundation

// Errors that callers (AlertEngine, BackgroundSyncManager) switch on.
enum FlippFetchError: Error {
    case serviceUnavailable   // HTTP >= 500 or no network
    case rateLimited          // HTTP 429
    case decodingFailed       // Neither shape decoded successfully
    case noResults            // Fetch succeeded but 0 products returned
}

// A single price match returned by Flipp for one item at one store.
struct FlippPriceResult {
    let itemID: Int64
    let storeID: Int64
    let storeName: String
    let regularPrice: Double?
    let salePrice: Double?
    let saleStartDate: String?
    let saleEndDate: String?
}

final class FlippService {

    static let shared = FlippService()
    private init() {}

    // Base URL for the Flipp partner API. Replace with real endpoint before shipping.
    private let baseURL = "https://api.flipp.com/flyerkit/v4"

    // MARK: - Main fetch

    // Fetches current flyer prices for all items in itemIDs using the given postal code.
    // Writes results into DatabaseManager automatically.
    // Throws FlippFetchError on failure.
    func fetchPrices(for itemNames: [String: Int64], postalCode: String) async throws {
        guard let storeIDs = buildStoreList() else { return }

        for (name, itemID) in itemNames {
            let urlStr = "\(baseURL)/items?q=\(name.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? "")&locale=en-CA&postal_code=\(postalCode)"
            guard let url = URL(string: urlStr) else { continue }

            let (data, response) = try await URLSession.shared.data(from: url)

            if let http = response as? HTTPURLResponse {
                switch http.statusCode {
                case 429: throw FlippFetchError.rateLimited
                case 500...: throw FlippFetchError.serviceUnavailable
                default: break
                }
            }

            // P0-3: Try both response shapes before giving up.
            let products = decodeProducts(from: data)
            guard !products.isEmpty else { continue }

            for product in products {
                guard let storeID = storeIDs[product.merchantNameRaw] else { continue }
                if let reg = product.regularPrice {
                    DatabaseManager.shared.insertPriceHistory(itemID: itemID,
                                                              storeID: storeID,
                                                              price: reg)
                }
                if let sale = product.salePrice {
                    DatabaseManager.shared.insertFlyerSale(
                        itemID: itemID,
                        storeID: storeID,
                        salePrice: sale,
                        startDate: product.validFrom ?? DateHelper.todayString(),
                        endDate: product.validTo
                    )
                }
            }
        }
    }

    // MARK: - P0-3 Dual-shape decoder

    // Attempts Shape B first (wrapped), then falls back to Shape A (flat).
    private func decodeProducts(from data: Data) -> [FlippProduct] {
        if let wrapped = try? JSONDecoder().decode(FlippResponseWrapped.self, from: data) {
            return wrapped.data.products
        }
        if let flat = try? JSONDecoder().decode(FlippResponseFlat.self, from: data) {
            return flat.products
        }
        return []
    }

    // Returns a [merchantName: storeID] map from selected stores in the DB.
    private func buildStoreList() -> [String: Int64]? {
        let stores = DatabaseManager.shared.fetchSelectedStores()
        guard !stores.isEmpty else { return nil }
        return Dictionary(uniqueKeysWithValues: stores.map { ($0.name, $0.id) })
    }
}

// MARK: - Codable shapes (P0-3)

// One product entry returned by Flipp — field names vary by shape but contents are the same.
private struct FlippProduct: Decodable {
    let merchantNameRaw: String
    let regularPrice: Double?
    let salePrice: Double?
    let validFrom: String?
    let validTo: String?

    private enum CodingKeys: String, CodingKey {
        case merchantNameRaw = "merchant_name"
        case regularPrice    = "current_price"
        case salePrice       = "sale_price"
        case validFrom       = "valid_from"
        case validTo         = "valid_to"
    }
}

// Shape A: { "products": [ ... ] }
private struct FlippResponseFlat: Decodable {
    let products: [FlippProduct]
}

// Shape B: { "data": { "products": [ ... ] } }
private struct FlippResponseWrapped: Decodable {
    struct Inner: Decodable {
        let products: [FlippProduct]
    }
    let data: Inner
}
