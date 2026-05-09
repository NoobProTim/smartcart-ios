// ItemDetailView.swift — SmartCart/Views/ItemDetailView.swift
// P1-D: Functional replacement for the Part 7 WIP stub.
// Wired from HomeView itemList NavigationLinks and NotificationRouter deep-links.
// Design reference: Batch 3, Screen 7 wireframe.

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
                    // P1-E: Seasonal badge
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
        storeName    = db.storeName(for: sid) ?? "Unknown Store"
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
private struct AlertSheet: View {
    let itemID: Int64
    @State private var selection: AlertType = .sale
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Alert Type") {
                    Picker("Type", selection: $selection) {
                        Text("Historical Low (Type A)").tag(AlertType.historicalLow)
                        Text("Sale Alert (Type B)").tag(AlertType.sale)
                        Text("Sale + Low Combined").tag(AlertType.combined)
                    }
                    .pickerStyle(.inline)
                    .labelsHidden()
                }
                Section {
                    Text(selection.description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
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

// MARK: - AlertType description helper
extension AlertType {
    var description: String {
        switch self {
        case .historicalLow: return "Fire when this item drops below its 90-day average price."
        case .sale:          return "Fire when a flyer sale exceeds your minimum discount threshold."
        case .expiry:        return "Fire one day before a tracked sale ends."
        case .combined:      return "Fire only when both a price low AND a sale are active simultaneously."
        }
    }
}
