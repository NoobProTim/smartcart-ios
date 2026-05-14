# Scanner & Dashboard Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single-shot receipt scanner with a multi-shot capture flow, add a savings dashboard card to Home, and lay the data foundation for historical low prices and a grocery list.

**Architecture:** New `MultiShotCaptureView` owns camera + thumbnail strip and calls existing `ReceiptScannerService` in parallel per shot before merging and routing to the unchanged `ReceiptReviewView`. DB methods are added as extensions in existing pattern files. No test target exists — verification is build + simulator.

**Tech Stack:** SwiftUI, `ReceiptScannerService` (existing), `DatabaseManager` extensions, SQLite.swift expressions.

---

## File Map

| File | Action | Responsibility |
|------|--------|---------------|
| `SmartCart/Views/MultiShotCaptureView.swift` | **Create** | Camera capture, thumbnail strip, retake, process |
| `SmartCart/Views/ReceiptScanView.swift` | **Delete** | Replaced by MultiShotCaptureView |
| `SmartCart/Views/HomeView.swift` | **Modify** | Use MultiShotCaptureView, add savings card |
| `SmartCart/ViewModels/HomeViewModel.swift` | **Modify** | Add `annualSavings: Double` |
| `SmartCart/Database/DatabaseManager+PriceHistory.swift` | **Modify** | Add `historicalLow(for:)` and `totalSavingsThisYear()` |
| `SmartCart/Database/DatabaseExpressions.swift` | **Modify** | Add grocery_list expressions |
| `SmartCart/Database/DatabaseManager+GroceryList.swift` | **Create** | grocery_list table CRUD |
| `SmartCart/Database/DatabaseManager.swift` | **Modify** | Add grocery_list migration |

---

## Task 1: MultiShotCaptureView

**Files:**
- Create: `SmartCart/Views/MultiShotCaptureView.swift`
- Delete: `SmartCart/Views/ReceiptScanView.swift`
- Modify: `SmartCart/Views/HomeView.swift`

- [ ] **Step 1: Create `MultiShotCaptureView.swift`**

Create `SmartCart/Views/MultiShotCaptureView.swift` with this complete content:

