// GroceryListView.swift — SmartCart/Views/GroceryListView.swift

import SwiftUI

struct GroceryListView: View {
    @EnvironmentObject private var vm: GroceryListViewModel

    var body: some View {
        Group {
            if vm.items.isEmpty {
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
        .navigationTitle("My List")
        .onAppear { vm.load() }
    }
}

// MARK: - GroceryListRow
private struct GroceryListRow: View {
    let item:     GroceryListItem
    let onToggle: () -> Void

    @State private var checked = false

    var body: some View {
        HStack(spacing: 12) {
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
