// ReceiptReviewView.swift
// SmartCart — Views/ReceiptReviewView.swift
//
// Shown after the camera captures a receipt and ReceiptParser runs.
// Displays the list of ParsedReceiptItems with:
//   - Checkbox to include/exclude each line
//   - Amber badge for low-confidence OCR lines (confidence < .high)
//   - Inline name correction field (tap to edit)
//   - Confirm CTA: saves selected items to user_items + purchase_history
//
// Sprint 3: saveComplete state now shows per-item "Saved $X vs your avg"
// copy for any item where the purchase price was below the user's rolling
// average. Falls back gracefully to the plain confirmation if no prior
// purchase history exists for a given item.

import SwiftUI
import Combine

// MARK: - SavingsSummaryRow
// Value type: one item's name + how much was saved vs the rolling average.
// Used to populate the success screen achievement rows.
struct SavingsSummaryRow: Identifiable {
    let id = UUID()
    let itemName: String
    let savedAmount: Double   // positive = paid less than average
}

// MARK: - ReceiptReviewViewModel

@MainActor
final class ReceiptReviewViewModel: ObservableObject {

    @Published var editableItems: [EditableReceiptItem]
    @Published var isSaving = false
    @Published var saveComplete = false
    @Published var saveError: String? = nil
    // Populated after save — rows where purchase price < rolling average.
    // Empty if no prior history exists for any saved item.
    @Published var savingsRows: [SavingsSummaryRow] = []

    private let storeID: Int64?

    init(items: [ParsedReceiptItem], storeID: Int64? = nil) {
        self.editableItems = items.map { EditableReceiptItem(source: $0) }
        self.storeID = storeID
    }

    var selectedItems: [EditableReceiptItem] { editableItems.filter { $0.isIncluded } }

    var subtotal: Double {
        selectedItems.compactMap { $0.source.parsedPrice }.reduce(0, +)
    }

    /// Total savings shown on the success screen.
    var totalSaved: Double { savingsRows.reduce(0) { $0 + $1.savedAmount } }

    // MARK: confirmAndSave(dismissAction:)
    // Saves all selected items to items + user_items + purchase_history.
    // After saving, computes per-item savings vs rolling average and
    // populates savingsRows so the success screen can show them.
    func confirmAndSave(dismissAction: @escaping () -> Void) {
        guard !selectedItems.isEmpty else {
            saveError = "Select at least one item to add."
            return
        }
        isSaving = true
        saveError = nil

        Task {
            let today = DateHelper.todayString()
            var computed: [SavingsSummaryRow] = []

            for editable in selectedItems {
                let rawName = editable.editedName.isEmpty ? editable.source.normalisedName : editable.editedName
                let normalisedName = NameNormaliser.normalise(rawName)
                let displayName = rawName.trimmingCharacters(in: .whitespaces)
                    .split(separator: " ").map { $0.capitalized }.joined(separator: " ")

                let itemID = DatabaseManager.shared.findItem(normalisedName: normalisedName)
                    ?? DatabaseManager.shared.insertItem(normalisedName: normalisedName, displayName: displayName)

                DatabaseManager.shared.addToWatchlist(itemID: itemID)

                if let price = editable.source.parsedPrice {
                    // Read the rolling average BEFORE writing this purchase,
                    // so we compare against historical data only.
                    let avgBefore = DatabaseManager.shared.averagePrice(for: itemID)

                    DatabaseManager.shared.insertPurchase(
                        itemID: itemID, storeID: storeID, price: price, date: today, source: "receipt")

                    // If we have a prior average and we paid less, record a savings row.
                    if let avg = avgBefore, price < avg {
                        computed.append(SavingsSummaryRow(
                            itemName: displayName,
                            savedAmount: avg - price
                        ))
                    }
                }

                DatabaseManager.shared.markGroceryListItemPurchased(itemID: itemID)
            }

            savingsRows = computed
            isSaving = false
            saveComplete = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.4) { dismissAction() }
        }
    }
}

// Mutable wrapper for one ParsedReceiptItem so it can be toggled and edited.
struct EditableReceiptItem: Identifiable {
    let id = UUID()
    let source: ParsedReceiptItem
    var isIncluded: Bool = true
    var editedName: String = ""

    var displayedName: String {
        editedName.isEmpty ? source.normalisedName : editedName
    }
}

// MARK: - ReceiptReviewView

