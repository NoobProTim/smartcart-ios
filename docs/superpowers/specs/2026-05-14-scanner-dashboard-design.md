# SmartCart — Scanner & Dashboard Feature Design
**Date:** 2026-05-14  
**Status:** Approved for implementation  
**Scope:** Multi-shot receipt scanner, Home dashboard, Flyer grocery list, Historical low logic

---

## 1. Multi-Shot Receipt Scanner

### Decision
Approach B — new `MultiShotCaptureView` wraps existing services. `ReceiptScannerService` and `ReceiptReviewView` are unchanged.

### Entry Point
`MultiShotCaptureView` replaces `ReceiptScanView` as the target of the Home FAB and the "Scan Receipt" button throughout the app.

### State
```swift
@State var capturedImages: [UIImage]   // ordered array; order irrelevant for processing
@State var selectedIndex: Int?         // which thumbnail is in "retake" mode
@State var isProcessing: Bool
@State var showCamera: Bool
@State var errorMessage: String?
```

### Capture Flow
1. View appears → camera sheet opens automatically (first shot)
2. Capture → image appended to `capturedImages` → thumbnail appears in horizontal strip at bottom of screen
3. Camera stays ready; user scrolls receipt down, taps **"+"** for next shot
4. Repeat until all sections of receipt are captured (no enforced limit for test build)
5. **"Process"** button (enabled when `capturedImages.count ≥ 1`) triggers OCR

### Thumbnail Strip
- Horizontal `ScrollView` of fixed-size thumbnails (80×120pt) at bottom of screen
- Tapping a thumbnail → enters **selected state**: "Retake" button overlaid on that thumbnail
- Tapping **"Retake"** → camera opens → new capture replaces image at that index in-place
- Tapping anywhere outside the thumbnail → deselects (no retake triggered)
- No separate remove button — Retake is the only action (replacing is sufficient)

### Processing (on "Process" tap)
```swift
// Parallel OCR via TaskGroup
let allItems: [ScannedLineItem] = await withTaskGroup(...) { group in
    for image in capturedImages {
        group.addTask { try await ReceiptScannerService.shared.scan(image: image).items }
    }
    // collect and flatten
}

// Deduplicate by normalisedName — keep highest-confidence version
let merged = deduplicate(allItems)

// Convert to ParsedReceiptItem and push to ReceiptReviewView
```

### Deduplication Rule
If two shots produce a `ScannedLineItem` with the same `nameNormalised`, keep the one with the higher `confidence` float. This handles receipt seams where the same item line appears in two overlapping shots.

### Files Changed
| File | Change |
|------|--------|
| `Views/MultiShotCaptureView.swift` | **New** — owns camera + thumbnail strip + processing |
| `Views/ReceiptScanView.swift` | **Replaced** — `MultiShotCaptureView` becomes the new entry point |
| `Services/ReceiptScannerService.swift` | No change |
| `Views/ReceiptReviewView.swift` | No change |
| `Views/HomeView.swift` | Update FAB target to `MultiShotCaptureView` |

---

## 2. Home Dashboard

### Layout
Home screen becomes a dashboard with a savings headline card above the existing Smart List.

### Savings Metric
**Label:** "You've saved **$X.XX** this year"  
**Subtitle:** "vs. your average prices"

**Calculation:**
```
savings = SUM(rollingAvg90 - actualPricePaid)
          for all purchase_history rows
          WHERE date >= Jan 1 current year
          AND actualPricePaid < rollingAvg90
```
- Never show negative (floor at $0.00)
- If insufficient price history to compute rollingAvg90 for an item, exclude that purchase from the sum
- Displayed as a card at the top of HomeView, above the segment tabs

### On Sale Now Tab
Existing tab in wireframes. Populated by `FlippService` results for user's tracked items at their selected stores. Each row is tappable — tapping adds item to the grocery list (see Section 3).

