# SmartCart — Flyers + Grocery List Design Spec
Date: 2026-05-15

## Overview

Replace the current Alerts and History tabs with a Flyers tab. Grocery list lives as a floating sheet (FAB), not a dedicated tab. Receipt scanner is commented out.

---

## Navigation (ContentView)

3 tabs replacing current 4:
- Tab 1: **Home** (house icon) — unchanged
- Tab 2: **Flyers** (tag icon) — new, replaces Alerts
- Tab 3: **Settings** (gearshape icon) — unchanged

History tab removed. Alerts tab removed. Scanner FAB removed from HomeView toolbar.

---

## FlyersView

### Layout (top to bottom)

1. **Nav bar** — large title "Flyers", subtitle "This week's best deals near you"
2. **Search bar** — system-style rounded field, filters deal list as user types
3. **"Best Prices This Week" carousel** — horizontal scroll, dark cards (Option B)
4. **Category chips** — horizontal scroll: All · Meat · Dairy · Eggs · Bakery · Produce · Baking
5. **Deal list** — scrollable list of all active flyer_sales
6. **Floating cart FAB** — fixed bottom-right, above tab bar

### Best Price Carousel Card (dark, 155pt wide)
- Top row: emoji in rounded square (left) · BEST pill + store name stacked (right)
- Item name (up to 2 lines)
- Large price (hero, own line)
- Bottom row: strikethrough original price · "Save $X.XX" in green

### Deal List Row
- Emoji / item image (44pt rounded square)
- Store badge (colored by chain) + expiry date
- Item name
- Sale price · strikethrough original · discount % badge (green)
- Add button (right): black circle with + icon → morphs to green ✓ on tap

### Add to List Feedback
- Button animates: black + → green ✓ (0.2s spring)
- FAB cart badge increments with a scale bounce

### Floating Cart FAB
- 52pt circle, black background, cart emoji
- Red badge (top-right) showing item count, hidden when 0
- Tap → bottom sheet slides up

### Cart Bottom Sheet
- Drag handle at top
- Header: "My List" + item count + "View full list →" (expands to full-screen GroceryListView)
- List of added items: emoji · name · store · price
- "Start Shopping" CTA button at bottom

---

## GroceryListView (full-screen, opened from sheet)

- Large navigation title "My List"
- Each row: large touch target (min 56pt tall)
  - Checkbox (tap to mark purchased)
  - Item name + store
  - Expected price
  - Swipe left to remove
- When checked: row dims, checkmark animates in, purchase recorded to DB
- Empty state: "Add items from Flyers to get started"

---

## Data Layer

### New FlippService method
`fetchPopularDeals(postalCode: String) async -> [FlyerDeal]`
- Queries ~15 common grocery terms in parallel
- Returns lightweight `[FlyerDeal]` structs for display
- Does NOT write to DB (display-only at this stage)

### New FlyerDeal struct
`name, storeName, salePrice, regularPrice, validTo, category, emoji`

### New DatabaseManager method  
`fetchAllActiveSales() -> [FlyerSaleRow]`
- Joins flyer_sales + items + stores
- Filtered to today's active deals
- Used as fallback when Flipp fetch is in-flight

### Existing methods used
- `addToGroceryList(itemID:expectedPrice:)`
- `fetchGroceryList()` 
- `markGroceryListItemPurchased(itemID:)`
- `removeFromGroceryList(id:)`

---

## What's Commented Out

- Scanner FAB button in HomeView toolbar
- `MultiShotCaptureView` sheet presentation
- Receipt scanner is NOT deleted — just inaccessible from UI

---

## Design System
Follows existing conventions:
- Section headers: `.font(.system(size: 11, weight: .semibold).smallCaps())`
- Prices: `.monospacedDigit()`
- Haptics: `.sensoryFeedback(.success, trigger:)` on add-to-list
- Spring animation: `.animation(.spring(duration: 0.2, bounce: 0.2), value:)`
- Card backgrounds: `Color(.secondarySystemGroupedBackground)`
- Discount/save badges: green capsule `rgba(52,199,89,0.12)` / `.green`
