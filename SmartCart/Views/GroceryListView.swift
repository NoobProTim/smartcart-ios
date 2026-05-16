// GroceryListView.swift — SmartCart/Views/GroceryListView.swift
//
// My List tab. Shows items added from Deals or Home.
//
// GAP-3 fix: list rows now show store name and an "On sale" pill badge
//   when an active Flipp deal exists for that item.
// GAP-3 fix: "+ Add item" button added at the bottom of the list.
// GAP-4 fix: empty state now has a "Browse Deals" button that switches
//   to the Deals tab (tab index 1) via the selectedTab environment value.
//
// Sprint 3: Pre-shop savings banner shown when any item has an active
//   deal cheaper than the user's historical average for that item.

import SwiftUI

struct GroceryListView: View {
    @EnvironmentObject private var vm: GroceryListViewModel
    // Lets the empty-state CTA switch to the Deals tab (index 1).
    @Environment(\.selectedTab) private var selectedTab

    // Computed once on render: total potential savings across all list items
    // that have an active deal below their historical average price.
    // Returns nil if no savings exist — banner is hidden in that case.
    private var potentialSavings: Double? {
        let total = vm.items.compactMap { item -> Double? in
            guard let sale = DatabaseManager.shared.fetchActiveSales(for: item.itemID).first else {
                return nil
            }
            let avg = DatabaseManager.shared.averagePrice(for: item.itemID)
            guard let avg, avg > sale.salePrice else { return nil }
            return avg - sale.salePrice
        }.reduce(0, +)
        return total > 0 ? total : nil
    }

    var body: some View {
        Group {
            if vm.items.isEmpty {
                emptyState
            } else {
                listContent
            }
        }
        .navigationTitle("My List")
        .onAppear { vm.load() }
    }

    // MARK: - emptyState
    // GAP-4 fix: empty state now matches wireframe — icon, message, and
    // a "Browse Deals" button that switches to the Deals tab.
    private var emptyState: some View {
        VStack(spacing: 20) {
            Spacer()

            Image(systemName: "cart")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            VStack(spacing: 6) {
                Text("Your list is empty")
                    .font(.headline)
                Text("Add items from the Deals tab or tap + on any tracked item.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            // GAP-4: "Browse Deals" CTA switches to the Deals tab.
            Button(action: { selectedTab.wrappedValue = 1 }) {
                Label("Browse Deals", systemImage: "tag")
                    .font(.system(size: 15, weight: .semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 24)
                    .padding(.vertical, 12)
                    .background(Color.accentColor)
                    .clipShape(Capsule())
            }

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - listContent
    // Pre-shop savings banner + list of items + + Add item footer.
    private var listContent: some View {
        VStack(spacing: 0) {
            // Pre-shop savings banner — shown when at least one list item
            // is currently on sale below the user's average price.
            if let savings = potentialSavings {
                PreShopSavingsBanner(potentialSavings: savings)
            }

            List {
                ForEach(vm.items) { item in
                    // Read the best active sale for this item (if any)
                    // so we can display store name + "On sale" pill.
                    let activeSale = DatabaseManager.shared.fetchActiveSales(for: item.itemID).first
                    GroceryListRow(item: item, activeSale: activeSale) {
                        vm.markPurchased(item)
                    }
                }
                .onDelete { vm.delete(at: $0) }

                // GAP-3: "+ Add item" row at the bottom of the list.
                // Switches to the Deals tab where users discover and add items.
                Section {
                    Button(action: { selectedTab.wrappedValue = 1 }) {
                        Label("Add item", systemImage: "plus.circle")
                            .font(.system(size: 15))
                            .foregroundStyle(Color.accentColor)
                    }
                    .buttonStyle(.plain)
                }
            }
            .listStyle(.insetGrouped)
        }
    }
}

// MARK: - PreShopSavingsBanner
// Green banner shown above the list when the user can save money vs their
// average prices by buying on sale today. Motivates action before shopping.
private struct PreShopSavingsBanner: View {
    let potentialSavings: Double

    var body: some View {
        HStack(spacing: 10) {
            Image(systemName: "checkmark.seal.fill")
                .font(.system(size: 20))
                .foregroundStyle(.green)

            VStack(alignment: .leading, spacing: 1) {
                Text("You could save \(potentialSavings, format: .currency(code: "CAD")) today")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(.primary)
                Text("Based on your average prices vs active deals")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            ZStack {
                Color(.secondarySystemGroupedBackground)
                LinearGradient(
                    colors: [Color.green.opacity(0.10), Color.clear],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            }
        )
    }
}

// MARK: - GroceryListRow
// One tappable row.
// GAP-3 fix: now shows store name and an "On sale" pill when an active
// Flipp deal exists for the item. Matches wireframe My List layout.
private struct GroceryListRow: View {
    let item:       GroceryListItem
    let activeSale: FlyerSale?      // nil if no active deal for this item
    let onToggle:   () -> Void

    @State private var checked = false

    // The store name to show under the item name.
    // Prefers the sale's store name; falls back to the item's own store if set.
    private var storeName: String? {
        if let sale = activeSale {
            return DatabaseManager.shared.fetchStoreName(for: sale.storeID)
        }
        return nil
    }

    var body: some View {
        HStack(spacing: 12) {
            // Tap the circle to mark purchased. 35ms delay lets the animation
            // complete before the row disappears from the list.
            Button {
                checked = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { onToggle() }
            } label: {
                Image(systemName: checked ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 24))
                    .foregroundStyle(checked ? Color.green : Color.secondary)
                    .animation(.spring(duration: 0.2, bounce: 0.3), value: checked)
            }
            .buttonStyle(.plain)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(item.nameDisplay)
                        .font(.system(size: 15, weight: .medium))
                        .strikethrough(checked)
                        .foregroundStyle(checked ? .secondary : .primary)

                    // GAP-3: "On sale" green pill — only shown when an active deal exists.
                    if activeSale != nil && !checked {
                        Text("On sale")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.green.opacity(0.12))
                            .clipShape(Capsule())
                    }
                }

                // GAP-3: Show "~$X.XX · Store Name" when a sale exists,
                // otherwise fall back to the item's plain expected price.
                if let sale = activeSale, let store = storeName {
                    Text("~\(sale.salePrice, format: .currency(code: "CAD")) · \(store)")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                } else if let price = item.expectedPrice {
                    Text(price, format: .currency(code: "CAD"))
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .monospacedDigit()
                }
            }
        }
        .padding(.vertical, 6)
        .sensoryFeedback(.success, trigger: checked)
    }
}