```swift
// MultiShotCaptureView.swift — SmartCart/Views/MultiShotCaptureView.swift
//
// Multi-shot receipt scanner. Replaces ReceiptScanView.
// User takes one or more photos of a receipt (useful for long receipts),
// then taps Process. Each image is OCR'd independently via ReceiptScannerService;
// results are merged by normalisedName (highest confidence wins) and handed
// to ReceiptReviewView as [ParsedReceiptItem].
//
// Tap a thumbnail → Retake button appears → camera opens → replaces that slot.
// Tap elsewhere → deselects thumbnail.

import SwiftUI
import AVFoundation

@MainActor
struct MultiShotCaptureView: View {

    @State private var capturedImages: [UIImage] = []
    @State private var selectedIndex: Int?        = nil
    @State private var retakeIndex: Int?          = nil   // slot to replace on next capture
    @State private var isProcessing               = false
    @State private var showCamera                 = false
    @State private var showPermissionSheet        = false
    @State private var errorMessage: String?      = nil
    @State private var reviewItems: [ParsedReceiptItem]? = nil

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                // Empty state or shot count header
                Group {
                    if capturedImages.isEmpty {
                        emptyPrompt
                    } else {
                        shotCountHeader
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)

                if let err = errorMessage {
                    Text(err)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal)
                        .padding(.bottom, 8)
                }

                if isProcessing {
                    ProgressView("Processing \(capturedImages.count) shot\(capturedImages.count == 1 ? "" : "s")…")
                        .padding(.bottom, 8)
                }

                // Thumbnail strip (hidden when empty)
                if !capturedImages.isEmpty {
                    thumbnailStrip
                }

                // Action bar
                actionBar
            }
            .navigationTitle("Scan Receipt")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .fullScreenCover(isPresented: $showCamera) {
                CameraPickerView(
                    onImage: { image in
                        showCamera = false
                        if let idx = retakeIndex {
                            capturedImages[idx] = image
                            retakeIndex = nil
                        } else {
                            capturedImages.append(image)
                        }
                        selectedIndex = nil
                        errorMessage  = nil
                    },
                    onError: { message in
                        showCamera   = false
                        retakeIndex  = nil
                        errorMessage = message
                    }
                )
            }
            .sheet(isPresented: $showPermissionSheet) {
                cameraPermissionDeniedSheet
            }
            .sheet(
                isPresented: Binding(
                    get: { reviewItems != nil },
                    set: { if !$0 { reviewItems = nil } }
                )
            ) {
                if let items = reviewItems {
                    ReceiptReviewView(
                        items: items,
                        isPresented: Binding(
                            get: { reviewItems != nil },
                            set: { if !$0 { reviewItems = nil } }
                        )
                    )
                }
            }
        }
        .onAppear { openCameraIfEmpty() }
    }

    // MARK: - Subviews

    private var emptyPrompt: some View {
        VStack(spacing: 16) {
            Image(systemName: "doc.viewfinder")
                .font(.system(size: 64))
                .foregroundStyle(.secondary)
            Text("Take photos of your receipt")
                .font(.headline)
            Text("Long receipts? Take multiple shots — order doesn't matter.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
        }
    }

    private var shotCountHeader: some View {
        VStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 48))
                .foregroundStyle(.green)
            Text("\(capturedImages.count) shot\(capturedImages.count == 1 ? "" : "s") captured")
                .font(.headline)
            Text("Add more shots or tap Process.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
    }

    private var thumbnailStrip: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 10) {
                ForEach(capturedImages.indices, id: \.self) { index in
                    thumbnailCell(index: index)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .frame(height: 160)
        .background(Color(.systemGroupedBackground))
    }

    private func thumbnailCell(index: Int) -> some View {
        let isSelected = selectedIndex == index
        return ZStack(alignment: .bottom) {
            Image(uiImage: capturedImages[index])
                .resizable()
                .scaledToFill()
                .frame(width: 90, height: 130)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(isSelected ? Color.accentColor : Color.clear, lineWidth: 3)
                )
                .overlay(
                    // Dim non-selected when one is selected
                    RoundedRectangle(cornerRadius: 10)
                        .fill(Color.black.opacity(selectedIndex != nil && !isSelected ? 0.3 : 0))
                )

            if isSelected {
                Button {
                    retakeIndex   = index
                    selectedIndex = nil
                    checkCameraPermissionAndPresent()
                } label: {
                    Text("Retake")
                        .font(.caption.weight(.semibold))
                        .padding(.horizontal, 10)
                        .padding(.vertical, 5)
                        .background(.ultraThinMaterial)
                        .clipShape(Capsule())
                }
                .padding(.bottom, 6)
            }
        }
        .onTapGesture {
            withAnimation(.easeInOut(duration: 0.15)) {
                selectedIndex = (selectedIndex == index) ? nil : index
            }
        }
    }

    private var actionBar: some View {
        HStack(spacing: 12) {
            Button {
                selectedIndex = nil
                retakeIndex   = nil
                checkCameraPermissionAndPresent()
            } label: {
                Label("Add Shot", systemImage: "plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isProcessing)

            Button {
                processAllShots()
            } label: {
                if isProcessing {
                    ProgressView().frame(maxWidth: .infinity)
                } else {
                    Label("Process", systemImage: "doc.text.viewfinder")
                        .frame(maxWidth: .infinity)
                }
            }
            .buttonStyle(.borderedProminent)
            .disabled(capturedImages.isEmpty || isProcessing)
        }
        .padding()
    }

    @ViewBuilder
    private var cameraPermissionDeniedSheet: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "camera.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("Camera Access Required")
                .font(.title2.weight(.semibold))
            Text("Enable camera access in Settings to scan receipts.")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 32)
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .buttonStyle(.borderedProminent)
            Button("Not Now") { showPermissionSheet = false }
                .foregroundStyle(.secondary)
            Spacer()
        }
        .presentationDetents([.medium])
    }

    // MARK: - Camera helpers

    private func openCameraIfEmpty() {
        if capturedImages.isEmpty { checkCameraPermissionAndPresent() }
    }

    private func checkCameraPermissionAndPresent() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)
        switch status {
        case .authorized:
            showCamera = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { self.showCamera = true }
                    else       { self.showPermissionSheet = true }
                }
            }
        case .denied, .restricted:
            showPermissionSheet = true
        @unknown default:
            showCamera = true
        }
    }

    // MARK: - Processing

    private func processAllShots() {
        isProcessing  = true
        errorMessage  = nil
        selectedIndex = nil

        Task {
            var allItems: [ScannedLineItem] = []

            await withTaskGroup(of: [ScannedLineItem].self) { group in
                for image in capturedImages {
                    group.addTask {
                        (try? await ReceiptScannerService.shared.scan(image: image))?.items ?? []
                    }
                }
                for await items in group {
                    allItems.append(contentsOf: items)
                }
            }

            // Deduplicate: same normalisedName → keep highest confidence
            var seen: [String: ScannedLineItem] = [:]
            for item in allItems {
                if let existing = seen[item.nameNormalised] {
                    if item.confidence > existing.confidence { seen[item.nameNormalised] = item }
                } else {
                    seen[item.nameNormalised] = item
                }
            }

            let parsed = seen.values.map { item in
                ParsedReceiptItem(
                    rawName:        item.nameRaw,
                    normalisedName: item.nameNormalised,
                    parsedPrice:    item.price,
                    confidence:     item.confidence >= 0.8 ? .high : .medium
                )
            }

            isProcessing = false
            if parsed.isEmpty {
                errorMessage = "No items found. Try clearer photos."
            } else {
                reviewItems = parsed
            }
        }
    }
}

// NOTE: CameraPickerView is defined here (moved from deleted ReceiptScanView.swift).
struct CameraPickerView: UIViewControllerRepresentable {
    let onImage: (UIImage) -> Void
    let onError: (String) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onImage: onImage, onError: onError)
    }

    func makeUIViewController(context: Context) -> UIViewController {
        guard UIImagePickerController.isSourceTypeAvailable(.camera) else {
            DispatchQueue.main.async { self.onError("Camera not available on this device.") }
            return UIViewController()
        }
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate   = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIViewController, context: Context) {}

    class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let onImage: (UIImage) -> Void
        let onError: (String) -> Void

        init(onImage: @escaping (UIImage) -> Void, onError: @escaping (String) -> Void) {
            self.onImage = onImage
            self.onError = onError
        }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let img = info[.originalImage] as? UIImage { onImage(img) }
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            picker.dismiss(animated: true)
        }
    }
}
```

