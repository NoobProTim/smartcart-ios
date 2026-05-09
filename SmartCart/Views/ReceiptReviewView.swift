// ReceiptReviewView.swift — SmartCart/Views/ReceiptReviewView.swift
//
// Shows scanned line items for user review before importing to database.
// User can toggle individual items on/off before confirming.

import SwiftUI

struct ReceiptReviewView: View {

    let result: ReceiptScanResult
    let onDismiss: () -> Void

    @State private var confirmed: Set<Int> = []
    @State private var isImporting = false
    @Environment(\.dismiss) private var dismiss

    init(result: ReceiptScanResult, onDismiss: @escaping () -> Void) {
        self.result = result
        self.onDismiss = onDismiss
        // Default: all items confirmed.
        _confirmed = State(initialValue: Set(result.items.indices))
    }

    var body: some View {
        NavigationStack {
            List {
                if let store = result.storeNameRaw {
                    Section("Store") {
                        Text(store).foregroundStyle(.secondary)
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
                    .disabled(confirmed.isEmpty || isImporting)
                }
            }
        }
    }

    private func importItems() {
        isImporting = true
        let selectedItems = confirmed.sorted().map { result.items[$0] }
        let storeID = ReceiptImportService.shared.resolveStore(
            nameRaw: result.storeNameRaw) ?? 0
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
