# SmartCart — Product Requirements Document
**Source:** Wireframes at github.com/NoobProTim/smartcart/wireframes (4 batches)  
**Generated:** 2026-05-14  
**Status:** Living document — update as features ship

---

## Product Vision

> "CamelCamelCamel for groceries — personalised."

SmartCart scans your grocery receipts, builds a per-item price history at your actual stores, and alerts you when **your** items hit a genuine historical low — timed to when you're likely running out.

**Zero cost to run:** On-device OCR (Apple Vision), SQLite database, Flipp API for flyer prices.

---

## Implementation Status Legend

- ✅ Done
- ⚠️ Partial (exists but incomplete)
- ❌ Missing

---

## Navigation Structure

### Wireframe spec — 4-tab bottom nav:
| Tab | Icon | Screen |
|-----|------|--------|
| Home | house | Smart List + Dashboard |
| Alerts | bell (with badge) | Alerts & Deals |
| History | chart.line | Price History |
| Settings | gear | Settings |

### Current state:
- ✅ Home tab → `HomeView` (just wired)
- ❌ Alerts tab — no dedicated Alerts screen
- ❌ History tab — `PriceHistoryView` exists but not a tab
- ✅ Settings tab → `SettingsView`
- ⚠️ Scanner — accessible via camera FAB on Home + Scan tab (wireframe uses FAB only, no separate tab)

**Gap:** Replace Scan tab with Alerts tab; add History tab; camera stays as FAB on Home.

---

## Screen 1 — Splash / Launch

**Spec:**
- Logo (green square, cart+checkmark icon)
- App name: "SmartCart"
- Tagline: "Know when to buy"
- Loading bar, auto-advances after 2s

**Status:** ✅ `SplashView.swift` exists

---

## Screen 2 — Onboarding Carousel

**Spec (3 slides):**
1. "SmartCart remembers what you buy" — receipt scanning illustration
2. "See real price history for your items" — 90-day price graph
3. "Get alerted when YOUR items hit a low" — notification examples
- Navigation: dot indicators, Back/Next, Skip
- Final: "Get Started" button

**Status:** ✅ `OnboardingCarouselView.swift` exists

---

## Screen 3 — Store Selection (Onboarding step 1 of 2)

**Spec:**
- Progress indicator: "Step 1 of 2"
- Title: "Which stores do you shop at?"
- Search bar: "Search stores…"
- Store list (10): Loblaws, No Frills, Metro, Sobeys, FreshCo, Walmart Canada, Costco Canada, Food Basics, Giant Tiger, Independent Grocers
- Each row: logo, name, category, checkbox
- Footer: dynamic "X stores selected"
- Continue button disabled until ≥1 selected

**Status:** ⚠️ Store selection exists in `SettingsView` but NOT wired into onboarding flow. `OnboardingSetupView.swift` may cover this — needs review.

**Gap:** Wire store selection into onboarding sequence before first use.

---

## Screen 4 — Notification Permission (Onboarding step 2 of 2)

**Spec:**
- Icon: bell with red notification dot
- Title: "Stay ahead of price drops"
- 3 example notifications shown
- iOS system permission dialog
- "Allow Notifications" + "Not now"

**Status:** ⚠️ `NotificationBannerView` exists as dismissible banner. Not wired as onboarding step.

**Gap:** Show as step 2 of onboarding, not just as a banner post-launch.

---

## Screen 5 — Home / Smart List

**Spec:**
- Greeting: "Good evening, [Name]" + "X items near replenishment"
- Alert banner: "X deals active right now · Item at Store · Item at Store"
- **Segment tabs:** "My List" | "On Sale Now"

### My List tab:
- Section "Running Low" (items in restock window)
- Section "Tracked Items" (everything else)
- Each item card:
  - Emoji thumbnail
  - Product name
  - "Last bought X days ago · Avg every Xd"
  - Price + store
  - Badge: "⏱ Due in N day(s)" OR "✓ Historical Low"
  - Sale pricing in green with strikethrough original

### On Sale Now tab:
- Sale cards per item with:
  - Store chip
  - Original price struck through
  - Sale price in green
  - "Save $X.XX · Ends [Day]"
  - Product emoji
  - Tap → add to grocery list

### FAB:
- Camera icon, bottom-right
- Opens `MultiShotCaptureView`

**Status:**
- ✅ Smart List items with restock badge
- ✅ Today's Deals section
- ✅ Grocery list section
- ✅ Savings card
- ✅ FAB (camera button in toolbar)
- ⚠️ Items don't have emoji thumbnails
- ❌ Greeting header ("Good evening, Timothy")
- ❌ Alert banner ("X deals active right now")
- ❌ Segment tabs ("My List" / "On Sale Now") — currently all sections stacked in one list
- ❌ "Last bought X days ago · Avg every Xd" metadata on list rows
- ❌ Strikethrough original price on sale items

---

## Screen 6 — Receipt Scanner

