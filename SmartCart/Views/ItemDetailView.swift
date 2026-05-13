// ItemDetailView.swift — SmartCart/Views/ItemDetailView.swift
//
// FIX #9 (Flipp Unavailability Badge):
//   FlippService writes "flipp_no_data_{itemID}" to user_settings when Flipp
//   has no data for this item. Previously, ItemDetailView never read that key,
//   so the Current Price section appeared silently empty — no explanation, no
//   retry path for the user.
//
//   Fix:
//     1. loadData() reads "flipp_no_data_{itemID}" from user_settings.
//        If the key exists, sets flippNoData = true.
//     2. When flippNoData == true, an amber inline badge is shown below the
//        current price HStack: "No price data found — tap to retry"
//     3. Tapping the badge:
//        a. Clears "flipp_no_data_{itemID}" from user_settings
//        b. Sets isRetrying = true (shows spinner, disables re-tap)
//        c. Calls FlippService.shared.fetchPrices(for:) for this item only
//        d. Calls loadData() to refresh price and re-check the flag
//     4. If the retry succeeds, flippNoData is false after loadData() and
//        the badge disappears automatically.
//     5. If Flipp still has no data, FlippService re-writes the key and
//        the badge reappears — user can retry again later.
//
// All prior fixes preserved:
//   P1-D: Functional wiring from HomeView and NotificationRouter
//   P1B-AlertSheet: three canonical alert types (A/B/C)
//   Part 9 fix: db.fetchStoreName(for:)

import SwiftUI
import Charts

struct ItemDetailView: View {

    let itemID: Int64

    @StateObject private var viewModel = PriceHistoryViewModel()
    @State private var selectedRange: ChartRange   = .thirtyDays
    @State private var showAlertSheet              = false
    @State private var showPurchaseToast           = false
    @State private var purchaseQty                 = 1

    // Flipp unavailability state (Fix #9)
    // flippNoData: true when "flipp_no_data_{itemID}" key is present in user_settings
    // isRetrying:  true while the async Flipp retry call is in-flight (shows spinner)
    @State private var flippNoData: Bool  = false
    @State private var isRetrying: Bool   = false

    private let db = DatabaseManager.shared

