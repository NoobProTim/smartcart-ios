// DatabaseManager+GroceryList.swift — SmartCart/Database/DatabaseManager+GroceryList.swift

import Foundation
import SQLite

struct ActiveSaleRow: Identifiable {
    let id:           Int64
    let itemName:     String
    let storeName:    String
    let salePrice:    Double
    let regularPrice: Double?
    let validTo:      Date?
}

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

    func fetchAllActiveSales() -> [ActiveSaleRow] {
        let today = Date()
        let query = flyerSalesTable
            .join(itemsTable, on: flyerItemID == itemID)
            .filter(flyerStartDate <= today)
        let rows = (try? db.prepare(query)) ?? AnySequence([])
        return rows.compactMap { row in
            let end = row[flyerEndDate]
            if let end = end, end < today { return nil }
            let storeRow     = try? db.pluck(storesTable.filter(storeID == row[flyerStoreID]))
            let storeNameVal = storeRow?[storeName] ?? "Unknown"
            return ActiveSaleRow(
                id:           row[flyerID],
                itemName:     row[itemNameDisplay],
                storeName:    storeNameVal,
                salePrice:    row[flyerSalePrice],
                regularPrice: row[flyerRegularPrice],
                validTo:      row[flyerEndDate]
            )
        }
    }
}
