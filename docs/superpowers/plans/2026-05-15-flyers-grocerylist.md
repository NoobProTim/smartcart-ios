# Flyers Tab + Grocery List Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the 4-tab nav with 3 tabs (Home, Flyers, Settings), build a FlyersView that shows live Flipp deals with a best-price carousel + search + category filter, and a floating cart sheet that expands to a full GroceryListView.

**Architecture:** FlyersViewModel fetches deals from a new `FlippService.fetchPopularDeals()` in parallel using TaskGroup. FlyersView owns all flyer+cart state. GroceryListView is a NavigationLink destination inside the cart sheet, using `presentationDetents([.medium, .large])` to expand naturally. Receipt scanner is commented out (not deleted).

**Tech Stack:** SwiftUI, SQLite.swift, AVFoundation (untouched), existing DatabaseManager extensions.

---

## File Map

| Action | File |
|--------|------|
| **Create** | `SmartCart/Models/FlyerDeal.swift` |
| **Create** | `SmartCart/ViewModels/FlyersViewModel.swift` |
| **Create** | `SmartCart/Views/FlyersView.swift` |
| **Create** | `SmartCart/Views/GroceryListView.swift` |
| **Create** | `SmartCart/ViewModels/GroceryListViewModel.swift` |
| **Modify** | `SmartCart/Services/FlippService.swift` |
| **Modify** | `SmartCart/Database/DatabaseManager+GroceryList.swift` |
| **Modify** | `SmartCart/App/ContentView.swift` |
| **Modify** | `SmartCart/Views/HomeView.swift` |

---

## Task 1: FlyerDeal model + DealCategory

**Files:**
- Create: `SmartCart/Models/FlyerDeal.swift`

- [ ] **Step 1: Create FlyerDeal.swift**

```swift
// FlyerDeal.swift — SmartCart/Models/FlyerDeal.swift

import Foundation

enum DealCategory: String, CaseIterable, Hashable {
    case all     = "All"
    case meat    = "Meat"
    case dairy   = "Dairy"
    case eggs    = "Eggs"
    case bakery  = "Bakery"
    case produce = "Produce"
    case baking  = "Baking"

    var emoji: String {
        switch self {
        case .all:     return "🛒"
        case .meat:    return "🥩"
        case .dairy:   return "🥛"
        case .eggs:    return "🥚"
        case .bakery:  return "🍞"
        case .produce: return "🥦"
        case .baking:  return "🧂"
        }
    }

    static func classify(from name: String) -> DealCategory {
        let n = name.lowercased()
        let dairyWords   = ["milk","butter","cream","yogurt","cheese","sour cream","cottage","margarine"]
        let meatWords    = ["chicken","beef","pork","turkey","salmon","fish","lamb","sausage","bacon","ham","steak","ground"]
        let eggWords     = ["egg"]
        let bakeryWords  = ["bread","bagel","bun","muffin","loaf","croissant","tortilla","pita","wrap"]
        let produceWords = ["apple","banana","tomato","lettuce","carrot","pepper","onion","potato","orange","berry","grape","cucumber","spinach","broccoli","celery","lemon","lime","avocado"]
        let bakingWords  = ["flour","sugar","baking","rice","oil","vinegar","salt","spice","sauce","pasta","cereal","oat","syrup"]

        if dairyWords.contains(where: { n.contains($0) })   { return .dairy }
        if meatWords.contains(where: { n.contains($0) })    { return .meat }
        if eggWords.contains(where: { n.contains($0) })     { return .eggs }
        if bakeryWords.contains(where: { n.contains($0) })  { return .bakery }
        if produceWords.contains(where: { n.contains($0) }) { return .produce }
        if bakingWords.contains(where: { n.contains($0) })  { return .baking }
        return .all
    }
}

struct FlyerDeal: Identifiable, Hashable {
    let id:            UUID
    let name:          String
    let storeName:     String
    let salePrice:     Double
    let regularPrice:  Double?
    let validTo:       Date?
    let category:      DealCategory

    var emoji: String { category.emoji }

    var savingsAmount: Double? {
        guard let reg = regularPrice, reg > salePrice else { return nil }
        return reg - salePrice
    }

    var discountPercent: Int? {
        guard let reg = regularPrice, reg > salePrice, reg > 0 else { return nil }
        return Int(((reg - salePrice) / reg) * 100)
    }

    var expiryLabel: String? {
        guard let end = validTo else { return nil }
        let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: Date()), to: Calendar.current.startOfDay(for: end)).day ?? 0
        if days < 0  { return nil }
        if days == 0 { return "ends today" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "ends \(fmt.string(from: end))"
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project /Users/tj/smartcart-ios/SmartCart/SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16' \
  build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED` (no errors)

