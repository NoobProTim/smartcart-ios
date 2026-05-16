# SmartCart — Product Requirements Document v2
**Updated:** 2026-05-15
**Status:** Living document — supersedes PRD.md
**Previous version:** docs/PRD.md (preserved for reference)

---

## Product Vision

> "Your personal grocery intelligence layer — know what you pay, know when to buy."

SmartCart is a personal finance tool for grocery shoppers. It combines three data sources into one buying signal:

1. **Your receipts** — what you actually paid, when, and where (on-device OCR)
2. **Live market prices** — what things cost right now at your stores (Flipp API)
3. **Your patterns** — how often you buy each item and when you're running low (SQLite)

When all three align — you're running low, it's on sale, and the price is below your historical average — SmartCart tells you. That's the product.

**Zero marginal cost to run:** Apple Vision OCR, local SQLite, Flipp API (confirmed: commercial use permitted for non-competing personal tools).

---

## Core Loop

```
Scan receipt → app learns prices + patterns
       ↓
Browse deals → see what's on sale at your stores this week
       ↓
Build list → add items where deal timing aligns with replenishment
       ↓
Buy → check off → purchase record written → loop repeats, smarter
```

The loop is only complete when all four steps work. Currently the purchase write-back (step 4) is missing — highest priority fix before any new features.

---

## Implementation Status

- ✅ Shipped and working
- ⚠️ Partial — exists but incomplete
- ❌ Not built
- 🔒 Blocked — pending external confirmation (Flipp legal)

---

## Navigation (Current — as of 2026-05-15)

| Tab | Icon | Screen |
|-----|------|--------|
| Home | house | Dashboard + Smart List |
| Flyers | tag | Deal feed + category filter |
| My List | cart.fill | Grocery list with badge count |
| Settings | gear | Stores, postal code, alerts |

**Scanner:** FAB on Home tab (camera button) → `MultiShotCaptureView`

---

## Navigation (v2 Target)

| Tab | Icon | Screen | Change |
|-----|------|--------|--------|
| Home | house | Dashboard + smart list + scanner FAB | Keep |
| Deals | tag | Flipp deal feed + flyer browser | Expand current Flyers tab |
| My List | cart.fill | Grocery list | Keep |
| Insights | chart.xyaxis.line | Price history + purchase patterns | New — replace Settings as tab 4 |
| Settings | gear | Moved to gear icon in nav bar on Home | Demote from tab |

---

## Feature Specs

---

### F1 — Receipt Scanner (REVIVE — core value prop)

The scanner is the primary mechanism by which SmartCart learns. Without it, there is no purchase history, no replenishment cycle, no price intelligence. It is currently dormant. Reviving it is the highest-leverage improvement in the product.

**Target flow:**
1. Tap camera FAB on Home
2. Scanner opens with store selector pre-filled from last use
3. Capture one or more receipt photos
4. Processing overlay ("Reading your receipt…")
5. Review screen — matched items, prices, quantities, unmatched flagged
6. Confirm → purchase records written to `purchase_history`, prices to `price_history`
7. Success sheet with achievement pills

**Status:**
- ✅ Multi-shot camera capture (`MultiShotCaptureView`)
- ✅ Thumbnail strip + retake flow
- ✅ Processing overlay
- ✅ Review screen with confidence badges + inline editing
- ✅ Confirm & Save writes to DB
- ⚠️ Store selector exists in `SettingsView` but not on scanner
- ⚠️ OCR parsing unreliable on Canadian grocery receipts (two-column layout, French text)
- ❌ Corner bracket overlay on camera frame
- ❌ Store/date/total header on Review screen
- ❌ Quantity field per item on Review screen
- ❌ Achievement pills on success sheet
- ❌ "Back to Smart List" / "Review items" on success sheet

**Priority gaps to fix:**
1. Store selector on scanner (P0 — purchases unattributable without it)
2. OCR reliability for Canadian receipts (ongoing — defer to after loop closes)
3. Achievement pills + success sheet CTAs (P2 — delight moment)

---

### F2 — Purchase Loop Completion (P0 — MISSING)

When a user checks off an item in the grocery list, it does not write a purchase record. The app cannot learn patterns without this. This is the single most important missing piece.

