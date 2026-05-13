// FlippService.swift
// SmartCart — Services/FlippService.swift
//
// Fetches flyer prices from Flipp's undocumented endpoint and writes results
// to price_history (regular prices) and flyer_sales (sale events).
//
// Flipp endpoint: https://backflipp.wishabi.com/flipp/items/search
// Parameters: ?locale=en-CA&postal_code={code}&q={query}
//
// UPDATED IN TASK #3 (P1-3):
// Removed ScraperFallback entirely. The HTML scraper was fetching raw page
// HTML from Loblaws, No Frills, and Metro — all of which render via React/Next.js.
// The raw fetch returns a pre-render shell with no product data, so the price
// regex found zero matches on every attempt.
//
// Replacement: term-variant retry. Instead of failing after one empty Flipp
// response, the service now retries with 3 progressively simplified query terms:
//   Attempt 1: full normalised name (e.g. "oatly oat milk 1l")
//   Attempt 2: first token only (e.g. "oatly")
//   Attempt 3: name with stop words stripped (e.g. "oat milk 1l")
// If all 3 attempts return empty, markFlippUnavailable(itemID:) is called.
//
// HTML scraper removed — JS-rendered store sites return pre-render shells.
// Post-MVP: consider headless browser (e.g. Playwright) or store-provided API.
//
// ALSO IN THIS FILE (P1-1 integration):
// processFlippResults() now calls NameNormaliser.nameMatchScore() before writing
// to price_history. Results below Constants.flippMatchThreshold are skipped.

import Foundation

// MARK: - FlippItem
// Represents one search result from the Flipp endpoint.
// Custom decoder handles two known JSON shapes and the String/Double price issue.
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

    // Custom decoder because:
    // 1. The Flipp API sometimes returns current_price as a String, not a Double.
    // 2. Any field may be missing — we want 0.0 rather than a crash.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        name      = try c.decode(String.self, forKey: .name)
        validTo   = try? c.decode(String.self, forKey: .validTo)
        storeCode = try? c.decode(String.self, forKey: .storeCode)

        if let d = try? c.decode(Double.self, forKey: .currentPrice) {
            currentPrice = d
        } else if let s = try? c.decode(String.self, forKey: .currentPrice), let d = Double(s) {
            currentPrice = d
        } else {
            currentPrice = 0.0
        }
    }
}

// Flipp sometimes wraps the results array in an object: { "items": [...] }
private struct FlippResponseWrapper: Decodable {
    let items: [FlippItem]
}

// MARK: - FlippService
final class FlippService {

    static let shared = FlippService()
    private init() {}

    private let baseURL = "https://backflipp.wishabi.com/flipp/items/search"
    private let session = URLSession.shared

    // MARK: - fetchPrices(for:)
    // Public entry point. Accepts an array of UserItems and fetches Flipp
    // prices for each one. Called by BackgroundSyncManager on daily refresh
    // and by manual pull-to-refresh.
    func fetchPrices(for items: [UserItem]) async {
        let postalCode = DatabaseManager.shared.getSetting(key: "user_postal_code") ?? ""
        for item in items {
            await fetchPricesForItem(item, postalCode: postalCode)
        }
    }

    // MARK: - fetchPricesForItem(_:postalCode:)
    // Fetches Flipp results for a single item using the term-variant retry strategy.
    // Three attempts are made with progressively simplified query terms.
    // If all attempts return empty results, the item is marked as unavailable.
    private func fetchPricesForItem(_ item: UserItem, postalCode: String) async {
        let normalisedName = NameNormaliser.normalise(item.nameDisplay)

        // Variant 1: full normalised name
        let variant1 = normalisedName

        // Variant 2: first token only — broadens the search for single-brand items
        let tokens = NameNormaliser.tokenise(variant1)
        let variant2 = tokens.first ?? variant1

        // Variant 3: stop words stripped — removes "bag of", "pack of", etc.
        let contentTokens = NameNormaliser.tokeniseWithoutStopWords(variant1)
        let variant3 = contentTokens.joined(separator: " ")

        let variants = [variant1, variant2, variant3].filter { !$0.isEmpty }

        for (index, queryTerm) in variants.enumerated() {
            let results = await queryFlipp(term: queryTerm, postalCode: postalCode)

            if !results.isEmpty {
                processFlippResults(results, for: item)
                return
            }

            print("[FlippService] Attempt \(index + 1) returned empty for '\(item.nameDisplay)' (query: '\(queryTerm)')")
        }

        // All 3 variants returned empty.
        markFlippUnavailable(itemID: item.itemID)
        print("[FlippService] All variants exhausted for '\(item.nameDisplay)' — marked unavailable")
    }