- [ ] **Step 3: Commit**

```bash
git -C /Users/tj/smartcart-ios add SmartCart/Models/FlyerDeal.swift
git -C /Users/tj/smartcart-ios commit -m "feat: FlyerDeal model and DealCategory enum"
```

---

## Task 2: Fix FlippService + add fetchPopularDeals

**Files:**
- Modify: `SmartCart/Services/FlippService.swift`

The `FlippItem` decoder currently maps `storeCode` from `"retailer_name"` — the real API field is `"merchant_name"`. Also missing `originalPrice`.

- [ ] **Step 1: Replace FlippItem struct (top of FlippService.swift)**

Replace the entire `FlippItem` struct (lines 28–54) with:

```swift
struct FlippItem: Decodable {
    let name:          String
    let currentPrice:  Double
    let originalPrice: Double?
    let validTo:       String?
    let storeCode:     String?

    enum CodingKeys: String, CodingKey {
        case name
        case currentPrice  = "current_price"
        case originalPrice = "original_price"
        case validTo       = "valid_to"
        case storeCode     = "merchant_name"   // was "retailer_name" — API uses merchant_name
    }

    init(from decoder: Decoder) throws {
        let c     = try decoder.container(keyedBy: CodingKeys.self)
        name      = try c.decode(String.self, forKey: .name)
        validTo   = try? c.decode(String.self, forKey: .validTo)
        storeCode = try? c.decode(String.self, forKey: .storeCode)
        if let d = try? c.decode(Double.self, forKey: .currentPrice) {
            currentPrice = d
        } else if let s = try? c.decode(String.self, forKey: .currentPrice), let d = Double(s) {
            currentPrice = d
        } else {
            currentPrice = 0.0
        }
        if let d = try? c.decode(Double.self, forKey: .originalPrice), d > 0 {
            originalPrice = d
        } else {
            originalPrice = nil
        }
    }
}
```

- [ ] **Step 2: Add FlyerDeal initialiser from FlippItem**

Add this extension at the bottom of `FlippService.swift`, before the final `}`:

```swift
// MARK: - FlyerDeal initialiser
extension FlyerDeal {
    init?(flippItem: FlippItem) {
        guard flippItem.currentPrice > 0.01, let store = flippItem.storeCode, !store.isEmpty else { return nil }
        let fmt = ISO8601DateFormatter()
        self.id           = UUID()
        self.name         = flippItem.name
        self.storeName    = store
        self.salePrice    = flippItem.currentPrice
        self.regularPrice = flippItem.originalPrice
        self.validTo      = flippItem.validTo.flatMap { fmt.date(from: $0) }
        self.category     = DealCategory.classify(from: flippItem.name)
    }
}
```

- [ ] **Step 3: Add fetchPopularDeals to FlippService**

Add this method inside `FlippService`, after `fetchPrices(for:)`:

```swift
// MARK: - fetchPopularDeals
/// Fetches deals across common grocery categories in parallel.
/// Returns deduplicated results sorted by discount % descending.
func fetchPopularDeals(postalCode: String) async -> [FlyerDeal] {
    let terms = [
        "milk", "chicken", "beef", "eggs", "bread",
        "butter", "yogurt", "apple", "tomato", "rice",
        "flour", "pork", "cheese", "orange juice", "cereal"
    ]

    var allDeals: [FlyerDeal] = []
    await withTaskGroup(of: [FlyerDeal].self) { group in
        for term in terms {
            group.addTask {
                let items = await self.queryFlipp(term: term, postalCode: postalCode)
                return items.compactMap { FlyerDeal(flippItem: $0) }
            }
        }
        for await batch in group {
            allDeals.append(contentsOf: batch)
        }
    }

    var seen = Set<String>()
    let deduped = allDeals.filter { deal in
        let key = "\(deal.name.lowercased())|\(deal.storeName.lowercased())"
        return seen.insert(key).inserted
    }
    return deduped.sorted { ($0.discountPercent ?? 0) > ($1.discountPercent ?? 0) }
}
```

- [ ] **Step 4: Verify build**

