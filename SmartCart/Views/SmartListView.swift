// SmartListView.swift — SmartCart/Views/SmartListView.swift
//
// Main screen: shows the user's active tracked items.
// Items due for restock appear in a "Restock Soon" section at the top.

import SwiftUI

struct SmartListView: View {

    @StateObject private var vm = SmartListViewModel()
    @State private var showAddItem = false
    @State private var newItemName = ""
    @State private var selectedItem: UserItem? = nil

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Loading…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.userItems.isEmpty {
                    emptyState
                } else {
                    itemList
                }
            }
            .navigationTitle("Smart List")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showAddItem = true
                    } label: {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showAddItem) {
                addItemSheet
            }
            .sheet(item: $selectedItem) { item in
                PriceHistoryView(item: item)
            }
            .onAppear { vm.loadItems() }
        }
    }

    // MARK: - Subviews

    private var itemList: some View {
        List {
            if !vm.itemsDueForRestock.isEmpty {
                Section("Restock Soon") {
                    ForEach(vm.itemsDueForRestock) { item in
                        SmartListRow(item: item) {
                            selectedItem = item
                        } onMarkPurchased: {
                            vm.markAsPurchased(item: item, price: item.lastPurchasedPrice)
                        }
                    }
                }
            }
            Section("All Items") {
                ForEach(vm.userItems) { item in
                    SmartListRow(item: item) {
                        selectedItem = item
                    } onMarkPurchased: {
                        vm.markAsPurchased(item: item, price: item.lastPurchasedPrice)
                    }
                }
            }
        }
        .refreshable { vm.loadItems() }
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "cart.badge.plus")
                .font(.system(size: 56))
                .foregroundStyle(.secondary)
            Text("Your Smart List is empty")
                .font(.headline)
            Text("Tap + to add your first item, or scan a receipt.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var addItemSheet: some View {
        NavigationStack {
            Form {
                Section("Item Name") {
                    TextField("e.g. Whole Milk", text: $newItemName)
                        .autocorrectionDisabled()
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { showAddItem = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") {
                        let name = newItemName.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty {
                            vm.addItem(nameDisplay: name)
                        }
                        newItemName = ""
                        showAddItem = false
                    }
                    .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }
}

// MARK: - Row

struct SmartListRow: View {
    let item: UserItem
    let onTap: () -> Void
    let onMarkPurchased: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    Text(item.nameDisplay)
                        .font(.body)
                    if item.hasActiveAlert {
                        Image(systemName: "bell.badge.fill")
                            .foregroundStyle(.orange)
                            .font(.caption)
                    }
                }
                if let days = item.daysUntilRestock {
                    Text(restockLabel(days: days))
                        .font(.caption)
                        .foregroundStyle(days <= 0 ? .red : .secondary)
                } else if let price = item.lastPurchasedPrice {
                    Text("Last paid $\(String(format: "%.2f", price))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer()
            Button {
                onMarkPurchased()
            } label: {
                Image(systemName: "checkmark.circle")
                    .font(.title2)
                    .foregroundStyle(.green)
            }
            .buttonStyle(.plain)
        }
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
    }

    private func restockLabel(days: Int) -> String {
        if days < 0  { return "Overdue by \(abs(days))d" }
        if days == 0 { return "Restock today" }
        return "Restock in \(days)d"
    }
}