**Required behaviour:**
- Check off item in `GroceryListView` → `markPurchased()` in `GroceryListViewModel`
- Write a row to `purchase_history`: `item_id`, `store_id` (from user's primary store), `price` (from `grocery_list.expected_price`), `purchased_at`, `source = "list"`
- Trigger replenishment recalculation for that item
- Remove from grocery list (already works)

**Files to touch:**
- `DatabaseManager+GroceryList.swift` — add purchase write inside `markGroceryListItemPurchased()`
- `DatabaseManager+Fixes.swift` — call `recalculateReplenishment(itemID:)` after write

---

### F3 — Deals Tab (Flipp — working, expand)

**Current state:** Flipp deal feed working. 15 grocery terms queried in parallel, filtered by user's selected stores, displayed as best-price carousel + category-filtered list.

**v2 additions:**

#### F3a — Flyer Browser 🔒
Display the actual weekly store circular inside the app. Users tap a store and scroll through flyer pages.

- Fetch active flyers for user's stores via Flipp flyer endpoint
- Display pages as native SwiftUI paged image viewer (not WebView)
- Cache pages to disk — works offline after first load
- Full Flipp attribution on every page
- **Blocked:** awaiting written confirmation from Flipp legal (email drafted in FLYERS-PLAN.md)

#### F3b — Smart Price Matching
When browsing deals, surface a "vs your price" comparison for items already in `purchase_history`.

- "You paid $4.99 last time · Today $3.49 · Save $1.50"
- Only shown for items the user has bought before
- Drives immediate add-to-list behaviour

#### F3c — Pre-Shop Mode
Before leaving for the store, user opens "Pre-Shop" — SmartCart checks every item on the grocery list against current Flipp deals across all their stores and surfaces better prices available elsewhere.

- "Oat Milk on your list · $4.99 at No Frills · $3.49 at Metro this week"
- Shown as a banner or sheet on the grocery list tab

---

### F4 — Home Tab (Dashboard)

**Current state:** Greeting header, segment tabs (My List / On Sale Now), Today's Deals section, savings card, camera FAB.

**v2 additions:**

#### F4a — New User Surface
New users with no purchase history currently see an empty dashboard. Show:
- "Scan your first receipt" hero card with camera illustration
- "Browse this week's deals" secondary CTA → Deals tab
- Disappears once first receipt is scanned

#### F4b — Replenishment Alerts Banner
"3 items running low this week" — tappable, expands to show which items and their current best prices.

#### F4c — Weekly Summary Card (Sundays)
One-line savings summary: "You saved $12.40 on groceries this week vs your usual prices."

---

### F5 — Insights Tab (New)

Replaces the dormant History tab. A personal analytics surface showing the user how SmartCart is working for them.

**Sections:**
- **Spending over time** — weekly grocery spend bar chart (from `purchase_history`)
- **Best savings** — top 5 items where SmartCart alerts led to a lower price
- **Price trends** — items whose prices have been consistently rising (inflation signal)
- **Your stores** — spend breakdown by store, average basket size

**Data source:** All from local `purchase_history` + `price_history` — no network required.

---

### F6 — Smart Price Alerts (Enhance existing)

**Current state:** Alert types A/B/C exist. Alert log table exists. Notification permission flow exists.

**v2 behaviour:**
- Alert fires only when: item is on sale AND user is within replenishment window AND sale price is below user's historical average
- Max 3 alerts per day (already enforced)
- Alert card shows: current price vs your average, days until you'll likely run out, store + expiry
- Tap alert → add to grocery list in one tap

---

### F7 — Onboarding (Polish)

**Current state:** Carousel → store selection → postal code → notification permission. Working.

**v2 additions:**
- After notification permission: show "Scan your first receipt" as step 4 — get users into the scanner immediately, before they reach the empty Home screen
- Skip path goes straight to Deals tab (not Home) — new users with no history get more value browsing deals than seeing an empty list

---

### F8 — Settings (Demote + Complete)

Settings moves from a primary tab to a gear icon in the Home nav bar. Tab slot freed for Insights.

**Missing items to complete:**
- Postal code update (currently only set during onboarding — no way to change it)
- Replenishment nudges toggle (separate from sale alerts)
- Weekly summary toggle
- Price intelligence: calculation method selector (median / average / most recent)
- Notification quiet hours

---

## Build Priority

### Sprint 1 — Close the loop (nothing else until this is done)
1. **Purchase loop** — `markPurchased()` writes to `purchase_history` (F2)
2. **Store selector on scanner** — attribute purchases to correct store (F1)
3. **New user Home surface** — scanner CTA + deals CTA (F4a)

### Sprint 2 — Intelligence layer
4. **Smart price matching on Deals tab** — "vs your price" comparison (F3b)
5. **Replenishment alerts banner on Home** (F4b)
6. **Insights tab** — spending chart + savings summary (F5)

### Sprint 3 — Flyer browser (post legal confirmation)
7. **Flyer browser** — if Flipp confirms, build native page viewer (F3a)
8. **Pre-shop mode** — cross-store price check before shopping (F3c)

### Sprint 4 — Polish
9. **Onboarding step 4** — first receipt scan prompt (F7)
10. **Settings completion** — postal code update, replenishment toggle, quiet hours (F8)
11. **Receipt review** — store/date/total header, quantity field, achievement pills (F1)
12. **Weekly summary card** on Home Sundays (F4c)

---

## Data Model (current — complete)

| Table | Purpose | Status |
|---|---|---|
| `stores` | Store registry | ✅ |
| `user_stores` | User's selected stores | ✅ |
| `items` | Normalised item catalogue | ✅ |
| `user_items` | Tracked items + replenishment data | ✅ |
| `purchase_history` | Every purchase ever scanned/confirmed | ✅ |
| `price_history` | Market prices from Flipp | ✅ |
| `flyer_sales` | Active sale events from Flipp | ✅ |
| `alert_log` | Fired alerts | ✅ |
| `user_settings` | Key/value settings store | ✅ |
| `grocery_list` | Current shopping list | ✅ |

**No schema changes needed for Sprint 1.** Purchase loop only requires writing to `purchase_history` (table exists) and calling `recalculateReplenishment` (function exists in `DatabaseManager+Fixes.swift`).

---

## External Dependencies

| Dependency | Status | Risk |
|---|---|---|
| Flipp API (deal search) | ✅ Working | Medium — undocumented endpoint |
| Flipp API (flyer pages) | 🔒 Pending legal | Low if confirmed |
| Apple Vision (OCR) | ✅ Working | None — on-device |
| CLGeocoder (postal → city) | ✅ Working | None — Apple SDK |
| SQLite.swift | ✅ Working | None — open source |

**Resilience plan for Flipp:** See `docs/FLYERS-PLAN.md` — `FlyerProvider` protocol abstraction in Phase 3 allows swapping to Reebee, Save.ca, or direct store PDFs if Flipp becomes unavailable.

---

## Open Questions

- [ ] Flipp legal confirmation received? → unblocks flyer browser (F3a)
- [ ] OCR reliability on Canadian receipts — worth another pass or defer indefinitely?
- [ ] Insights tab: is spending chart useful before user has 4+ weeks of history?
- [ ] Pre-shop mode (F3c): modal sheet or dedicated tab section?