```bash
xcodebuild -project /Users/tj/smartcart-ios/SmartCart/SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16' \
  build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 5: Commit**

```bash
git -C /Users/tj/smartcart-ios add SmartCart/Services/FlippService.swift
git -C /Users/tj/smartcart-ios commit -m "fix: FlippService merchant_name field, add originalPrice, fetchPopularDeals"
```

---

## Task 3: DatabaseManager — add fetchAllActiveSales

**Files:**
- Modify: `SmartCart/Database/DatabaseManager+GroceryList.swift`

- [ ] **Step 1: Add ActiveSaleRow struct and fetchAllActiveSales to DatabaseManager+GroceryList.swift**

Add after the closing `}` of the existing `GroceryListItem` struct, before `extension DatabaseManager`:

```swift
struct ActiveSaleRow: Identifiable {
    let id:           Int64
    let itemName:     String
    let storeName:    String
    let salePrice:    Double
    let regularPrice: Double?
    let validTo:      Date?
}
```

Add this method inside `extension DatabaseManager`, after `removeFromGroceryList`:

```swift
/// All active flyer_sales joined with item display names and store names.
/// Used as offline fallback when Flipp is unavailable.
func fetchAllActiveSales() -> [ActiveSaleRow] {
    let today = Date()
    let query = flyerSalesTable
        .join(itemsTable, on: flyerItemID == itemID)
        .filter(flyerStartDate <= today)
    let rows = (try? db.prepare(query)) ?? AnySequence([])
    return rows.compactMap { row in
        let end = row[flyerEndDate]
        if let end = end, end < today { return nil }
        let storeRow     = try? db.pluck(storesTable.filter(storeID == row[flyerStoreID]))
        let storeNameVal = storeRow?[storeName] ?? "Unknown"
        return ActiveSaleRow(
            id:           row[flyerID],
            itemName:     row[itemNameDisplay],
            storeName:    storeNameVal,
            salePrice:    row[flyerSalePrice],
            regularPrice: row[flyerRegularPrice],
            validTo:      row[flyerEndDate]
        )
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project /Users/tj/smartcart-ios/SmartCart/SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16' \
  build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git -C /Users/tj/smartcart-ios add SmartCart/Database/DatabaseManager+GroceryList.swift
git -C /Users/tj/smartcart-ios commit -m "feat: DatabaseManager fetchAllActiveSales for offline fallback"
```

---

## Task 4: FlyersViewModel

**Files:**
- Create: `SmartCart/ViewModels/FlyersViewModel.swift`

- [ ] **Step 1: Create FlyersViewModel.swift**

```swift
// FlyersViewModel.swift — SmartCart/ViewModels/FlyersViewModel.swift

import SwiftUI

@MainActor
final class FlyersViewModel: ObservableObject {
    @Published var deals:          [FlyerDeal]   = []
    @Published var isLoading:       Bool           = false
    @Published var searchText:      String         = ""
    @Published var selectedCategory: DealCategory  = .all
    @Published var addedIDs:        Set<UUID>      = []
    @Published var cartCount:       Int            = 0

    var filteredDeals: [FlyerDeal] {
        var result = deals
        if selectedCategory != .all {
            result = result.filter { $0.category == selectedCategory }
        }
        if !searchText.isEmpty {
            result = result.filter {
                $0.name.localizedCaseInsensitiveContains(searchText) ||
                $0.storeName.localizedCaseInsensitiveContains(searchText)
            }
        }
        return result
    }

    var bestDeals: [FlyerDeal] {
        Array(
            deals
                .filter { $0.discountPercent != nil }
                .sorted { ($0.discountPercent ?? 0) > ($1.discountPercent ?? 0) }
                .prefix(10)
        )
    }

    func load() async {
        guard deals.isEmpty else { return }
        isLoading = true
        let postalCode = DatabaseManager.shared.getSetting(key: "user_postal_code") ?? "M5V3A8"
        deals = await FlippService.shared.fetchPopularDeals(postalCode: postalCode)
        cartCount = DatabaseManager.shared.fetchGroceryList().count
        isLoading = false
    }

    func addToCart(_ deal: FlyerDeal) {
        let db   = DatabaseManager.shared
        let norm = NameNormaliser.normalise(deal.name)
        let iid  = db.upsertItem(nameNormalised: norm, nameDisplay: deal.name)
        db.addToGroceryList(itemID: iid, expectedPrice: deal.salePrice)
        addedIDs.insert(deal.id)
        cartCount = db.fetchGroceryList().count
    }

    func refreshCartCount() {
        cartCount = DatabaseManager.shared.fetchGroceryList().count
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project /Users/tj/smartcart-ios/SmartCart/SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16' \
  build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git -C /Users/tj/smartcart-ios add SmartCart/ViewModels/FlyersViewModel.swift
git -C /Users/tj/smartcart-ios commit -m "feat: FlyersViewModel with deal loading, filtering, and cart management"
```

---

## Task 5: GroceryListViewModel + GroceryListView

**Files:**
- Create: `SmartCart/ViewModels/GroceryListViewModel.swift`
- Create: `SmartCart/Views/GroceryListView.swift`

- [ ] **Step 1: Create GroceryListViewModel.swift**

```swift
// GroceryListViewModel.swift — SmartCart/ViewModels/GroceryListViewModel.swift

import SwiftUI

@MainActor
final class GroceryListViewModel: ObservableObject {
    @Published var items: [GroceryListItem] = []

    func load() {
        items = DatabaseManager.shared.fetchGroceryList()
    }

    func markPurchased(_ item: GroceryListItem) {
        DatabaseManager.shared.markGroceryListItemPurchased(itemID: item.itemID)
        items.removeAll { $0.id == item.id }
    }

    func delete(at offsets: IndexSet) {
        offsets.forEach { DatabaseManager.shared.removeFromGroceryList(id: items[$0].id) }
        items.remove(atOffsets: offsets)
    }
}
```

- [ ] **Step 2: Create GroceryListView.swift**

```swift
// GroceryListView.swift — SmartCart/Views/GroceryListView.swift

import SwiftUI

struct GroceryListView: View {
    @StateObject private var vm = GroceryListViewModel()

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
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project /Users/tj/smartcart-ios/SmartCart/SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16' \
  build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git -C /Users/tj/smartcart-ios add SmartCart/ViewModels/GroceryListViewModel.swift SmartCart/Views/GroceryListView.swift
git -C /Users/tj/smartcart-ios commit -m "feat: GroceryListView with check-off and swipe-to-delete"
```

---

## Task 6: FlyersView (carousel + search + category + list + cart FAB)

**Files:**
- Create: `SmartCart/Views/FlyersView.swift`

- [ ] **Step 1: Create FlyersView.swift**

```swift
// FlyersView.swift — SmartCart/Views/FlyersView.swift

import SwiftUI

struct FlyersView: View {
    @StateObject private var vm = FlyersViewModel()
    @State private var showCart = false

    var body: some View {
        NavigationStack {
            ZStack(alignment: .bottomTrailing) {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        bestPriceCarousel
                        categoryChips
                        dealList
                    }
                }

                CartFAB(count: vm.cartCount) { showCart = true }
                    .padding(.trailing, 16)
                    .padding(.bottom, 16)
            }
            .navigationTitle("Flyers")
            .navigationSubtitle("This week's best deals near you")
            .searchable(text: $vm.searchText, prompt: "Search deals...")
            .overlay {
                if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground).opacity(0.6))
                }
            }
        }
        .task { await vm.load() }
        .sheet(isPresented: $showCart, onDismiss: { vm.refreshCartCount() }) {
            NavigationStack {
                CartSheetView()
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
    }

    // MARK: Best price carousel
    private var bestPriceCarousel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Best prices this week")
                .font(.system(size: 11, weight: .semibold).smallCaps())
                .textCase(nil)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(vm.bestDeals) { deal in
                        BestPriceCard(deal: deal)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: Category chips
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DealCategory.allCases, id: \.self) { cat in
                    Button {
                        vm.selectedCategory = cat
                    } label: {
                        Text("\(cat.emoji) \(cat.rawValue)")
                            .font(.system(size: 13, weight: vm.selectedCategory == cat ? .semibold : .regular))
                            .foregroundStyle(vm.selectedCategory == cat ? .white : Color(.label))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                vm.selectedCategory == cat
                                    ? Color(.label)
                                    : Color(.secondarySystemGroupedBackground)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(duration: 0.2), value: vm.selectedCategory)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: Deal list
    private var dealList: some View {
        LazyVStack(spacing: 8) {
            if vm.filteredDeals.isEmpty && !vm.isLoading {
                Text("No deals found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                ForEach(vm.filteredDeals) { deal in
                    DealRow(
                        deal: deal,
                        isAdded: vm.addedIDs.contains(deal.id)
                    ) {
                        vm.addToCart(deal)
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 80)
    }
}

// MARK: - BestPriceCard
private struct BestPriceCard: View {
    let deal: FlyerDeal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Emoji (left) + BEST pill / store name (right)
            HStack(alignment: .top) {
                Text(deal.emoji)
                    .font(.system(size: 24))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("BEST")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Color.yellow)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.yellow.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    Text(deal.storeName.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .padding(.bottom, 10)

            Text(deal.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.65))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            Text(deal.salePrice, format: .currency(code: "CAD"))
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.bottom, 6)

            HStack(spacing: 6) {
                if let reg = deal.regularPrice {
                    Text(reg, format: .currency(code: "CAD"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.28))
                        .strikethrough()
                        .monospacedDigit()
                }
                if let savings = deal.savingsAmount {
                    Text("Save \(savings, format: .currency(code: "CAD"))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(13)
        .frame(width: 155, alignment: .leading)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

// MARK: - DealRow
private struct DealRow: View {
    let deal:    FlyerDeal
    let isAdded: Bool
    let onAdd:   () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(deal.emoji)
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    StoreBadgeView(name: deal.storeName)
                    if let label = deal.expiryLabel {
                        Text(label)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(deal.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(deal.salePrice, format: .currency(code: "CAD"))
                        .font(.system(size: 15, weight: .bold))
                        .monospacedDigit()

                    if let reg = deal.regularPrice {
                        Text(reg, format: .currency(code: "CAD"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .strikethrough()
                            .monospacedDigit()
                    }

                    if let pct = deal.discountPercent {
                        Text("−\(pct)%")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
            }

            Spacer()

            Button(action: onAdd) {
                Image(systemName: isAdded ? "checkmark" : "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(isAdded ? Color.green : Color(white: 0.11))
                    .clipShape(Circle())
                    .animation(.spring(duration: 0.2, bounce: 0.2), value: isAdded)
            }
            .buttonStyle(.plain)
            .disabled(isAdded)
            .sensoryFeedback(.success, trigger: isAdded)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - StoreBadgeView
struct StoreBadgeView: View {
    let name: String

    private var color: Color {
        switch name.lowercased() {
        case let n where n.contains("no frills"):  return Color(red: 0.91, green: 0.14, blue: 0.16)
        case let n where n.contains("loblaws"):    return Color(red: 0.78, green: 0.06, blue: 0.18)
        case let n where n.contains("metro"):      return Color(red: 0.0,  green: 0.19, blue: 0.53)
        case let n where n.contains("walmart"):    return Color(red: 0.0,  green: 0.44, blue: 0.86)
        case let n where n.contains("highland"):   return Color(red: 0.18, green: 0.50, blue: 0.25)
        case let n where n.contains("sobeys"):     return Color(red: 0.82, green: 0.14, blue: 0.14)
        default:                                    return Color.secondary
        }
    }

    var body: some View {
        Text(name.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .lineLimit(1)
    }
}

// MARK: - CartFAB
struct CartFAB: View {
    let count:  Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            ZStack(alignment: .topTrailing) {
                Image(systemName: "cart.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(.white)
                    .frame(width: 52, height: 52)
                    .background(Color(white: 0.11))
                    .clipShape(Circle())
                    .shadow(color: .black.opacity(0.3), radius: 8, y: 4)

                if count > 0 {
                    Text("\(min(count, 99))")
                        .font(.system(size: 10, weight: .black))
                        .foregroundStyle(.white)
                        .frame(width: 18, height: 18)
                        .background(Color.red)
                        .clipShape(Circle())
                        .overlay(Circle().strokeBorder(Color(.systemBackground), lineWidth: 2))
                        .offset(x: 4, y: -4)
                        .transition(.scale.combined(with: .opacity))
                }
            }
        }
        .buttonStyle(.plain)
        .animation(.spring(duration: 0.2, bounce: 0.3), value: count)
    }
}

// MARK: - CartSheetView
struct CartSheetView: View {
    @State private var items: [GroceryListItem] = []

    var body: some View {
        Group {
            if items.isEmpty {
                VStack(spacing: 14) {
                    Image(systemName: "cart")
                        .font(.system(size: 40))
                        .foregroundStyle(.secondary)
                    Text("Your list is empty")
                        .font(.headline)
                    Text("Tap + on any deal to add it.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List {
                    ForEach(items) { item in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(item.nameDisplay)
                                    .font(.system(size: 14, weight: .semibold))
                                if let price = item.expectedPrice {
                                    Text(price, format: .currency(code: "CAD"))
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                        .monospacedDigit()
                                }
                            }
                            Spacer()
                        }
                        .padding(.vertical, 2)
                    }
                }
                .listStyle(.insetGrouped)
            }
        }
        .navigationTitle("My List")
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                NavigationLink("View full list") {
                    GroceryListView()
                }
                .font(.system(size: 14, weight: .semibold))
            }
        }
        .onAppear { items = DatabaseManager.shared.fetchGroceryList() }
    }
}
```

- [ ] **Step 2: Verify build**

```bash
xcodebuild -project /Users/tj/smartcart-ios/SmartCart/SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16' \
  build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 3: Commit**

```bash
git -C /Users/tj/smartcart-ios add SmartCart/Views/FlyersView.swift
git -C /Users/tj/smartcart-ios commit -m "feat: FlyersView with carousel, search, category filter, deal list, cart FAB"
```

---

## Task 7: ContentView — 3-tab swap + HomeView scanner comment-out

**Files:**
- Modify: `SmartCart/App/ContentView.swift`
- Modify: `SmartCart/Views/HomeView.swift`

- [ ] **Step 1: Replace ContentView.swift body**

Replace the entire `ContentView` struct body with:

```swift
struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
            FlyersView()
                .tabItem {
                    Label("Flyers", systemImage: "tag")
                }
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}
```

Delete `HistoryTabView` struct from the same file (lines 34–76) — it's no longer reachable.

- [ ] **Step 2: Comment out scanner FAB in HomeView.swift**

In `HomeView.swift`, find the scanner toolbar button (around line 56–62) and comment it out:

```swift
// Scanner button commented out — receipt scanner on hold
// Button { showScanner = true } label: {
//     Image(systemName: "camera.viewfinder")
//         .font(.system(size: 18))
// }
// .accessibilityLabel("Scan a receipt")
```

Also comment out the scanner sheet presentation. Find the `.sheet` that references `MultiShotCaptureView` (search for `showScanner`) and comment it out:

```swift
// .sheet(isPresented: $showScanner) {
//     MultiShotCaptureView(...)
// }
```

- [ ] **Step 3: Verify build**

```bash
xcodebuild -project /Users/tj/smartcart-ios/SmartCart/SmartCart.xcodeproj \
  -scheme SmartCart \
  -destination 'platform=iOS Simulator,OS=latest,name=iPhone 16' \
  build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "error:|BUILD"
```

Expected: `BUILD SUCCEEDED`

- [ ] **Step 4: Commit**

```bash
git -C /Users/tj/smartcart-ios add SmartCart/App/ContentView.swift SmartCart/Views/HomeView.swift
git -C /Users/tj/smartcart-ios commit -m "feat: 3-tab nav (Home/Flyers/Settings), scanner FAB commented out"
```

---

## Self-Review

**Spec coverage check:**
- ✅ 3 tabs: Home, Flyers, Settings — Task 7
- ✅ FlyersView: search, carousel, category chips, deal list — Task 6
- ✅ Best-price carousel (dark cards, Option B) — Task 6 `BestPriceCard`
- ✅ + button → green ✓ + FAB badge increment — Task 6 `DealRow` + `FlyersViewModel.addToCart`
- ✅ Floating cart FAB with count badge — Task 6 `CartFAB`
- ✅ Cart bottom sheet + "View full list" → GroceryListView — Task 6 `CartSheetView`
- ✅ GroceryListView with check-off and swipe-to-delete — Task 5
- ✅ Scanner FAB commented out — Task 7
- ✅ Flipp merchant_name bug fixed — Task 2
- ✅ fetchPopularDeals parallel fetch — Task 2
- ✅ fetchAllActiveSales offline fallback — Task 3

**Type consistency check:**
- `FlyerDeal` defined Task 1, consumed in Tasks 4, 6 — ✅ same struct
- `DealCategory` defined Task 1, used in Task 4 `FlyersViewModel.selectedCategory` — ✅
- `upsertItem(nameNormalised:nameDisplay:)` — matches DatabaseManager.swift line 231 — ✅
- `addToGroceryList(itemID:expectedPrice:)` — matches DatabaseManager+GroceryList.swift — ✅
- `fetchGroceryList() -> [GroceryListItem]` — matches, `GroceryListItem` used in Tasks 5, 6 — ✅
- `CartFAB` defined in FlyersView.swift, used only in FlyersView — ✅
- `CartSheetView` defined in FlyersView.swift — ✅
- `StoreBadgeView` defined in FlyersView.swift — ✅
- `FlyerDeal(flippItem:)` init defined in Task 2, called in `fetchPopularDeals` Task 2 — ✅
