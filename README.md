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
├── Services/                   # FlippService, AlertEngine, ReceiptParser, BackgroundSync
├── Views/                      # SwiftUI screens and view models
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

## Build Status
| Task | Status |
|---|---|
| ATLAS — Architecture & Tech Spec | ✅ Complete |
| FORGE — Task #1 Scaffold (15 parts) | ✅ Complete |
| FORGE — Task #1-R1 Retroactive Fixes (6 issues) | ✅ Complete |
| PRISM — Task #1 QA Review (19 issues) | ✅ Complete |
| FORGE — Task #2 UI Screens (Parts 1–4) | 🟡 In Progress |

## Open Issues
See [GitHub Issues](../../issues) for all tracked P1 items.

## Non-Developer Notes
This project is built for vibe coding with Claude Code / Cursor. Every function has a plain-English comment. No clever abstractions. Every module is independently testable.
