// ReceiptReviewView.swift — SmartCart/Views/ReceiptReviewView.swift
//
// Shows scanned line items for user review before importing to database.
// User can toggle individual items on/off before confirming.
//
// P0-C: If the store cannot be resolved, the Import button is blocked
// and an inline picker lets the user select the correct store before proceeding.
// storeID = -1 is used as a sentinel for "Other / Unknown" and is excluded
// from all Flipp and AlertEngine queries via guard storeID > 0.

import SwiftUI

struct ReceiptReviewView: View {

    let result: ReceiptScanResult
    let onDismiss: () -> Void

    @State private var confirmed: Set<Int> = []
    @State private var isImporting = false
    // P0-C: nil = unresolved, -1 = "Other", >0 = valid store
    @State private var resolvedStoreID: Int64?
    @State private var showUnknownStorePicker = false
    @State private var allStores: [Store] = []
    @Environment(\.dismiss) private var dismiss

    init(result: ReceiptScanResult, onDismiss: @escaping () -> Void) {
        self.result = result
        self.onDismiss = onDismiss
        _confirmed = State(initialValue: Set(result.items.indices))
    }

    var body: some View {
        NavigationStack {
            List {
                // Store section — shows resolved name or picker prompt.
                Section("Store") {
                    if showUnknownStorePicker {
                        storePickerSection
                    } else {
                        Text(result.storeNameRaw ?? "Unknown store")
                            .foregroundStyle(
                                resolvedStoreID == nil ? Color.orange : Color.secondary
                            )
                        if resolvedStoreID == nil {
                            Text("Store not recognised — please select below to enable import.")
                                .font(.caption)
                                .foregroundStyle(.orange)
                        }
                    }
                }

                Section("Items Found (\(result.items.count))") {
                    ForEach(Array(result.items.enumerated()), id: \.offset) { index, item in
                        HStack {
                            Image(systemName: confirmed.contains(index)
                                  ? "checkmark.circle.fill" : "circle")
                                .foregroundStyle(confirmed.contains(index) ? .green : .secondary)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.nameRaw)
                                    .font(.body)
                                Text(item.nameNormalised)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text("$\(String(format: "%.2f", item.price))")
                                .font(.body.monospacedDigit())
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            if confirmed.contains(index) {
                                confirmed.remove(index)
                            } else {
                                confirmed.insert(index)
                            }
                        }
                    }
                }
            }
            .navigationTitle("Review Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                        onDismiss()
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(isImporting ? "Importing…" : "Import") {
                        importItems()
                    }
                    // P0-C: Import disabled until store is resolved (not nil) and not sentinel.
                    .disabled(confirmed.isEmpty || isImporting || !isStoreResolved)
                }
            }
            .onAppear {
                resolveStoreOnAppear()
            }
        }
    }

    // MARK: - Store picker (shown when auto-resolve fails)

    @ViewBuilder
    private var storePickerSection: some View {
        Picker("Select Store", selection: Binding(
            get: { resolvedStoreID ?? 0 },
            set: { resolvedStoreID = $0 }
        )) {
            Text("— Select a store —").tag(Int64(0))
            ForEach(allStores) { store in
                Text(store.name).tag(store.id)
            }
            Text("Other / Unknown").tag(Int64(-1))
        }
        .pickerStyle(.menu)
    }

    // MARK: - Helpers

    // True when the store is resolved to a real store ID (> 0).
    // Sentinel -1 ("Other") and nil (unresolved) both block import.
    private var isStoreResolved: Bool {
        guard let sid = resolvedStoreID else { return false }
        return sid > 0
    }

    private func resolveStoreOnAppear() {
        // P0-C: Attempt auto-resolve; show picker if it fails.
        let resolved = ReceiptImportService.shared.resolveStore(nameRaw: result.storeNameRaw)
        if let sid = resolved {
            resolvedStoreID = sid
        } else {
            allStores = DatabaseManager.shared.fetchAllStores()
            showUnknownStorePicker = true
        }
    }

    private func importItems() {
        // P0-C: Double-check store is resolved before proceeding.
        guard isStoreResolved, let storeID = resolvedStoreID else { return }

        isImporting = true
        let selectedItems = confirmed.sorted().map { result.items[$0] }

        Task.detached(priority: .userInitiated) {
            ReceiptImportService.shared.importConfirmedItems(
                items:       selectedItems,
                storeID:     storeID,
                receiptDate: result.receiptDate
            )
            await MainActor.run {
                dismiss()
                onDismiss()
            }
        }
    }
}

extension ReceiptScanResult: Identifiable {
    public var id: String { rawLines.joined().hash.description }
}
