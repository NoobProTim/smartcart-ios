// GroceryListViewModel.swift — SmartCart/ViewModels/GroceryListViewModel.swift

import Combine
import SwiftUI

@MainActor
final class GroceryListViewModel: ObservableObject {
    @Published var items: [GroceryListItem] = []

    func load() {
        items = DatabaseManager.shared.fetchGroceryList()
    }

    func markPurchased(_ item: GroceryListItem) {
        DatabaseManager.shared.markGroceryListItemPurchased(itemID: item.itemID)
        load()
    }

    func delete(at offsets: IndexSet) {
        offsets.forEach { DatabaseManager.shared.removeFromGroceryList(id: items[$0].id) }
        items.remove(atOffsets: offsets)
    }
}
