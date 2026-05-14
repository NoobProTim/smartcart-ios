// PriceHistoryViewModel.swift — SmartCart/ViewModels/PriceHistoryViewModel.swift
//
// Drives the price history detail screen for a single item.

import Foundation
import Combine

@MainActor
final class PriceHistoryViewModel: ObservableObject {

    @Published var pricePoints: [PricePoint] = []
    @Published var activeSales: [FlyerSale] = []
    @Published var rollingAvg90: Double? = nil
    @Published var isLoading: Bool = false

    private let db = DatabaseManager.shared

    // points: alias used by ItemDetailView (range-filtered subset of pricePoints)
    var points: [PricePoint] { pricePoints }

    init() {}

    init(item: UserItem) {
        load(itemID: item.itemID, range: .thirtyDays)
    }

    func load() {}

    func load(itemID: Int64, range: ChartRange = .thirtyDays) {
        isLoading = true
        Task {
            let sales   = db.fetchActiveSales(for: itemID)
            let avg     = db.rollingAverage90(for: itemID)
            let history = db.fetchPriceHistory(for: itemID)
            let filtered: [PricePoint]
            if let cutoff = range.cutoffDate {
                filtered = history.filter { $0.observedAt >= cutoff }
            } else {
                filtered = history
            }

            pricePoints   = filtered
            activeSales   = sales
            rollingAvg90  = avg
            isLoading     = false
        }
    }

    // Lowest price recorded in price_history within the last 90 days.
    var historicalLow: Double? {
        pricePoints
            .filter { $0.observedAt >= Calendar.current.date(byAdding: .day, value: -90, to: Date())! }
            .map { $0.price }
            .min()
    }
}
