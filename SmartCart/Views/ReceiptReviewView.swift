// ReceiptReviewView.swift — SmartCart/Views/ReceiptReviewView.swift
import SwiftUI

struct ReceiptReviewView: View {

    let result: ReceiptScanResult
    let onDismiss: () -> Void

    @State private var confirmed: Set<Int> = []
    // P1-E: per-row quantity, keyed by item index, default 1
    @State private var quantities: [Int: Int] = [:]
    @State private var isImporting            = false
    @State private var resolvedStoreID: Int64?
    @State private var showUnknownStorePicker = false
    @State private var allStores: [Store]     = []
    @Environment(\.dismiss) private var dismiss

    init(result: ReceiptScanResult, onDismiss: @escaping () -> Void) {
        // P1-C: debug-only precondition — catches empty-result regressions early.
        #if DEBUG
        precondition(!result.items.isEmpty,
            "ReceiptReviewView must not be instantiated with an empty item list.")
        #endif
        self.result    = result
        self.onDismiss = onDismiss
        _confirmed     = State(initialValue: Set(result.items.indices))
        _quantities    = State(initialValue: Dictionary(
            uniqueKeysWithValues: result.items.indices.map { ($0, 1) }
        ))
    }

    var body: some View {
        NavigationStack {
            // P1-C: Zero-item guard — show ContentUnavailableView with a Try Again CTA.
            if result.items.isEmpty {
                if #available(iOS 17, *) {
                    ContentUnavailableView {
                        Label("No Items Found", systemImage: "doc.text.magnifyingglass")
                    } description: {
                        Text("The scan didn't detect any line items. Try a clearer photo.")
                    } actions: {
                        Button("Try Again") { dismiss(); onDismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                } else {
                    VStack(spacing: 16) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.system(size: 48)).foregroundStyle(.secondary)
                        Text("No Items Found").font(.title2.weight(.semibold))
                        Text("The scan didn't detect any line items. Try a clearer photo.")
                            .multilineTextAlignment(.center).foregroundStyle(.secondary)
                        Button("Try Again") { dismiss(); onDismiss() }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                }
            } else {
                List {
                    Section("Store") {
                        if showUnknownStorePicker {
                            storePickerSection
                        } else {
                            Text(result.storeNameRaw ?? "Unknown store")
                                .foregroundStyle(resolvedStoreID == nil ? Color.orange : Color.secondary)
                            if resolvedStoreID == nil {
                                Text("Store not recognised — please select below to enable import.")
                                    .font(.caption).foregroundStyle(.orange)
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
                                    Text(item.nameRaw).font(.body)
                                    Text(item.nameNormalised).font(.caption).foregroundStyle(.secondary)
                                }
                                Spacer()
                                // P1-E: Quantity stepper — only visible when row is confirmed.
                                if confirmed.contains(index) {
                                    Stepper(
                                        value: Binding(
                                            get: { quantities[index] ?? 1 },
                                            set: { quantities[index] = $0 }
                                        ),
                                        in: 1...99
                                    ) {
                                        Text("×\(quantities[index] ?? 1)")
                                            .font(.caption.monospacedDigit())
                                            .foregroundStyle(.secondary)
                                    }
                                    .labelsHidden()
                                    .fixedSize()
                                }
                                Text("$\(String(format: "%.2f", item.price))")
                                    .font(.body.monospacedDigit())
                            }
                            .contentShape(Rectangle())
                            .onTapGesture {
                                if confirmed.contains(index) { confirmed.remove(index) }
                                else                         { confirmed.insert(index) }
                            }
                        }
                    }
                }
                .navigationTitle("Review Receipt")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss(); onDismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(isImporting ? "Importing…" : "Import") { importItems() }
                            .disabled(confirmed.isEmpty || isImporting || !isStoreResolved)
                    }
                }
                .onAppear { resolveStoreOnAppear() }
            }
        }
    }

    // MARK: - Store picker
    @ViewBuilder
    private var storePickerSection: some View {
        Picker("Select Store", selection: Binding(
            get: { resolvedStoreID ?? 0 },
            set: { resolvedStoreID = $0 }
        )) {
            Text("— Select a store —").tag(Int64(0))
            ForEach(allStores) { store in Text(store.name).tag(store.id) }
            Text("Other / Unknown").tag(Int64(-1))
        }
        .pickerStyle(.menu)
    }

    private var isStoreResolved: Bool {
        guard let sid = resolvedStoreID else { return false }
        return sid > 0
    }

    private func resolveStoreOnAppear() {
        if let sid = ReceiptImportService.shared.resolveStore(nameRaw: result.storeNameRaw) {
            resolvedStoreID = sid
        } else {
            allStores = DatabaseManager.shared.fetchAllStores()
            showUnknownStorePicker = true
        }
    }

    private func importItems() {
        guard isStoreResolved, let storeID = resolvedStoreID else { return }
        isImporting = true
        // P1-E: Pass quantity per confirmed item to markPurchased.
        let selectedItems: [(ParsedReceiptItem, Int)] = confirmed.sorted().map {
            (result.items[$0], quantities[$0] ?? 1)
        }
        Task.detached(priority: .userInitiated) {
            ReceiptImportService.shared.importConfirmedItems(
                items:       selectedItems.map { $0.0 },
                quantities:  selectedItems.map { $0.1 },
                storeID:     storeID,
                receiptDate: result.receiptDate
            )
            await MainActor.run { dismiss(); onDismiss() }
        }
    }
}

// P1-H: Identifiable conformance removed — ReceiptScanResult now carries
// a stable UUID id set at scan time by ReceiptScannerService.shared.scan().
// No Identifiable extension needed here.