struct ReceiptReviewView: View {
    @StateObject private var vm: ReceiptReviewViewModel
    @Binding var isPresented: Bool
    let storeName: String?

    init(items: [ParsedReceiptItem], storeID: Int64? = nil, storeName: String? = nil, isPresented: Binding<Bool>) {
        _vm = StateObject(wrappedValue: ReceiptReviewViewModel(items: items, storeID: storeID))
        _isPresented = isPresented
        self.storeName = storeName
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.saveComplete {
                    successView
                } else {
                    reviewList
                }
            }
            .navigationTitle(storeName.map { "Review · \($0)" } ?? "Review Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .disabled(vm.isSaving)
                }
            }
        }
        .sensoryFeedback(.success, trigger: vm.saveComplete)
    }

    // MARK: - successView
    // Shown after confirmAndSave completes. If any items were bought below
    // their rolling average, a green "You saved" headline and per-item rows
    // are shown. If no prior history exists, the plain confirmation is shown.
    private var successView: some View {
        ScrollView {
            VStack(spacing: 20) {
                Spacer().frame(height: 20)

                // Big checkmark
                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 64))
                    .foregroundStyle(Color.accentColor)

                // Headline — personalised if we have savings data
                if vm.totalSaved > 0 {
                    VStack(spacing: 4) {
                        Text("Great shop!")
                            .font(.system(size: 22, weight: .bold))
                        Text("You saved \(vm.totalSaved, format: .currency(code: "CAD")) vs your averages")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                    }
                } else {
                    VStack(spacing: 4) {
                        Text("\(vm.selectedItems.count) item\(vm.selectedItems.count == 1 ? "" : "s") added")
                            .font(.system(size: 22, weight: .bold))
                        Text("SmartCart is tracking them for you.")
                            .font(.system(size: 15))
                            .foregroundStyle(.secondary)
                    }
                }

                // Achievement pills row
                HStack(spacing: 8) {
                    AchievementPill(
                        icon: "tag.fill",
                        label: "\(vm.selectedItems.count) tracked",
                        color: .accentColor
                    )
                    if vm.subtotal > 0 {
                        AchievementPill(
                            icon: "dollarsign.circle.fill",
                            label: String(format: "$%.2f receipt", vm.subtotal),
                            color: .green
                        )
                    }
                }

                // Per-item savings breakdown — only shown if savings exist.
                // Each row tells the user exactly which item they bought well.
                if !vm.savingsRows.isEmpty {
                    VStack(alignment: .leading, spacing: 0) {
                        Text("Savings breakdown")
                            .font(.system(size: 13, weight: .medium))
                            .foregroundStyle(.secondary)
                            .textCase(.uppercase)
                            .kerning(0.4)
                            .padding(.horizontal, 16)
                            .padding(.bottom, 8)

                        VStack(spacing: 0) {
                            ForEach(vm.savingsRows) { row in
                                HStack {
                                    Text(row.itemName)
                                        .font(.system(size: 15))
                                        .foregroundStyle(.primary)
                                    Spacer()
                                    Text("-\(row.savedAmount, format: .currency(code: "CAD")) vs avg")
                                        .font(.system(size: 14, weight: .semibold))
                                        .foregroundStyle(.green)
                                        .monospacedDigit()
                                }
                                .padding(.horizontal, 16)
                                .padding(.vertical, 10)
                                if row.id != vm.savingsRows.last?.id {
                                    Divider().padding(.leading, 16)
                                }
                            }
                        }
                        .background(Color(.secondarySystemGroupedBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                        .padding(.horizontal, 16)
                    }
                }

                Spacer().frame(height: 20)
            }
            .frame(maxWidth: .infinity)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - reviewList
    private var reviewList: some View {
        VStack(spacing: 0) {
            // Totals header bar
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 2) {
                    if let name = storeName {
                        Text(name)
                            .font(.system(size: 14, weight: .semibold))
                    }
                    Text(Date(), format: .dateTime.month(.abbreviated).day().year())
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
                Spacer()
                VStack(alignment: .trailing, spacing: 2) {
                    if vm.subtotal > 0 {
                        Text(String(format: "$%.2f", vm.subtotal))
                            .font(.system(size: 15, weight: .semibold))
                            .monospacedDigit()
                    }
                    Text("\(vm.selectedItems.count) of \(vm.editableItems.count) items")
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.secondarySystemBackground))

            // Select all toggle
            HStack {
                Text("Items")
                    .font(.system(size: 13, weight: .medium)).foregroundStyle(.secondary)
                Spacer()
                Button(vm.editableItems.allSatisfy({ $0.isIncluded }) ? "Deselect all" : "Select all") {
                    let allSelected = vm.editableItems.allSatisfy({ $0.isIncluded })
                    for i in vm.editableItems.indices { vm.editableItems[i].isIncluded = !allSelected }
                }
                .font(.system(size: 13))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 8)

            List {
                ForEach($vm.editableItems) { $editable in
                    ReceiptItemRow(editable: $editable)
                }
            }
            .listStyle(.plain)

            if let err = vm.saveError {
                Text(err).font(.system(size: 13)).foregroundStyle(.red)
                    .padding(.horizontal, 16).padding(.top, 4)
            }

            // Confirm CTA
            Button(action: {
                vm.confirmAndSave { isPresented = false }
            }) {
                Group {
                    if vm.isSaving {
                        ProgressView().tint(.white)
                    } else {
                        Text("Add \(vm.selectedItems.count) Item\(vm.selectedItems.count == 1 ? "" : "s") to Smart List")
                            .font(.system(size: 16, weight: .semibold))
                    }
                }
                .foregroundStyle(.white)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(vm.selectedItems.isEmpty ? Color.secondary.opacity(0.4) : Color.accentColor)
                .clipShape(RoundedRectangle(cornerRadius: 14))
            }
            .disabled(vm.selectedItems.isEmpty || vm.isSaving)
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }
}

// MARK: - ReceiptItemRow
// One editable row. Checkbox, amber confidence badge, inline name editor.
struct ReceiptItemRow: View {
    @Binding var editable: EditableReceiptItem

    var body: some View {
        HStack(spacing: 12) {
            Button(action: { editable.isIncluded.toggle() }) {
                Image(systemName: editable.isIncluded ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 22))
                    .foregroundStyle(editable.isIncluded ? Color.accentColor : Color.secondary)
            }
            .frame(width: 44, height: 44)
            .contentShape(Rectangle())
            .accessibilityLabel(editable.isIncluded ? "Deselect \(editable.displayedName)" : "Select \(editable.displayedName)")

            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 6) {
                    TextField("Item name", text: Binding(
                        get: { editable.displayedName },
                        set: { editable.editedName = $0 }
                    ))
                    .font(.system(size: 15))
                    .foregroundStyle(editable.isIncluded ? .primary : .secondary)

                    if editable.source.confidence != .high {
                        Text(editable.source.confidence == .low ? "Low confidence" : "Review")
                            .font(.system(size: 10, weight: .semibold))
                            .padding(.horizontal, 6).padding(.vertical, 2)
                            .background(Color.orange.opacity(0.15))
                            .foregroundStyle(Color.orange)
                            .clipShape(Capsule())
                    }
                }

                if let price = editable.source.parsedPrice {
                    Text(String(format: "$%.2f", price))
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
            }
        }
        .opacity(editable.isIncluded ? 1.0 : 0.45)
        .listRowSeparator(.visible)
    }
}

// MARK: - AchievementPill
private struct AchievementPill: View {
    let icon: String
    let label: String
    let color: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: icon)
                .font(.system(size: 11, weight: .semibold))
            Text(label)
                .font(.system(size: 12, weight: .semibold))
        }
        .foregroundStyle(color)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(color.opacity(0.10))
        .clipShape(Capsule())
    }
}

// MARK: - Preview
#Preview {
    let mockItems: [ParsedReceiptItem] = [
        ParsedReceiptItem(rawName: "SALTED BUTTER", normalisedName: "salted butter",
                          parsedPrice: 5.99, confidence: .high),
        ParsedReceiptItem(rawName: "2% MILK 4L", normalisedName: "2% milk 4l",
                          parsedPrice: 6.49, confidence: .medium),
        ParsedReceiptItem(rawName: "CHKN BRST 1KG", normalisedName: "chkn brst 1kg",
                          parsedPrice: 14.99, confidence: .low),
        ParsedReceiptItem(rawName: "EGGS DOZEN", normalisedName: "eggs dozen",
                          parsedPrice: 5.29, confidence: .high),
    ]
    ReceiptReviewView(items: mockItems, storeName: "No Frills", isPresented: .constant(true))
}
