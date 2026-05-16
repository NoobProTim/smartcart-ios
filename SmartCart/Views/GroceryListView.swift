// GroceryListView.swift — SmartCart/Views/GroceryListView.swift
//
// My List tab. Shows items added from Flyers or Home.
// Sprint 3: adds a pre-shop savings banner at the top when any list item
// has an active Flipp deal cheaper than the user's average price for that item.
// The banner total is the sum of (avgPrice - salePrice) for all matching items.

import SwiftUI

struct GroceryListView: View {
    @EnvironmentObject private var vm: GroceryListViewModel

    // Computed once on render: total potential savings across all list items
    // that have an active deal below their historical average price.
    // Returns nil if no savings exist — banner is hidden in that case.
    private var potentialSavings: Double? {
        let total = vm.items.compactMap { item -> Double? in
            // Get the best active sale for this item
            guard let sale = DatabaseManager.shared.fetchActiveSales(for: item.itemID).first else {
                return nil
            }
            // Get the user's average price for this item (nil if no history)
            let avg = DatabaseManager.shared.averagePrice(for: item.itemID)
            guard let avg, avg > sale.salePrice else { return nil }
            // Saving = difference between what they usually pay vs today's sale price
            return avg - sale.salePrice
        }.reduce(0, +)
        return total > 0 ? total : nil
    }

    var body: some View {
        Group {
            if vm.items.isEmpty {
                // Empty state — guides new users to add items from Flyers
                VStack(spacing: 14) {
                    Image(systemName: "cart")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("Your list is empty")
                        .font(.headline)
                    Text("Add items from Flyers to get started.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    // Pre-shop savings banner — shown when at least one list item
                    // is currently on sale below the user's average price.
                    if let savings = potentialSavings {
                        PreShopSavingsBanner(potentialSavings: savings)
                    }

                    // Grocery list — check off items as you shop
                    List {
                        ForEach(vm.items) { item in
                            GroceryListRow(item: item) {
                                vm.markPurchased(item)
                            }
                        }
                        .onDelete { vm.delete(at: $0) }
                    }
                    .listStyle(.insetGrouped)
                }
            }
        }
        .navigationTitle("My List")
        .onAppear { vm.load() }
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
// One tappable row. Checkbox animates to checked then calls onToggle
// which marks the item purchased and removes it from the list.
private struct GroceryListRow: View {
    let item:     GroceryListItem
    let onToggle: () -> Void

    @State private var checked = false

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
                Text(item.nameDisplay)
                    .font(.system(size: 15, weight: .medium))
                    .strikethrough(checked)
                    .foregroundStyle(checked ? .secondary : .primary)
                if let price = item.expectedPrice {
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