    @State private var item: UserItem?
    @State private var storeName: String     = ""
    @State private var currentPrice: Double? = nil

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {

                // MARK: Header
                VStack(alignment: .leading, spacing: 6) {
                    Text(item?.nameDisplay ?? "—")
                        .font(.title2.weight(.bold))
                    HStack(spacing: 12) {
                        Label(storeName, systemImage: "storefront")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                        if let date = item?.lastPurchasedDate {
                            Text("Last bought \(date.formatted(date: .abbreviated, time: .omitted))")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                    }
                    if let price = item?.lastPurchasedPrice {
                        Text("Paid $\(String(format: "%.2f", price))")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    if item?.isSeasonal == true {
                        Label("Seasonal item — restock alerts paused", systemImage: "snowflake")
                            .font(.caption)
                            .foregroundStyle(.blue)
                            .padding(.top, 2)
                    }
                }
                .padding()

                Divider()

                // MARK: Price history chart
                VStack(alignment: .leading, spacing: 8) {
                    Text("Price History")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 12)

                    Picker("Range", selection: $selectedRange) {
                        ForEach(ChartRange.allCases) { range in
                            Text(range.label).tag(range)
                        }
                    }
                    .pickerStyle(.segmented)
                    .padding(.horizontal)
                    .onChange(of: selectedRange) { _, r in
                        viewModel.load(itemID: itemID, range: r)
                    }

                    if viewModel.points.isEmpty {
                        Text("No price data yet.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding()
                    } else {
                        Chart(viewModel.points) { point in
                            LineMark(
                                x: .value("Date",  point.observedAt),
                                y: .value("Price", point.price)
                            )
                            .foregroundStyle(Color.accentColor)
                            AreaMark(
                                x: .value("Date",  point.observedAt),
                                y: .value("Price", point.price)
                            )
                            .foregroundStyle(Color.accentColor.opacity(0.12))
                        }
                        .chartYScale(domain: .automatic(includesZero: false))
                        .frame(height: 180)
                        .padding(.horizontal)
                    }
                }

                Divider().padding(.top, 8)

                // MARK: Current price
                VStack(alignment: .leading, spacing: 6) {
                    Text("Current Price")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 12)

                    HStack {
                        if let p = currentPrice {
                            Text("$\(String(format: "%.2f", p))")
                                .font(.title.weight(.semibold))
                            Text("at \(storeName)")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        } else {
                            Text("No current price available")
                                .font(.subheadline)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.horizontal)

                    // Flipp unavailability badge (Fix #9)
                    // Shown only when FlippService wrote a no-data marker for this item.
                    // Tapping clears the marker and retries the Flipp fetch immediately.
                    if flippNoData {
                        FlippUnavailableBadge(isRetrying: isRetrying) {
                            retryFlipp()
                        }
                        .padding(.horizontal)
                        .padding(.bottom, 4)
                    }
                }
                .padding(.bottom, flippNoData ? 0 : 12)

                Divider()

                // MARK: Alert status row
                Button {
                    showAlertSheet = true
                } label: {
                    HStack(spacing: 12) {
                        Image(systemName: alertBellIcon)
                            .foregroundStyle(Color.accentColor)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Alert Status")
                                .font(.subheadline.weight(.medium))
                                .foregroundStyle(.primary)
                            Text(alertStatusLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Image(systemName: "chevron.right")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                    .padding()
                }

                Divider()

                // MARK: Mark as Purchased
                VStack(alignment: .leading, spacing: 10) {
                    Text("Mark as Purchased")
                        .font(.headline)
                        .padding(.horizontal)
                        .padding(.top, 12)

                    HStack {
                        Text("Quantity")
                            .foregroundStyle(.secondary)
                        Spacer()
                        Stepper(
                            value: $purchaseQty, in: 1...99
                        ) {
                            Text("\(purchaseQty)")
                                .font(.body.monospacedDigit())
                        }
                        .fixedSize()
                    }
                    .padding(.horizontal)

                    Button {
                        confirmPurchase()
                    } label: {
                        Label("Confirm Purchase", systemImage: "cart.badge.plus")
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .padding(.horizontal)
                    .padding(.bottom, 16)
                }
            }
        }
        .navigationTitle(item?.nameDisplay ?? "Item Detail")
        .navigationBarTitleDisplayMode(.inline)
        .onAppear { loadData() }
        .sheet(isPresented: $showAlertSheet) {
            AlertSheet(itemID: itemID)
                .presentationDetents([.medium])
        }
        .overlay(alignment: .bottom) {
            if showPurchaseToast {
                Text("✅ Purchase recorded")
                    .font(.subheadline.weight(.medium))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(.regularMaterial, in: Capsule())
                    .padding(.bottom, 24)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.easeInOut(duration: 0.3), value: showPurchaseToast)
    }

    // MARK: - loadData()
    // Populates all view state from the database.
    // Fix #9: also reads "flipp_no_data_{itemID}" — sets flippNoData = true if present.
    // Called on appear and after confirmPurchase() or retryFlipp().
    private func loadData() {
        item         = db.fetchUserItem(itemID: itemID)
        let sid      = db.primaryStoreID(for: itemID) ?? 0
        storeName    = db.fetchStoreName(for: sid) ?? "Unknown Store"
        currentPrice = db.currentLowestPrice(for: itemID)
        viewModel.load(itemID: itemID, range: selectedRange)

        // Check whether FlippService flagged this item as having no data
        let noDataKey   = "flipp_no_data_\(itemID)"
        let noDataValue = db.getSetting(key: noDataKey)
        flippNoData     = (noDataValue != nil)
    }

    // MARK: - retryFlipp()
    // Called when the user taps the FlippUnavailableBadge.
    // Steps:
    //   1. Guard: do nothing if already retrying (prevents double-tap spam)
    //   2. Clear the no-data marker so we start fresh
    //   3. Set isRetrying = true (badge shows spinner)
    //   4. Fetch Flipp prices for this item only (async, wrapped in Task)
    //   5. Reload view data — if Flipp now has data, badge disappears;
    //      if Flipp wrote the key again, badge reappears for another retry
    private func retryFlipp() {
        guard !isRetrying else { return }
        isRetrying = true

        // Remove the no-data marker before fetching — FlippService will re-write
        // it if the retry still finds nothing, so we get a clean round-trip
        let noDataKey = "flipp_no_data_\(itemID)"
        db.setSetting(key: noDataKey, value: nil)

        Task {
            // Build a minimal UserItem array containing only this item,
            // so FlippService doesn't re-fetch the entire list
            if let userItem = db.fetchUserItem(itemID: itemID) {
                await FlippService.shared.fetchPrices(for: [userItem])
            }
            // Back on main actor to update UI
            await MainActor.run {
                isRetrying = false
                loadData()
            }
        }
    }

    private func confirmPurchase() {
        let price = currentPrice ?? item?.lastPurchasedPrice
        db.markPurchased(itemID: itemID, priceAtPurchase: price, quantity: purchaseQty)
        withAnimation { showPurchaseToast = true }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            withAnimation { showPurchaseToast = false }
        }
        loadData()
    }

    private var alertBellIcon: String {
        guard let i = item else { return "bell" }
        return i.hasActiveAlert ? "bell.badge.fill" : "bell"
    }

    private var alertStatusLabel: String {
        guard let i = item else { return "No active alert" }
        if i.hasActiveAlert { return "Active alert — tap to change type" }
        return "No active alert — tap to configure"
    }
}

// MARK: - FlippUnavailableBadge
// Amber inline badge shown in the Current Price section when FlippService
// has no data for this item.
//
// WHY A SEPARATE VIEW:
//   Keeps ItemDetailView.body readable — the badge has its own layout logic
//   (spinner vs. label swap) that would clutter the parent if inlined.
//
// isRetrying: when true, shows a ProgressView spinner instead of the text label.
//   The button is also disabled to prevent double-tap.
// onRetry: closure called when the user taps the badge (not called during retry).
private struct FlippUnavailableBadge: View {
    let isRetrying: Bool
    let onRetry: () -> Void

    var body: some View {
        Button(action: onRetry) {
            HStack(spacing: 8) {
                if isRetrying {
                    // Show spinner while fetch is in-flight
                    ProgressView()
                        .progressViewStyle(.circular)
                        .scaleEffect(0.8)
                    Text("Checking Flipp…")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                } else {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text("No price data found — tap to retry")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(.orange)
                }
                Spacer()
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color.orange.opacity(0.10), in: RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .strokeBorder(Color.orange.opacity(0.30), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .disabled(isRetrying)
        .animation(.easeInOut(duration: 0.2), value: isRetrying)
    }
}

// MARK: - Alert type picker sheet
// P1B: Exposes the three user-configurable types: A (Historical Low), B (Sale), C (Expiry).
// .combined is NOT shown here — it is engine-only, auto-fired when A+B are both active.
private struct AlertSheet: View {
    let itemID: Int64
    @State private var selection: AlertType = .historicalLow
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Alert Type") {
                    Picker("Type", selection: $selection) {
                        Text("Type A — Historical Low").tag(AlertType.historicalLow)
                        Text("Type B — Sale Alert").tag(AlertType.sale)
                        Text("Type C — Expiry Reminder").tag(AlertType.expiry)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Text(selection.userDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Text("Note: when both a Historical Low and a Sale are active at the same time, the engine automatically fires a combined alert — you don't need to configure this separately.")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
            }
            .navigationTitle("Configure Alert")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }
}

// MARK: - Chart range
enum ChartRange: String, CaseIterable, Identifiable {
    case thirtyDays  = "30d"
    case ninetyDays  = "90d"
    case oneYear     = "1yr"
    case all         = "All"

    var id: String { rawValue }
    var label: String { rawValue }

    var cutoffDate: Date? {
        let cal = Calendar.current
        switch self {
        case .thirtyDays:  return cal.date(byAdding: .day,  value: -30,  to: Date())
        case .ninetyDays:  return cal.date(byAdding: .day,  value: -90,  to: Date())
        case .oneYear:     return cal.date(byAdding: .year, value: -1,   to: Date())
        case .all:         return nil
        }
    }
}

// MARK: - AlertType user-facing description
// P1B: Renamed from `description` → `userDescription` to avoid shadowing CustomStringConvertible.
// The engine-only `.combined` case is included for completeness but not surfaced in AlertSheet.
extension AlertType {
    var userDescription: String {
        switch self {
        case .historicalLow:
            return "Fire when this item drops below its 90-day store average (Type A). Ideal for catching genuine long-term lows."
        case .sale:
            return "Fire when a flyer sale exceeds your minimum discount threshold (Type B). Fires once per sale event."
        case .expiry:
            return "Fire one day before a tracked sale ends (Type C). Reminds you to buy before the deal expires."
        case .combined:
            return "Engine-only: fires automatically when a sale (Type B) and a historical low (Type A) are both active simultaneously."
        }
    }
}