**Spec:**
- Top: close button, "Scan Receipt", store selector dropdown ("No Frills ▾")
- Camera frame with corner bracket overlay
- Animated vertical scan line
- "Fit receipt inside frame" hint
- Bottom shutter row: grid icon | shutter button | upload icon
- Tips row: "Flatten receipt", "Good lighting", "All lines visible"
- Processing overlay: blur + spinner + "Reading your receipt…"

**Status:**
- ✅ Multi-shot camera capture (`MultiShotCaptureView`)
- ✅ Thumbnail strip, retake flow
- ✅ Processing overlay with `ProgressView`
- ❌ Store selector dropdown (no way to tag which store the receipt is from)
- ❌ Corner bracket overlay on camera
- ❌ Scanning tips row
- ❌ Receipt totals passed through to Review screen

**Gap (key):** Store selector is important — without it, purchases can't be attributed to the right store for price history.

---

## Screen 7 — Receipt Review

**Spec:**
- Header: Store avatar, "StoreName · City", date, total amount, item count
- Warning banner: "X item(s) couldn't be matched — tap to fix"
- Item cards:
  - Checkbox
  - Product name (bold)
  - Category + store (muted)
  - Quantity: ×1, ×2
  - Price right-aligned
  - Unmatched state: "Needs review" chip (amber)
- Sticky footer: "X matched · X needs review" · "Prices saved to history ✓" · "Confirm & Save" + "Discard scan"

**Status:**
- ✅ Checkbox per item
- ✅ Inline name editing
- ✅ Amber confidence badge (low/medium)
- ✅ Confirm & Save
- ❌ Store/date/total header
- ❌ "Needs review" vs matched/unmatched states (we use confidence, not match status)
- ❌ Quantity field per item
- ❌ "Discard scan" secondary button (Cancel exists but no explicit Discard)

---

## Screen 8 — Confirm Success Sheet

**Spec:**
- Modal sheet over Review
- ✓ checkmark icon
- "Receipt saved!"
- "X items added to your price history"
- Achievement pills: "🏷 X new deals found", "📦 X items tracked", "📊 Prices updated"
- "What happens next" box with item-specific copy
- "Back to Smart List" + "Review items"

**Status:**
- ✅ Post-save celebration state (checkmark + item count)
- ❌ Achievement pills
- ❌ "What happens next" contextual copy
- ❌ "Back to Smart List" / "Review items" buttons (just auto-dismisses after 0.8s)

---

## Screen 9 — Item Detail

**Spec:**
- Product hero: large emoji (72×72), product name, brand/size
- Tag labels: "📉 All-Time Low" (red) and/or "✓ In Season" (green)
- **Price banner:**
  - Current sale price (large, primary color)
  - Previous price struck through
  - Store + expiry ("@ Metro · expires Sun")
  - "Your Low" label with ✓ if current = personal low
  - Discount badge ("−22%")
- **Price history chart** (30d / 90d / 1yr / All tabs) with:
  - Retail price line
  - Personal average dashed line
  - Sale event dots
  - Current price indicator
- **Smart Insights grid (2×2):**
  - Avg Cycle: "11 days"
  - You Usually Pay: "$5.12"
  - Sale Frequency: "~3×/mo"
  - Stock Up Qty: "2 units"
- **Replenishment section:**
  - "Last purchased X days ago"
  - Progress bar (last purchase → predicted reorder)
  - Alert timing: "Alert set for Day N · X days out"
- **Current Prices Nearby (multi-store list):**
  - Each row: store name, price, freshness ("Updated 2h ago"), BEST badge
- **Purchase History list:**
  - Each entry: receipt #, store, price, date, price-vs-avg indicator
- **Sticky footer CTA:** "🔔 Set Price Alert" + "✓ Add to Shopping List"
- **Alert Sheet:** 3 options (Price Drop, Replenishment+Sale, Any Sale)

**Status:**
- ✅ Product name, last purchased, store, paid price
- ✅ Price history chart (30d/90d/1yr/All)
- ✅ Alert sheet (A/B/C types)
- ✅ Confirm Purchase with quantity stepper
- ✅ Historical low card (just added: green card with calendar-year low)
- ❌ Emoji thumbnail in hero
- ❌ "All-Time Low" / "In Season" tag labels
- ❌ Sale price banner (current sale vs regular)
- ❌ "Your Low" comparison badge
- ❌ Discount percentage badge
- ❌ Smart Insights grid (avg cycle, usual price, sale frequency, stock-up qty)
- ❌ Replenishment progress bar
- ❌ Current Prices Nearby (multi-store)
- ❌ Purchase history list
- ❌ "Add to Shopping List" footer button

---

## Screen 10 — Alerts & Deals (dedicated tab)

**Spec:**
- Date label + "Alerts & Deals" title
- Summary banner: "X genuine deals right now · All timed to your replenishment cycles · $X.XX potential savings"
- Filter chips (horizontal scroll): All (N) | 🔥 On Sale (N) | 🔔 Running Low (N) | 📌 Watching (N)
- Alert cards (one per triggered item):
  - Product emoji + colored background by type
  - Name, store, expiry
  - Badge: ALL-TIME LOW (red) / ON SALE (green) / RUNNING LOW (blue) / WATCHING (neutral)
  - Current price vs was price + savings + discount %
  - Replenishment timing: "Due in ~X days · Good timing" or "Due in ~X days · Early"
  - "Dismiss" + "Add to List" CTAs
