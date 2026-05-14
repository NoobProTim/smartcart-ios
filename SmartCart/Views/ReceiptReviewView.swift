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
// P0-2 fix context: ReceiptScannerView sets showError=true if parsedItems is empty;
// this view handles the non-empty case.

import SwiftUI
import Combine

// MARK: - ReceiptReviewViewModel

@MainActor
final class ReceiptReviewViewModel: ObservableObject {

    // Mutable wrappers around the parsed items so the user can edit names / toggle inclusion.
    @Published var editableItems: [EditableReceiptItem]
    @Published var isSaving = false
    @Published var saveComplete = false
    @Published var saveError: String? = nil

    init(items: [ParsedReceiptItem]) {
        // Start with all items included. User can uncheck any.
        self.editableItems = items.map { EditableReceiptItem(source: $0) }
    }

    /// Returns only the items the user has checked for inclusion.
    var selectedItems: [EditableReceiptItem] { editableItems.filter { $0.isIncluded } }

    /// Saves all selected items to items + user_items + purchase_history.
    /// Uses the edited name if the user changed it; otherwise uses the OCR name.
    func confirmAndSave(dismissAction: @escaping () -> Void) {
        guard !selectedItems.isEmpty else {
            saveError = "Select at least one item to add."
            return
        }
        isSaving = true
        saveError = nil

        Task {
            let today = DateHelper.todayString()

            for editable in selectedItems {
                let rawName = editable.editedName.isEmpty ? editable.source.normalisedName : editable.editedName
                // Normalise the name in case the user typed it with mixed case
                let normalisedName = NameNormaliser.normalise(rawName)
                let displayName = rawName.trimmingCharacters(in: .whitespaces)
                    .split(separator: " ").map { $0.capitalized }.joined(separator: " ")

                // Find or create the item in the items table
                let itemID = DatabaseManager.shared.findItem(normalisedName: normalisedName)
                    ?? DatabaseManager.shared.insertItem(normalisedName: normalisedName, displayName: displayName)

                // Add to user's watchlist (INSERT OR IGNORE — safe to call if already present)
                DatabaseManager.shared.addToWatchlist(itemID: itemID)

                // Write a purchase_history row for this receipt line
                if let price = editable.source.parsedPrice {
                    DatabaseManager.shared.insertPurchase(
                        itemID: itemID, storeID: nil, price: price, date: today, source: "receipt")
                }
            }

            isSaving = false
            saveComplete = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.8) { dismissAction() }
        }
    }
}

// Mutable wrapper for one ParsedReceiptItem so it can be toggled and edited in the list.
struct EditableReceiptItem: Identifiable {
    let id = UUID()
    let source: ParsedReceiptItem
    var isIncluded: Bool = true
    // editedName: starts empty (meaning "use source name"); non-empty = user correction
    var editedName: String = ""

    // The name to display in the text field: edited name if set, else the OCR name.
    var displayedName: String {
        editedName.isEmpty ? source.normalisedName : editedName
    }
}

// MARK: - ReceiptReviewView

struct ReceiptReviewView: View {
    @StateObject private var vm: ReceiptReviewViewModel
    @Binding var isPresented: Bool // set to false to dismiss the whole scan flow

    init(items: [ParsedReceiptItem], isPresented: Binding<Bool>) {
        _vm = StateObject(wrappedValue: ReceiptReviewViewModel(items: items))
        _isPresented = isPresented
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.saveComplete {
                    // Post-save celebration state
                    VStack(spacing: 16) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 56)).foregroundStyle(Color.accentColor)
                        Text("\(vm.selectedItems.count) item\(vm.selectedItems.count == 1 ? "" : "s") added")
                            .font(.system(size: 20, weight: .bold))
                        Text("SmartCart is tracking them for you.")
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    reviewList
                }
            }
            .navigationTitle("Review Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { isPresented = false }
                        .disabled(vm.isSaving)
                }
            }
        }
    }

    // MARK: Review list
    private var reviewList: some View {
        VStack(spacing: 0) {
            // Header count
            HStack {
                Text("\(vm.selectedItems.count) of \(vm.editableItems.count) items selected")
                    .font(.system(size: 13)).foregroundStyle(.secondary)
                Spacer()
                // Select all / Deselect all toggle
                Button(vm.editableItems.allSatisfy({ $0.isIncluded }) ? "Deselect all" : "Select all") {
                    let allSelected = vm.editableItems.allSatisfy({ $0.isIncluded })
                    for i in vm.editableItems.indices { vm.editableItems[i].isIncluded = !allSelected }
                }
                .font(.system(size: 13))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            List {
                ForEach($vm.editableItems) { $editable in
                    ReceiptItemRow(editable: $editable)
                }
            }
            .listStyle(.plain)

            // Error message
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
// One editable row. Checkbox, amber badge for low confidence, inline name editor.
struct ReceiptItemRow: View {
    @Binding var editable: EditableReceiptItem
    @State private var isEditing = false

    var body: some View {
        HStack(spacing: 12) {
            // Checkbox — 44pt touch target via frame + contentShape
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
                    // Inline name field: tap to correct OCR mistakes
                    TextField("Item name", text: Binding(
                        get: { editable.displayedName },
                        set: { editable.editedName = $0 }
                    ))
                    .font(.system(size: 15))
                    .foregroundStyle(editable.isIncluded ? .primary : .secondary)

                    // Amber badge: OCR confidence below .high
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
    ReceiptReviewView(items: mockItems, isPresented: .constant(true))
}
