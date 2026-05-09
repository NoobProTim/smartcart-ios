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
    let item: UserItem

    init(item: UserItem) {
        self.item = item
    }

    func load() {
        isLoading = true
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let sales   = self.db.fetchActiveSales(for: self.item.itemID)
            let avg     = self.db.rollingAverage90(for: self.item.itemID)
            let history = self.db.fetchPriceHistory(for: self.item.itemID)
            await MainActor.run {
                self.pricePoints    = history
                self.activeSales    = sales
                self.rollingAvg90  = avg
                self.isLoading     = false
            }
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
