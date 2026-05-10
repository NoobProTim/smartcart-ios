# SmartCart — iOS Grocery Price Intelligence

SmartCart is a local-first iOS app that learns what you buy from scanned receipts, tracks price history across your favourite grocery stores, and alerts you when a tracked item hits a genuine low — timed to your replenishment cycle.

## Tech Stack
- **SwiftUI** + Xcode (iOS 16+)
- **SQLite.swift** 0.15.x — local on-device database
- **Apple Vision** (`VNRecognizeTextRequest`) — on-device OCR for receipt scanning
- **Swift Charts** — price history graphs
- **UserNotifications** + **BGAppRefreshTask** — push alerts and background sync
- **Flipp API** (`backflipp.wishabi.com`) — flyer and sale price data
- **$0/month** — no server, no paid APIs beyond existing Claude Code subscription

## Project Structure
```
SmartCart/
├── SmartCartApp.swift          # App entry point, notification router
├── Models/                     # Pure Swift value types (1:1 with DB tables)
├── Database/                   # Schema DDL + DatabaseManager (all DB reads/writes)
├── Engine/                     # ReplenishmentEngine (restock cycle brain)
├── Services/                   # FlippService, AlertEngine, ReceiptParser, BackgroundSync
├── Views/                      # SwiftUI screens
├── ViewModels/                 # HomeViewModel and other ObservableObjects
└── Utilities/                  # DateHelper, NameNormaliser, Constants
```

## Database Schema (9 tables)
`stores` · `items` · `user_items` · `purchase_history` · `price_history` · `flyer_sales` · `alert_log` · `user_stores` · `user_settings`

## Alert Types
- **Type A — Historical Low**: price ≤ 90-day rolling avg × 0.85, within restock window
- **Type B — Sale Alert**: active flyer event meeting user discount threshold
- **Type C — Expiry Reminder**: sale ending within N days, item not yet purchased
- **Combined**: A + B merge into one notification when both fire for the same item
- **Cap**: max 3 alerts/day, sorted by priority

## How Replenishment Works

SmartCart learns your shopping rhythm automatically — you never set a manual reminder.

**Cycle calculation**

Every time you scan a receipt (or tap “Mark as Purchased”), the app records the date and quantity in `purchase_history`. `ReplenishmentEngine` looks at your last two purchases of the same item and computes the average gap in days. That gap becomes your *replenishment cycle*.

- First purchase: no cycle yet — the item shows “No restock estimate”.
- Second purchase onward: the cycle is live and updates after every new purchase.
- The predicted restock date (`user_items.next_restock_date`) is written back to the database immediately.

**Bulk quantity scaling**

If you buy 2 or more units of an item at once, the engine multiplies the base cycle by the quantity. Buying 2 packs of paper towels extends the predicted restock date proportionally — you won’t get an alert until you’re actually running low.

**Seasonal suppression**

Items flagged `is_seasonal = 1` (e.g. holiday ham, pumpkin spice anything) have their restock alerts paused outside of their seasonal window. The engine detects seasonality automatically from your purchase history: if all purchases of an item fall within a 90-day band of the calendar year, it is marked seasonal. Alerts resume when the season approaches again.

**Restock badge states**

Every item in the Smart List carries a coloured badge driven by `ReplenishmentEngine.restockStatus(for:)`:

| Badge | Colour | Meaning |
|---|---|---|
| Due | Red | Predicted restock date has passed or is today |
| Soon | Orange | Restock is within the next 3 days |
| OK | None | Plenty of time remaining |
| Seasonal | Blue snowflake | Alerts paused — outside seasonal window |

**Alert gating**

`AlertEngine` delegates all restock-window checks to `ReplenishmentEngine.isInRestockWindow(for:)`. A Type A or Type B alert is only fired if the item is within its restock window — preventing price-drop notifications for things you’ve just bought and don’t need yet.

## Build Status
| Task | Status |
|---|---|
| ATLAS — Architecture & Tech Spec | ✅ Complete |
| FORGE — Task #1 Scaffold | ✅ Complete |
| FORGE — Task #1-R1 Retroactive Fixes | ✅ Complete |
| PRISM — Task #1 QA Review | ✅ Complete |
| FORGE — Task #2 Replenishment Engine (Parts 1–6) | ✅ Complete |

## Open Issues
See [GitHub Issues](../../issues) for all tracked P1 items.

## Non-Developer Notes
This project is built for vibe coding with Claude Code / Cursor. Every function has a plain-English comment. No clever abstractions. Every module is independently testable.