- Alert Preferences toggles (at bottom):
  - Price Drop Alerts
  - Replenishment Alerts
  - Quiet Hours: "10 PM – 7 AM"
  - Timing Filter: "Only alert when sale + replen align"

**Status:** ❌ Entirely missing — no Alerts & Deals screen in the app

---

## Screen 11 — Settings

**Spec:**
- **Notifications section:**
  - Price alerts (toggle ON) — "When items hit historical lows"
  - Replenishment nudges (toggle ON) — "When you're likely running out"
  - Weekly summary (toggle OFF) — "One recap each Sunday"
- **Your Stores section:** card with saved store locations, Edit link
- **Location & Flyers:** postal code input with validation
- **Price Intelligence section:**
  - Replenishment window explanation
  - Calculation method chip selector: "Median of last 6" / "Average of last 6" / "Most recent only"
  - Alert timing explanation
- **Action buttons:** Save changes, Reset to defaults

**Status:**
- ✅ Price alerts toggle
- ✅ Store management (add/remove stores)
- ✅ Postal code input with validation
- ✅ Sale alerts + expiry reminder toggles
- ✅ Daily alert cap display
- ❌ Replenishment nudges toggle (separate from sale alerts)
- ❌ Weekly summary toggle
- ❌ Price Intelligence section (replenishment window calculation method)
- ❌ Reset to defaults button

---

## Screen 12 — Empty States

### Empty Home:
- Icon: shopping bag/cart
- "No items yet"
- "Scan your first receipt and SmartCart will start learning what you buy"
- "Set up stores & alerts" (primary) + "Scan a receipt" (secondary)

### Empty Alerts:
- Icon: bell
- "No alerts yet"
- "SmartCart will ping you when something you actually buy hits a genuine low"
- 3-bullet how-to card: scan receipts / add stores / turn on alerts
- "Scan a receipt" button

**Status:**
- ✅ `EmptyCTAView` exists on Home (scan receipt CTA)
- ❌ "Set up stores & alerts" button in empty Home state
- ❌ Empty Alerts screen (there's no Alerts screen at all)

---

## Feature Gap Summary

### P0 — Blocks core value proposition:
1. **Store selector on Scanner** — purchases can't be attributed to correct store without it
2. **Alerts & Deals tab** — primary discovery surface for deals is entirely missing
3. **Onboarding → store selection → permission flow** — first-run experience is incomplete

### P1 — High-value, wireframe-specified:
4. **Smart Insights grid on Item Detail** — avg cycle, usual price, sale frequency, stock-up qty
5. **Replenishment progress bar on Item Detail** — visual "how close to reorder"
6. **Purchase history list on Item Detail** — "My receipts for this item"
7. **Segment tabs on Home** — "My List" / "On Sale Now" (vs current stacked sections)
8. **Alert banner on Home** — "X deals active right now"
9. **Multi-store prices on Item Detail** — current prices nearby (Flipp data)
10. **Success sheet achievement pills** — post-scan delight moment

### P2 — Polish and completeness:
11. **Greeting header on Home** — "Good evening, [Name]"
12. **"Add to Shopping List" button on Item Detail** — secondary CTA
13. **History tab** — `PriceHistoryView` needs tab wiring
14. **Weekly summary notification toggle** in Settings
15. **Price intelligence settings** (calculation method for replenishment)
16. **Reset to defaults** in Settings
17. **Receipt Review totals header** — store, date, total, item count
18. **Discount % badge** on Item Detail sale price

---

## Data Requirements (already implemented in DB)

All 9 tables from the spec exist:
- ✅ `stores`, `user_stores`, `items`, `user_items`
- ✅ `purchase_history`, `price_history`
- ✅ `flyer_sales`, `alert_log`, `user_settings`
- ✅ `grocery_list` (added in this sprint)

Computed values needed for new screens:
- Avg purchase cycle per item → `purchase_history` grouped by `item_id`
- Sale frequency → `flyer_sales` count in rolling window
- Stock-up quantity → user override or `purchase_history` qty avg
- Multi-store current price → `flyer_sales` JOIN `stores` WHERE active

---

## Implementation Priority Order

```
Sprint 2:
  [P0-1] Store selector on Scanner
  [P0-2] Alerts & Deals tab (screen + tab wiring)
  [P1-1] Smart Insights grid on Item Detail

Sprint 3:
  [P1-2] Replenishment progress bar on Item Detail
  [P1-3] Purchase history list on Item Detail
  [P0-3] Onboarding flow (store selection + permission as steps)

Sprint 4:
  [P1-4] Segment tabs on Home
  [P1-5] Alert banner on Home
  [P2-1] Success sheet achievement pills
  [P2-2] History tab
```
