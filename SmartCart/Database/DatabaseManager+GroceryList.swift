// DatabaseManager+GroceryList.swift — SmartCart/Database/DatabaseManager+GroceryList.swift

import Foundation
import SQLite

struct GroceryListItem: Identifiable {
    let id:            Int64
    let itemID:        Int64
    let nameDisplay:   String
    let expectedPrice: Double?
    let addedAt:       Date
    let isPurchased:   Bool
}

extension DatabaseManager {

    func addToGroceryList(itemID: Int64, expectedPrice: Double?) {
        let existing = groceryListTable.filter(
            groceryListItemID == itemID && groceryListPurchased == 0
        )
        guard (try? db.scalar(existing.count)) == 0 else { return }
        _ = try? db.run(groceryListTable.insert(
            groceryListItemID    <- itemID,
            groceryListPrice     <- expectedPrice,
            groceryListAddedAt   <- Date(),
            groceryListPurchased <- 0
        ))
    }

    func fetchGroceryList() -> [GroceryListItem] {
        let query = groceryListTable
            .join(itemsTable, on: groceryListItemID == itemID)
            .filter(groceryListPurchased == 0)
            .order(groceryListAddedAt.asc)
        let rows = (try? db.prepare(query)) ?? AnySequence([])
        return rows.map { row in
            GroceryListItem(
                id:            row[groceryListID],
                itemID:        row[groceryListItemID],
                nameDisplay:   row[itemNameDisplay],
                expectedPrice: row[groceryListPrice],
                addedAt:       row[groceryListAddedAt],
                isPurchased:   row[groceryListPurchased] == 1
            )
        }
    }

    func markGroceryListItemPurchased(itemID: Int64) {
        _ = try? db.run(
            groceryListTable
                .filter(groceryListItemID == itemID && groceryListPurchased == 0)
                .update(groceryListPurchased <- 1)
        )
    }

    func removeFromGroceryList(id: Int64) {
        _ = try? db.run(groceryListTable.filter(groceryListID == id).delete())
    }
}