- [ ] **Step 2: Delete `ReceiptScanView.swift`**

```bash
rm /Users/tj/smartcart-ios/SmartCart/Views/ReceiptScanView.swift
```

Then in Xcode: right-click `ReceiptScanView.swift` in the file navigator → **Delete → Move to Trash**.

- [ ] **Step 3: Update `HomeView.swift` to use `MultiShotCaptureView`**

Find this in `HomeView.swift`:
```swift
.sheet(isPresented: $showScanner, onDismiss: { viewModel.load() }) {
    ReceiptScanView()
}
```
Replace with:
```swift
.sheet(isPresented: $showScanner, onDismiss: { viewModel.load() }) {
    MultiShotCaptureView()
}
```

- [ ] **Step 4: Build and verify**

```bash
xcodebuild \
  -project SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `** BUILD SUCCEEDED **` with no errors.

- [ ] **Step 5: Smoke-test in simulator**

```bash
xcrun simctl install D0FA3120-3176-463A-AB64-BCFA6CB0B1FC \
  "/Users/tj/Library/Developer/Xcode/DerivedData/SmartCart-ftmfvebyemafyodgeyzvelrcnpri/Build/Products/Debug-iphonesimulator/SmartCart.app"
xcrun simctl launch D0FA3120-3176-463A-AB64-BCFA6CB0B1FC TJ.SmartCart
```

Verify:
1. Tapping the camera FAB on Home opens `MultiShotCaptureView`
2. Camera launches automatically
3. After a capture, a thumbnail appears in the strip
4. Tapping the thumbnail shows a "Retake" button
5. Tapping "Add Shot" opens camera again, adding a second thumbnail
6. "Process" button becomes enabled after first shot

- [ ] **Step 6: Commit**

```bash
git -C /Users/tj/smartcart-ios add \
  SmartCart/Views/MultiShotCaptureView.swift \
  SmartCart/Views/HomeView.swift
