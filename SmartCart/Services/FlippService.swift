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
// Removed ScraperFallback entirely. HTML scraper fetched raw page HTML from
// Loblaws, No Frills, and Metro — all React/Next.js rendered. Pre-render
// shell returned zero product data.
//
// Replacement: term-variant retry.
//   Attempt 1: full normalised name (e.g. "oatly oat milk 1l")
//   Attempt 2: first token only (e.g. "oatly")
//   Attempt 3: name with stop words stripped (e.g. "oat milk 1l")
// If all 3 attempts return empty, markFlippUnavailable(itemID:) is called.
//
// ALSO IN THIS FILE (P1-1 integration):
// processFlippResults() now calls NameNormaliser.nameMatchScore() before
// writing to price_history. Results below Constants.flippMatchThreshold are skipped.

import Foundation

// MARK: - FlippItem
struct FlippItem: Decodable {
    let name:          String
    let currentPrice:  Double
    let originalPrice: Double?
    let validTo:       String?
    let storeCode:     String?
    let saleStory:     String?

    enum CodingKeys: String, CodingKey {
        case name
        case currentPrice  = "current_price"
        case originalPrice = "original_price"
        case validTo       = "valid_to"
        case storeCode     = "merchant_name"
        case saleStory     = "sale_story"
    }

    init(from decoder: Decoder) throws {
        let c     = try decoder.container(keyedBy: CodingKeys.self)
        name      = try c.decode(String.self, forKey: .name)
        validTo   = try? c.decode(String.self, forKey: .validTo)
        storeCode = try? c.decode(String.self, forKey: .storeCode)
        saleStory = try? c.decode(String.self, forKey: .saleStory)
        if let d = try? c.decode(Double.self, forKey: .currentPrice) {
            currentPrice = d
        } else if let s = try? c.decode(String.self, forKey: .currentPrice), let d = Double(s) {
            currentPrice = d
        } else {
            currentPrice = 0.0
        }
        if let d = try? c.decode(Double.self, forKey: .originalPrice), d > 0 {
            originalPrice = d
        } else {
            originalPrice = nil
        }
    }
}

private struct FlippResponseWrapper: Decodable {
    let items: [FlippItem]
}

// MARK: - FlippService
final class FlippService {

    static let shared = FlippService()
    private init() {}

    private let baseURL = "https://backflipp.wishabi.com/flipp/items/search"
    private let session = URLSession.shared

    // MARK: - fetchPopularDeals
    func fetchPopularDeals(postalCode: String) async -> [FlyerDeal] {
        let terms = [
            "milk", "chicken", "beef", "eggs", "bread",
            "butter", "yogurt", "apple", "tomato", "rice",
            "flour", "pork", "cheese", "orange juice", "cereal"
        ]
        var allDeals: [FlyerDeal] = []
        await withTaskGroup(of: [FlyerDeal].self) { group in
            for term in terms {
                group.addTask {
                    let items = await self.queryFlipp(term: term, postalCode: postalCode)
                    return items.compactMap { FlyerDeal(flippItem: $0) }
                }
            }
            for await batch in group {
                allDeals.append(contentsOf: batch)
            }
        }
        var seen = Set<String>()
        let deduped = allDeals.filter { deal in
            let key = "\(deal.name.lowercased())|\(deal.storeName.lowercased())"
            return seen.insert(key).inserted
        }
        return deduped.sorted { ($0.discountPercent ?? 0) > ($1.discountPercent ?? 0) }
    }

    // MARK: - fetchPrices(for:)
    func fetchPrices(for items: [UserItem]) async {
        let postalCode = DatabaseManager.shared.getSetting(key: "user_postal_code") ?? ""
        for item in items {
            await fetchPricesForItem(item, postalCode: postalCode)
        }
    }

