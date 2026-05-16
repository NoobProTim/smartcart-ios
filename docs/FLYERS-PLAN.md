# Flyers Feature — Architecture Plan & Compliance Notes

## Status
- Current build: Flipp API (undocumented endpoint) — deal search working
- Next build: Flyer browser — **PAUSED pending compliance review**

---

## Compliance Assessment

**Commercial use is permitted.** Flipp's ToS allows building commercial apps that integrate
Flipp data, including charging users, as long as the app does not compete with Flipp's core
service (a deal aggregator / flyer marketplace).

SmartCart is clearly non-competing:
- Flipp: discover and browse deals across all stores for any shopper
- SmartCart: personal grocery assistant that tracks your list, your stores, your history

**The ToS test — "substantially the same functionality":**

| Flipp's core product | SmartCart |
|---|---|
| Public deal discovery for all shoppers | Personal shopping list for one user |
| Full flyer catalogue, all stores | Deals filtered to user's chosen stores |
| Marketplace / ad-driven | Personal finance / budgeting tool |

SmartCart does not replicate Flipp's functionality. Commercial use is on solid ground.

**What IS prohibited (does not apply to SmartCart):**
- Building a competing deal aggregator or white-label flyer marketplace ✗
- Reverse engineering or decompiling Flipp's services ✗
- Removing Flipp/Wishabi attribution and IP notices ✗

**One remaining action — written confirmation:**
Before App Store submission, get written confirmation from Flipp that SmartCart's specific
use case is approved. This is standard practice for any commercial API dependency —
not because it's in doubt, but to have it on record. See email draft below.

---

## Draft Email to Flipp Legal

**To:** legal@flipp.com
**CC:** hello@wishabi.com
**Subject:** Use Case Confirmation — SmartCart iOS (Personal Grocery Assistant)

Hi Flipp Team,

My name is Timothy Joshua. I'm building SmartCart, a personal grocery shopping assistant for iOS, and I'd like written confirmation that my planned use of Flipp data falls within your approved use cases before I submit to the App Store.

**What SmartCart does:**
SmartCart is a personal finance tool for individual grocery shoppers — not a deal platform or marketplace. Users build a private shopping list, track their purchase history, and see when items on their list are on sale at the stores they already shop at. The app is a budgeting and list management tool.

**How I plan to use Flipp data:**
- Query deal and pricing data to show users the current best price for items on their personal shopping list, filtered to their chosen stores
- Display the relevant store's flyer so users can browse the circular in context
- Follow the integration patterns from your official iOS SDK
- Preserve all Flipp copyright and trademark notices in the UI, with Flipp attribution displayed whenever deal or pricing data is shown

**Why I believe this is within your ToS:**
SmartCart does not perform substantially the same functionality as Flipp. It does not aggregate deals for general discovery, run a marketplace, or serve ads. It is a single-user personal tool that uses Flipp data as a data source, not as a product.

I've reviewed your Storefronts ToS and your official GitHub SDK examples. I'm confident this use case is compliant and simply want written confirmation before shipping commercially.

I'm planning to submit to the App Store in 8–10 weeks, so confirmation by mid-June would be helpful.

Could you confirm that the above use case is approved, or let me know if there's a formal developer agreement I should sign?

Thank you,
Timothy Joshua
ntim90@gmail.com

---

## Architecture Plan

### Phase 1 — Current (Flipp search API)
- `FlippService.fetchPopularDeals()` — parallel search for 15 grocery terms
- Results filtered to user's selected stores
- Displayed as deal carousel + category-filtered list in FlyersView
- `FlyerDeal` model carries `flyerId`, `validFrom`, `validTo`, `storeName`

### Phase 2 — Flyer Browser (build after compliance confirmed)
- Fetch active flyers for user's stores + postal code via Flipp flyer endpoint
- Display flyer pages as a native SwiftUI paged image viewer
- Cache flyer images to disk on first fetch (works offline after that)
- New SQLite table: `flyers` (store_id, valid_from, valid_to, page_count, cache_path)
- Show "last updated X days ago" banner if cache is stale and network unavailable

### Phase 3 — Source independence (resilience)
Abstract data fetching behind a `FlyerProvider` protocol so Flipp can be swapped:

```swift
protocol FlyerProvider {
    func fetchDeals(postalCode: String, stores: [String]) async -> [FlyerDeal]
    func fetchFlyerPages(flyerId: String, store: String) async -> [URL]
}
```

**Alternative providers if Flipp becomes unavailable:**
- **Reebee** (reebee.com) — Canadian flyer aggregator, has an API
- **Save.ca** — Canadian coupon/flyer platform
- **Direct store PDFs** — FreshCo, No Frills, and Loblaws publish weekly flyer
  PDFs at predictable URLs (can be downloaded and rendered with PDFKit)
- **Manual import** — let users photograph or import a flyer PDF from Files app

### Phase 4 — Offline-first cache
- Background refresh every 24h when on WiFi
- All fetched flyer images stored in `Caches/flyers/{flyerId}/page_{n}.jpg`
- SQLite tracks last-fetched timestamp per flyer
- UI always serves from cache; network fetch is a background update

---

## File Locations

| File | Purpose |
|---|---|
| `Services/FlippService.swift` | Current Flipp API integration |
| `Models/FlyerDeal.swift` | Deal model with flyerId, validFrom, validTo |
| `Views/FlyersView.swift` | Deal carousel + category list UI |
| `ViewModels/FlyersViewModel.swift` | Filtering, search, addToCart logic |
| `Services/FlyerProvider.swift` | (Phase 3) Protocol abstraction — not yet built |
| `Services/FlyerCacheService.swift` | (Phase 2) Disk cache manager — not yet built |

---

## Open Questions

- [ ] Flipp legal response — compliant use confirmed?
- [ ] Is there an official Flipp developer program / licensed API?
- [ ] Which alternative provider (Reebee, Save.ca) has the best Canadian coverage?
- [ ] PDFKit rendering quality for store-published flyer PDFs — test needed