git -C /Users/tj/smartcart-ios rm SmartCart/Views/ReceiptScanView.swift
git -C /Users/tj/smartcart-ios commit -m "feat: multi-shot receipt scanner with thumbnail strip and retake"
```

---

## Task 2: Historical Low DB Method

**Files:**
- Modify: `SmartCart/Database/DatabaseManager+PriceHistory.swift`

- [ ] **Step 1: Add `historicalLow(for:)` to `DatabaseManager+PriceHistory.swift`**

Append this method inside the `extension DatabaseManager` block at the bottom of the file (before the closing `}`):

```swift
/// Returns the lowest price recorded for an item, with a label describing the date window.
///
/// Window logic:
///   - January: Q1 of previous year (Jan 1 – Mar 31) labelled "Based on last Jan–Mar"
///   - Feb–Dec:  current year Jan 1 – today, labelled "Lowest this year"
///
/// Queries both price_history and purchase_history; returns the overall MIN.
/// Returns nil if no price data exists for the item in the window.
func historicalLow(for itemID: Int64) -> (price: Double, label: String)? {
    let cal   = Calendar.current
    let today = Date()
    let month = cal.component(.month, from: today)
    let year  = cal.component(.year,  from: today)

    let fmt = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"

    let startStr: String
    let endStr:   String
    let label:    String

    if month == 1 {
        startStr = "\(year - 1)-01-01"
        endStr   = "\(year - 1)-03-31"
        label    = "Based on last Jan–Mar"
    } else {
        startStr = "\(year)-01-01"
        endStr   = fmt.string(from: today)
        label    = "Lowest this year"
    }

    guard let start = fmt.date(from: startStr),
          let end   = fmt.date(from: endStr) else { return nil }

    // MIN from price_history
    let phRows = try? db.prepare(
        priceHistoryTable
            .filter(priceHistItemID == itemID &&
                    priceHistDate   >= start  &&
                    priceHistDate   <= end)
            .select(priceHistPrice)
    )
    let phMin = phRows?.compactMap { $0[priceHistPrice] }.min()

    // MIN from purchase_history (price is nullable)
    let purchRows = try? db.prepare(
        purchaseHistoryTable
            .filter(purchaseItemID == itemID &&
                    purchasedAt    >= start  &&
                    purchasedAt    <= end)
            .select(purchasePrice)
    )
    let purchMin = purchRows?.compactMap { $0[purchasePrice] }.min()

    let candidates = [phMin, purchMin].compactMap { $0 }
    guard let lowest = candidates.min() else { return nil }
    return (price: lowest, label: label)
}
```

- [ ] **Step 2: Build and verify**

```bash
xcodebuild \
  -project SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 3: Commit**

```bash
git -C /Users/tj/smartcart-ios add SmartCart/Database/DatabaseManager+PriceHistory.swift
git -C /Users/tj/smartcart-ios commit -m "feat: add historicalLow(for:) with calendar-year window logic"
```

---

## Task 3: Savings Card on Home

**Files:**
- Modify: `SmartCart/Database/DatabaseManager+PriceHistory.swift`
- Modify: `SmartCart/ViewModels/HomeViewModel.swift`
- Modify: `SmartCart/Views/HomeView.swift`

- [ ] **Step 1: Add `totalSavingsThisYear()` to `DatabaseManager+PriceHistory.swift`**

Append inside the `extension DatabaseManager` block (after `historicalLow`):

```swift
/// Calculates total savings for the current calendar year.
///
/// For each purchase_history row this year where the actual price paid
/// is less than the item's current 90-day rolling average:
///   saving = rollingAvg90 - actualPricePaid
///
/// Returns the sum of all such savings, floored at 0.
func totalSavingsThisYear() -> Double {
    let cal        = Calendar.current
    let year       = cal.component(.year, from: Date())
    let fmt        = DateFormatter()
    fmt.dateFormat = "yyyy-MM-dd"
    guard let startOfYear = fmt.date(from: "\(year)-01-01") else { return 0 }

    let rows = (try? db.prepare(
        purchaseHistoryTable
            .filter(purchasedAt >= startOfYear)
            .select(purchaseItemID, purchasePrice)
    )) ?? AnySequence([])

    var total = 0.0
    for row in rows {
        guard let paid = row[purchasePrice],
              paid > 0,
              let avg = rollingAverage90(for: row[purchaseItemID]),
              paid < avg
        else { continue }
        total += avg - paid
    }
    return max(0, total)
}
```

- [ ] **Step 2: Add `annualSavings` to `HomeViewModel.swift`**

Add this published property after `@Published var isLoading: Bool = false`:
```swift
@Published var annualSavings: Double = 0
```

In the `load()` function, add this line after `isLoading = false`:
```swift
annualSavings = db.totalSavingsThisYear()
```

The updated `load()` body becomes:
```swift
func load() {
    isLoading = true
    Task {
        let allItems = db.fetchUserItems()
        let deals    = computeTodaysDeals(from: allItems)
        let statuses = computeRestockStatuses(for: allItems)
        let sorted   = engine.sortedByUrgency(allItems)
        let savings  = db.totalSavingsThisYear()

        items           = sorted
        todaysDeals     = deals
        restockStatuses = statuses
        annualSavings   = savings
        isLoading       = false
    }
}
```

- [ ] **Step 3: Add savings card to `HomeView.swift`**

