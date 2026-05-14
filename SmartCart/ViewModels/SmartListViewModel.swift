// SmartListViewModel.swift — SmartCart/ViewModels/SmartListViewModel.swift
//
// Drives the main Smart List screen.
// All DB reads happen on a background queue; @Published updates are
// dispatched back to the main thread.

import Foundation
import Combine

@MainActor
final class SmartListViewModel: ObservableObject {

    @Published var userItems: [UserItem] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String? = nil

    private let db = DatabaseManager.shared

    // Call on view .onAppear and after any mutation.
    func loadItems() {
        isLoading = true
        errorMessage = nil
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let items = self.db.fetchUserItems()
            self.userItems = items
            self.isLoading = false
        }
    }

    // Mark an item as purchased at an optional price.
    // Atomic write guaranteed by DatabaseManager.markPurchased() (Fix P0-1).
    func markAsPurchased(item: UserItem, price: Double?) {
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            self.db.markPurchased(itemID: item.itemID, priceAtPurchase: price)
            self.loadItems()
        }
    }

    // Adds a new item to the user's list.
    func addItem(nameDisplay: String) {
        let nameNorm = nameDisplay.lowercased()
            .trimmingCharacters(in: .whitespacesAndNewlines)
        Task(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let iid = self.db.upsertItem(nameNormalised: nameNorm, nameDisplay: nameDisplay)
            self.db.upsertUserItem(itemIDValue: iid)
            self.loadItems()
        }
    }

    // Returns items due for restock, sorted by days overdue (most overdue first).
    var itemsDueForRestock: [UserItem] {
        userItems
            .filter { $0.isInRestockWindow }
            .sorted {
                let a = $0.daysUntilRestock ?? 0
                let b = $1.daysUntilRestock ?? 0
                return a < b
            }
    }
}