### Files Changed
| File | Change |
|------|--------|
| `Views/HomeView.swift` | Add savings card, wire "On Sale Now" taps to grocery list |
| `Database/DatabaseManager.swift` | Add `totalSavingsThisYear() -> Double` |

---

## 3. Flyer Grocery List

### Concept
User taps a flyer item on the "On Sale Now" tab → item is added to an in-app grocery list with the current sale price locked as the "expected price." When the user later scans a receipt containing that item, the app compares actual paid price vs. expected and the difference counts toward total savings.

### Storage
New `grocery_list` table (test build — in-memory state is not sufficient across sessions):
```sql
CREATE TABLE grocery_list (
  id            INTEGER PRIMARY KEY AUTOINCREMENT,
  item_id       INTEGER NOT NULL REFERENCES items(id),
  expected_price REAL,          -- sale price at time of adding
  added_date    TEXT NOT NULL,
  is_purchased  INTEGER DEFAULT 0
);
```

### Flow
1. Tap flyer item on "On Sale Now" → `DatabaseManager.addToGroceryList(itemID:expectedPrice:)`
2. Grocery list visible as a section on Home (below savings card, above Smart List) or as a badge on the Home tab
3. On receipt scan confirm: if a confirmed `ParsedReceiptItem` matches a `grocery_list` row → mark `is_purchased = 1`, compute saving, add to savings total

### Files Changed
| File | Change |
|------|--------|
| `Database/DatabaseManager.swift` | Add `grocery_list` table + CRUD methods |
| `Views/HomeView.swift` | Grocery list section |
| `Views/ReceiptReviewView.swift` | Match confirmed items against grocery_list on save |

---

## 4. Historical Low — Calendar Year Logic

### Rule
| Month | Source period | Label shown to user |
|-------|--------------|---------------------|
| February – December | Jan 1 – today (current year) | "Lowest this year" |
| January | Jan 1 – Mar 31 (previous year) | "Based on last Jan–Mar" |

Auto-switches on Feb 1 with no user action required.

### Data Sources
Query both `purchase_history` and `price_history` — take the overall MIN across both tables for the relevant date window.

### Implementation
```swift
func historicalLow(for itemID: Int64) -> (price: Double, label: String)? {
    let calendar = Calendar.current
    let month = calendar.component(.month, from: Date())
    let year = calendar.component(.year, from: Date())

    let (startDate, endDate, label): (String, String, String)
    if month == 1 {
        // Q1 of previous year
        startDate = "\(year - 1)-01-01"
        endDate   = "\(year - 1)-03-31"
        label     = "Based on last Jan–Mar"
    } else {
        startDate = "\(year)-01-01"
        endDate   = DateHelper.todayString()
        label     = "Lowest this year"
    }

    // MIN(price) across purchase_history UNION price_history for itemID in [startDate, endDate]
}
```

### Where It's Displayed
- Item Detail screen (price banner)
- "On Sale Now" flyer cards (to show how current sale compares)
- Alert notifications (Type A — Historical Low uses 90-day rolling avg, not this; this is a display-only metric)

### Files Changed
| File | Change |
|------|--------|
| `Database/DatabaseManager.swift` | Add `historicalLow(for:) -> (price: Double, label: String)?` |
| `Views/HomeView.swift` | Show on flyer cards |
| Item Detail view (future) | Show in price banner |

---

## Open Questions (deferred to implementation)
- Grocery list UI placement: separate section on Home, or a badge/tab? (decide at build time based on screen density)
- Max shots per scan: no limit for test build; revisit after testing with real receipts
- Savings card visibility when savings = $0: show card with "$0.00" and "Start scanning receipts to track savings" copy, or hide entirely until first saving recorded?

---

## Implementation Order
1. `MultiShotCaptureView` (unblocks all receipt testing)
2. `historicalLow(for:)` in DatabaseManager (no UI dependency, quick win)
3. `totalSavingsThisYear()` + savings card on Home
4. Grocery list table + flyer tap flow