In `HomeView.swift`, find `var listContent: some View` (or the `List {` block). Add the savings card as a `Section` at the very top of the `List`, before the "Today's Deals" section:

```swift
// Savings card — only shown when savings > 0
if viewModel.annualSavings > 0 {
    Section {
        HStack(spacing: 16) {
            Image(systemName: "dollarsign.circle.fill")
                .font(.system(size: 36))
                .foregroundStyle(.green)
            VStack(alignment: .leading, spacing: 2) {
                Text("You've saved")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                Text(viewModel.annualSavings, format: .currency(code: "CAD"))
                    .font(.system(size: 22, weight: .bold))
                Text("vs. your average prices this year")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 6)
    }
}
```

- [ ] **Step 4: Build and verify**

```bash
xcodebuild \
  -project SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 5: Commit**

```bash
git -C /Users/tj/smartcart-ios add \
  SmartCart/Database/DatabaseManager+PriceHistory.swift \
  SmartCart/ViewModels/HomeViewModel.swift \
  SmartCart/Views/HomeView.swift
git -C /Users/tj/smartcart-ios commit -m "feat: savings card on Home dashboard — totalSavingsThisYear()"
```

---

## Task 4: Grocery List

**Files:**
- Modify: `SmartCart/Database/DatabaseExpressions.swift`
- Modify: `SmartCart/Database/DatabaseManager.swift`
- Create: `SmartCart/Database/DatabaseManager+GroceryList.swift`
- Modify: `SmartCart/Views/HomeView.swift`
- Modify: `SmartCart/ViewModels/HomeViewModel.swift`

- [ ] **Step 1: Add grocery_list expressions to `DatabaseExpressions.swift`**

Append at the bottom of the file:

```swift
// MARK: - grocery_list

let groceryListTable     = Table("grocery_list")
let groceryListID        = Expression<Int64>("id")
let groceryListItemID    = Expression<Int64>("item_id")
let groceryListPrice     = Expression<Double?>("expected_price")
let groceryListAddedAt   = Expression<Date>("added_date")
let groceryListPurchased = Expression<Int64>("is_purchased")
```

- [ ] **Step 2: Add `grocery_list` migration to `DatabaseManager.swift`**

In `runMigrations()`, at the end of the `do` block (after the last `ALTER TABLE` line), add:

```swift
// grocery_list (Task 4 — flyer tap to list)
try db.run(groceryListTable.create(ifNotExists: true) { t in
    t.column(groceryListID,        primaryKey: .autoincrement)
    t.column(groceryListItemID)
    t.column(groceryListPrice)
    t.column(groceryListAddedAt)
    t.column(groceryListPurchased, defaultValue: 0)
    t.foreignKey(groceryListItemID, references: itemsTable, itemID, delete: .cascade)
})
```

- [ ] **Step 3: Create `DatabaseManager+GroceryList.swift`**

Create `SmartCart/Database/DatabaseManager+GroceryList.swift`:

```swift
// DatabaseManager+GroceryList.swift — SmartCart/Database/DatabaseManager+GroceryList.swift
//
// CRUD for the grocery_list table.
// A grocery list entry is created when the user taps a flyer item on Home.
// It is marked is_purchased = 1 when a matching item is confirmed in ReceiptReviewView.

import Foundation
import SQLite

struct GroceryListItem: Identifiable {
    let id:            Int64
    let itemID:        Int64
    let nameDisplay:   String   // joined from items table
    let expectedPrice: Double?
    let addedAt:       Date
    let isPurchased:   Bool
}

extension DatabaseManager {

    /// Adds an item to the grocery list with an optional expected (sale) price.
    /// Safe to call multiple times — silently skips if item is already on the list
    /// and not yet purchased.
    func addToGroceryList(itemID: Int64, expectedPrice: Double?) {
        let existing = groceryListTable.filter(
            groceryListItemID == itemID && groceryListPurchased == 0
        )
        guard (try? db.scalar(existing.count)) == 0 else { return }
        _ = try? db.run(groceryListTable.insert(
            groceryListItemID  <- itemID,
            groceryListPrice   <- expectedPrice,
            groceryListAddedAt <- Date(),
            groceryListPurchased <- 0
        ))
    }

    /// Returns all unpurchased grocery list items, joined with display name.
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

    /// Marks a grocery list entry as purchased (called from ReceiptReviewView on confirm).
    func markGroceryListItemPurchased(itemID: Int64) {
        _ = try? db.run(
            groceryListTable
                .filter(groceryListItemID == itemID && groceryListPurchased == 0)
                .update(groceryListPurchased <- 1)
        )
    }