    // MARK: - fetchPricesForItem(_:postalCode:)
    private func fetchPricesForItem(_ item: UserItem, postalCode: String) async {
        let normalisedName = item.nameDisplay.lowercased()
        let variant1 = NameNormaliser.normalise(normalisedName)
        let tokens = NameNormaliser.tokenise(variant1)
        let variant2 = tokens.first ?? variant1
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

        markFlippUnavailable(itemID: item.itemID)
        print("[FlippService] All variants exhausted for '\(item.nameDisplay)' — marked unavailable")
    }

    // MARK: - queryFlipp(term:postalCode:)
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
    private func decodeFlippResponse(_ data: Data) -> [FlippItem] {
        if let items = try? JSONDecoder().decode([FlippItem].self, from: data) { return items }
        if let wrapper = try? JSONDecoder().decode(FlippResponseWrapper.self, from: data) { return wrapper.items }
        print("[FlippService] Unrecognised JSON shape")
        return []
    }

    // MARK: - processFlippResults(_:for:)
    // P1-1: name match score check before writing to price_history.
    private func processFlippResults(_ results: [FlippItem], for item: UserItem) {
        let db = DatabaseManager.shared
        let today = Date()
        let dateFormatter = ISO8601DateFormatter()
        let itemNormalisedName = NameNormaliser.normalise(item.nameDisplay)

        for flippItem in results {
            guard flippItem.currentPrice > 0.01 else {
                print("[FlippService] Skipping zero-price result: \(flippItem.name)")
                continue
            }

            let matchScore = NameNormaliser.nameMatchScore(itemNormalisedName, flippItem.name)
            guard matchScore >= Constants.flippMatchThreshold else {
                print("[FlippService] Skipping '\(flippItem.name)' — match score \(String(format: "%.2f", matchScore)) below threshold \(Constants.flippMatchThreshold)")
                continue
            }

            let storeID: Int64
            if let code = flippItem.storeCode {
                storeID = db.upsertStore(name: code)
            } else {
                continue
            }

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
    func markFlippUnavailable(itemID: Int64) {
        let timestamp = ISO8601DateFormatter().string(from: Date())
        DatabaseManager.shared.setSetting(key: "flipp_no_data_\(itemID)", value: timestamp)
    }
}

// MARK: - FlyerDeal initialiser from FlippItem
extension FlyerDeal {
    nonisolated init?(flippItem: FlippItem) {
        guard flippItem.currentPrice > 0.01,
              let store = flippItem.storeCode, !store.isEmpty else { return nil }

        // ISO8601DateFormatter needs .withFractionalSeconds omitted but does handle +00:00 offsets.
        let fmt = ISO8601DateFormatter()
        fmt.formatOptions = [.withInternetDateTime]

        // Prefer explicit original_price; fall back to parsing "SAVE 24%" / "34% OFF" from sale_story.
        var regPrice = flippItem.originalPrice
        if regPrice == nil, let story = flippItem.saleStory,
           let pct = Self.discountPercent(from: story), pct > 0, pct < 100 {
            regPrice = (flippItem.currentPrice / (1.0 - Double(pct) / 100.0)).rounded(toPlaces: 2)
        }

        self.id           = UUID()
        self.name         = flippItem.name
        self.storeName    = store
        self.salePrice    = flippItem.currentPrice
        self.regularPrice = regPrice
        self.validTo      = flippItem.validTo.flatMap { fmt.date(from: $0) }
        self.category     = DealCategory.classify(from: flippItem.name)
    }

    // Parses "SAVE 24%", "34% OFF", "SAVE UP TO 20%" → percentage integer.
    nonisolated private static func discountPercent(from story: String) -> Int? {
        let pattern = #"(\d+)\s*%"#
        guard let range = story.range(of: pattern, options: .regularExpression),
              let numRange = story[range].range(of: #"\d+"#, options: .regularExpression) else { return nil }
        return Int(story[numRange])
    }
}

private extension Double {
    nonisolated func rounded(toPlaces places: Int) -> Double {
        let factor = pow(10.0, Double(places))
        return (self * factor).rounded() / factor
    }
}