    // MARK: - queryFlipp(term:postalCode:)
    // Makes a single HTTP GET request to the Flipp endpoint and returns decoded results.
    // Returns an empty array on any failure (network, parse, or non-200 response).
    private func queryFlipp(term: String, postalCode: String) async -> [FlippItem] {
        var components = URLComponents(string: baseURL)!
        var queryItems: [URLQueryItem] = [
            URLQueryItem(name: "locale", value: "en-CA"),
            URLQueryItem(name: "q", value: term)
        ]
        if !postalCode.isEmpty {
            queryItems.append(URLQueryItem(name: "postal_code", value: postalCode))
        }
        components.queryItems = queryItems

        guard let url = components.url else {
            print("[FlippService] Failed to build URL for term: \(term)")
            return []
        }

        do {
            let (data, response) = try await session.data(from: url)
            guard let http = response as? HTTPURLResponse, http.statusCode == 200 else {
                print("[FlippService] Non-200 response for term: \(term)")
                return []
            }
            return decodeFlippResponse(data)
        } catch {
            print("[FlippService] Network error for term '\(term)': \(error)")
            return []
        }
    }

    // MARK: - decodeFlippResponse(_:)
    // Tries two JSON shapes: root array first, then wrapped object.
    // The Flipp endpoint has returned both shapes in the wild.
    private func decodeFlippResponse(_ data: Data) -> [FlippItem] {
        if let items = try? JSONDecoder().decode([FlippItem].self, from: data) {
            return items
        }
        if let wrapper = try? JSONDecoder().decode(FlippResponseWrapper.self, from: data) {
            return wrapper.items
        }
        print("[FlippService] Unrecognised JSON shape — could not decode response")
        return []
    }

    // MARK: - processFlippResults(_:for:)
    // Takes decoded Flipp results and writes them to the correct tables.
    //
    // P1-1 INTEGRATION: Before writing to price_history, checks name match score.
    // If the Flipp result's name scores below Constants.flippMatchThreshold against
    // the item's normalised name, the result is skipped.
    //
    // Routing logic:
    //   - If valid_to is present and >= today → write to flyer_sales
    //   - Otherwise → write to price_history as a regular price observation
    private func processFlippResults(_ results: [FlippItem], for item: UserItem) {
        let db = DatabaseManager.shared
        let today = Date()
        let dateFormatter = ISO8601DateFormatter()
        let itemNormalisedName = NameNormaliser.normalise(item.nameDisplay)

        for flippItem in results {
            // Guard: skip Flipp results with 0.0 prices.
            // TODO P2-5: Move this guard into a dedicated filter function.
            guard flippItem.currentPrice > 0.01 else {
                print("[FlippService] Skipping zero-price result: \(flippItem.name)")
                continue
            }

            // P1-1: Name match confidence check.
            let matchScore = NameNormaliser.nameMatchScore(itemNormalisedName, flippItem.name)
            guard matchScore >= Constants.flippMatchThreshold else {
                print("[FlippService] Skipping '\(flippItem.name)' — match score \(String(format: "%.2f", matchScore)) below threshold \(Constants.flippMatchThreshold)")
                continue
            }

            guard let code = flippItem.storeCode else { continue }
            let storeID = db.upsertStore(name: code)

            if let validToString = flippItem.validTo,
               let validToDate = dateFormatter.date(from: validToString),
               validToDate >= today {
                db.insertFlyerSale(
                    itemID: item.itemID,
                    storeID: storeID,
                    salePrice: flippItem.currentPrice,
                    startDate: today,
                    endDate: validToDate,
                    source: "flipp"
                )
            } else {
                db.insertPriceHistory(
                    itemID: item.itemID,
                    storeID: storeID,
                    price: flippItem.currentPrice,
                    source: "flipp"
                )
            }
        }

        db.setSetting(key: "last_price_refresh", value: dateFormatter.string(from: today))
    }

    // MARK: - markFlippUnavailable(itemID:)
    // Writes a user_settings flag when all Flipp retry variants return empty.
    // ItemDetailView reads this key and shows a "Price data unavailable" banner.
    func markFlippUnavailable(itemID: Int64) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        DatabaseManager.shared.setSetting(
            key: "flipp_no_data_\(itemID)",
            value: timestamp
        )
    }
}