    /// Removes an item from the grocery list entirely (user swipe-to-delete).
    func removeFromGroceryList(id: Int64) {
        _ = try? db.run(groceryListTable.filter(groceryListID == id).delete())
    }
}
```

- [ ] **Step 4: Add `groceryList` to `HomeViewModel.swift`**

Add after `@Published var annualSavings: Double = 0`:
```swift
@Published var groceryList: [GroceryListItem] = []
```

In `load()`, add after `annualSavings = savings`:
```swift
groceryList = db.fetchGroceryList()
```

- [ ] **Step 5: Add grocery list section to `HomeView.swift`**

In the `List` in `listContent`, add this section after the savings card and before the "Today's Deals" section:

```swift
// Grocery list section
if !viewModel.groceryList.isEmpty {
    Section {
        ForEach(viewModel.groceryList) { entry in
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(entry.nameDisplay)
                        .font(.system(size: 15))
                    if let price = entry.expectedPrice {
                        Text("Expected: \(price, format: .currency(code: "CAD"))")
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                Image(systemName: "cart")
                    .foregroundStyle(.secondary)
            }
            .swipeActions(edge: .trailing) {
                Button(role: .destructive) {
                    DatabaseManager.shared.removeFromGroceryList(id: entry.id)
                    viewModel.load()
                } label: {
                    Label("Remove", systemImage: "trash")
                }
            }
        }
    } header: {
        Text("Grocery List")
            .font(.system(size: 13, weight: .semibold))
            .foregroundStyle(.secondary)
            .textCase(nil)
    }
}
```

- [ ] **Step 6: Wire flyer tap in `HomeView.swift` to add to grocery list**

Find the `DealRowView` call in `listContent`:
```swift
DealRowView(deal: sale, itemName: item.nameDisplay)
```

Wrap it in a `Button`:
```swift
Button {
    DatabaseManager.shared.addToGroceryList(
        itemID: item.itemID,
        expectedPrice: sale.salePrice
    )
    viewModel.load()
} label: {
    DealRowView(deal: sale, itemName: item.nameDisplay)
}
.buttonStyle(.plain)
```

- [ ] **Step 7: Build and verify**

```bash
xcodebuild \
  -project SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -configuration Debug \
  build 2>&1 | grep -E "error:|BUILD SUCCEEDED|BUILD FAILED"
```

Expected: `** BUILD SUCCEEDED **`

- [ ] **Step 8: Smoke-test in simulator**

```bash
xcrun simctl install D0FA3120-3176-463A-AB64-BCFA6CB0B1FC \
  "/Users/tj/Library/Developer/Xcode/DerivedData/SmartCart-ftmfvebyemafyodgeyzvelrcnpri/Build/Products/Debug-iphonesimulator/SmartCart.app"
xcrun simctl launch D0FA3120-3176-463A-AB64-BCFA6CB0B1FC TJ.SmartCart
```

Verify:
1. Home loads without crash
2. Tapping a deal card adds it to the "Grocery List" section
3. Swipe-to-delete removes it from the list
4. The savings card is hidden when savings = $0 (no purchase history yet)

- [ ] **Step 9: Commit**

```bash
git -C /Users/tj/smartcart-ios add \
  SmartCart/Database/DatabaseExpressions.swift \
  SmartCart/Database/DatabaseManager.swift \
  SmartCart/Database/DatabaseManager+GroceryList.swift \
  SmartCart/ViewModels/HomeViewModel.swift \
  SmartCart/Views/HomeView.swift
git -C /Users/tj/smartcart-ios commit -m "feat: grocery list — add from flyer, show on Home, swipe to remove"
```

---

## Self-Review Notes

- `CameraPickerView` moved from deleted `ReceiptScanView.swift` into `MultiShotCaptureView.swift` — no duplication, single definition.
- `historicalLow` uses `purchasedAt` (the correct column name from `DatabaseExpressions.swift`, not `date`).
- `purchasePrice` is `Expression<Double?>` (nullable) — correctly handled with `compactMap` in both `historicalLow` and `totalSavingsThisYear`.
- `groceryListID` join ambiguity: `groceryListTable.join(itemsTable, on: groceryListItemID == itemID)` — `itemID` refers to `items.id` which is unambiguous as both tables' `id` columns use different expression names (`groceryListID` vs `itemID`).
- Task order: 1 → 2 → 3 → 4. Each task compiles and runs independently.
