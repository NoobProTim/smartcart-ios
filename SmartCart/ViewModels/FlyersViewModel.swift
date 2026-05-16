// FlyersViewModel.swift — SmartCart/ViewModels/FlyersViewModel.swift

import Combine
import SwiftUI

@MainActor
final class FlyersViewModel: ObservableObject {
    @Published var deals:             [FlyerDeal]   = []
    @Published var isLoading:          Bool           = false
    @Published var searchText:         String         = ""
    @Published var selectedCategory:   DealCategory   = .all
    @Published var addedIDs:           Set<UUID>      = []

    var filteredDeals: [FlyerDeal] {
        var result = deals
        if selectedCategory != .all {
            result = result.filter { $0.category == selectedCategory }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.storeName.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var userStores: [String] {
        DatabaseManager.shared.fetchSelectedStoreNames()
    }

    var bestDeals: [FlyerDeal] {
        Array(
            deals
                .filter { $0.discountPercent != nil }
                .sorted { ($0.discountPercent ?? 0) > ($1.discountPercent ?? 0) }
                .prefix(10)
        )
    }

    func load() async {
        guard deals.isEmpty else { return }
        isLoading = true
        let postalCode = DatabaseManager.shared.getSetting(key: "user_postal_code") ?? "M5V3A8"
        deals = await FlippService.shared.fetchPopularDeals(postalCode: postalCode)
        isLoading = false
    }

    func addToCart(_ deal: FlyerDeal) {
        let db   = DatabaseManager.shared
        let norm = NameNormaliser.normalise(deal.name)
        let iid  = db.upsertItem(nameNormalised: norm, nameDisplay: deal.name)
        db.addToGroceryList(itemID: iid, expectedPrice: deal.salePrice)
        addedIDs.insert(deal.id)
    }
}
