// ItemDetailView.swift — SmartCart/Views/ItemDetailView.swift
// P1-D: Functional ItemDetailView wired from HomeView and NotificationRouter.
// P1B-AlertSheet: Picker now exposes the three canonical types (A/B/C).
//   historicalLow (A), sale (B), expiry (C) — all selectable by the user.
//   .combined is engine-only (auto-merged when A+B both active); not shown as a user option.
// Part 9 fix: db.storeName(for:) → db.fetchStoreName(for:) in loadData()

import SwiftUI
import Charts

struct ItemDetailView: View {

    let itemID: Int64

    @StateObject private var viewModel = PriceHistoryViewModel()
    @State private var selectedRange: ChartRange = .thirtyDays
    @State private var showAlertSheet            = false
    @State private var showPurchaseToast         = false
    @State private var purchaseQty               = 1

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
                    .padding(.bottom, 12)
                }

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

    // MARK: - Helpers
    private func loadData() {
        item         = db.fetchUserItem(itemID: itemID)
        let sid      = db.primaryStoreID(for: itemID) ?? 0
        // Fix: was db.storeName(for:) — renamed to db.fetchStoreName(for:) in Part 7
        storeName    = db.fetchStoreName(for: sid) ?? "Unknown Store"
        currentPrice = db.currentLowestPrice(for: itemID)
        viewModel.load(itemID: itemID, range: selectedRange)
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
                    // A — Historical Low
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
