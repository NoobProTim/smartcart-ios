// AlertDetailView.swift
// SmartCart — Views/AlertDetailView.swift
//
// Shown when the user taps a push notification OR an alert row in a future Alerts tab.
// Displays:
//   - Item name + alert type label
//   - Alert price vs. 90-day rolling average (with % savings)
//   - Store name
//   - Mark as Purchased CTA
//
// Navigation: deep-linked via smartcart://alert?itemID=N&alertLogID=M
// The alertLogID uniquely identifies the alert_log row so we can show
// the exact price and type that triggered this notification.

import SwiftUI

// MARK: - AlertDetailViewModel

@MainActor
final class AlertDetailViewModel: ObservableObject {

    let itemID: Int64
    let alertLogID: Int64  // alert_log.id — identifies the specific alert event

    @Published var displayName    = ""
    @Published var alertType: String? = nil  // 'historical_low' | 'sale' | 'expiry' | 'combined'
    @Published var alertPrice: Double? = nil
    @Published var rollingAverage: Double? = nil
    @Published var storeName: String? = nil
    @Published var saleEndDate: String? = nil  // for expiry alerts
    @Published var isLoading       = true
    @Published var showMarkPurchased = false
    @Published var purchaseConfirmed = false

    // Percentage saving vs. rolling average. Nil if no average data.
    var savingPercent: Double? {
        guard let price = alertPrice, let avg = rollingAverage, avg > 0 else { return nil }
        return ((avg - price) / avg) * 100
    }

    // Human-readable alert type label for display.
    var alertTypeLabel: String {
        switch alertType {
        case "historical_low": return "📉 Historical Low"
        case "sale":           return "🏷️ On Sale"
        case "expiry":         return "⏰ Sale Ending Soon"
        case "combined":       return "📉🏷️ Historical Low + Sale"
        default:               return "Price Alert"
        }
    }

    // Accent colour per alert type.
    var alertTypeColor: Color {
        switch alertType {
        case "historical_low", "combined": return .red
        case "expiry":                     return .orange
        default:                           return Color.accentColor
        }
    }

    init(itemID: Int64, alertLogID: Int64) {
        self.itemID     = itemID
        self.alertLogID = alertLogID
    }

    /// Loads item name, alert record, and rolling average from SQLite.
    func load() {
        isLoading = true
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }

            // Fetch alert_log row for this specific alert event
            let alertRow  = DatabaseManager.shared.fetchAlertLogRow(alertLogID: self.alertLogID)
            let items     = DatabaseManager.shared.fetchUserItems()
            let name      = items.first(where: { $0.itemID == self.itemID })?.displayName ?? "Item"
            let stores    = DatabaseManager.shared.fetchSelectedStores()
            let storeName = alertRow.flatMap { row in
                stores.first(where: { $0.id == row.storeID })?.name
            }

            // Rolling average from the first store with sufficient data
            var avg: Double? = nil
            for store in stores {
                if let a = DatabaseManager.shared.rollingAverage90(itemID: self.itemID, storeID: store.id) {
                    avg = a; break
                }
            }

            // Sale end date: look up the linked flyer_sales row if this is a sale/expiry alert
            var endDate: String? = nil
            if let row = alertRow, let saleEventID = row.saleEventID {
                endDate = DatabaseManager.shared.fetchSaleEndDate(saleEventID: saleEventID)
                    .flatMap { DateHelper.friendlyDate($0) }
            }

            await MainActor.run {
                self.displayName    = name
                self.alertType      = alertRow?.alertType
                self.alertPrice     = alertRow?.triggerPrice
                self.rollingAverage = avg
                self.storeName      = storeName
                self.saleEndDate    = endDate
                self.isLoading      = false
            }
        }
    }

    /// Records a purchase at the alert price and dismisses.
    func markAsPurchased(dismissAction: @escaping () -> Void) {
        guard let price = alertPrice else { return }
        Task.detached(priority: .userInitiated) { [weak self] in
            guard let self else { return }
            let today = DateHelper.todayString()
            DatabaseManager.shared.insertPurchase(
                itemID: self.itemID, storeID: nil, price: price, date: today, source: "alert")
            await MainActor.run {
                self.purchaseConfirmed = true
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { dismissAction() }
            }
        }
    }
}

// MARK: - AlertDetailView

struct AlertDetailView: View {
    @StateObject private var vm: AlertDetailViewModel
    @Environment(\.dismiss) private var dismiss

    init(itemID: Int64, alertLogID: Int64) {
        _vm = StateObject(wrappedValue: AlertDetailViewModel(itemID: itemID, alertLogID: alertLogID))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView("Loading alert…")
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else if vm.purchaseConfirmed {
                    // Post-purchase celebration state
                    VStack(spacing: 16) {
                        Image(systemName: "cart.fill.badge.plus")
                            .font(.system(size: 56)).foregroundStyle(Color.accentColor)
                        Text("Purchase recorded!")
                            .font(.system(size: 20, weight: .bold))
                        Text("Price history updated.")
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    alertBody
                }
            }
            .navigationTitle(vm.displayName)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .onAppear { vm.load() }
    }

    // MARK: Alert body
    private var alertBody: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {

                // Alert type pill
                Text(vm.alertTypeLabel)
                    .font(.system(size: 13, weight: .semibold))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(vm.alertTypeColor.opacity(0.12))
                    .foregroundStyle(vm.alertTypeColor)
                    .clipShape(Capsule())

                // Price vs. average card
                priceCard

                // Store name
                if let store = vm.storeName {
                    HStack(spacing: 6) {
                        Image(systemName: "mappin.circle")
                            .foregroundStyle(.secondary)
                        Text(store)
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                }

                // Sale expiry date (expiry / combined alert types)
                if let end = vm.saleEndDate {
                    HStack(spacing: 6) {
                        Image(systemName: "calendar.badge.clock")
                            .foregroundStyle(.orange)
                        Text("Sale ends \(end)")
                            .font(.system(size: 15)).foregroundStyle(.orange)
                    }
                }

                Spacer(minLength: 32)

                // Mark as Purchased CTA
                Button(action: { vm.markAsPurchased { dismiss() } }) {
                    Text("Mark as Purchased")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .disabled(vm.alertPrice == nil)
            }
            .padding(20)
        }
    }

    // MARK: Price card
    // Shows alert price on the left, rolling average on the right, savings chip centred below.
    private var priceCard: some View {
        VStack(spacing: 12) {
            HStack {
                // Alert price
                VStack(alignment: .leading, spacing: 4) {
                    Text("Today's price")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    if let price = vm.alertPrice {
                        Text(String(format: "$%.2f", price))
                            .font(.system(size: 28, weight: .bold))
                            .foregroundStyle(vm.alertTypeColor)
                    } else {
                        Text("—")
                            .font(.system(size: 28, weight: .bold)).foregroundStyle(.secondary)
                    }
                }
                Spacer()
                // Rolling average
                VStack(alignment: .trailing, spacing: 4) {
                    Text("90-day avg")
                        .font(.system(size: 12)).foregroundStyle(.secondary)
                    if let avg = vm.rollingAverage {
                        Text(String(format: "$%.2f", avg))
                            .font(.system(size: 22, weight: .semibold)).foregroundStyle(.secondary)
                    } else {
                        Text("No data")
                            .font(.system(size: 15)).foregroundStyle(.secondary)
                    }
                }
            }

            // % savings chip — only shown when we have both values
            if let pct = vm.savingPercent, pct > 0 {
                HStack(spacing: 4) {
                    Image(systemName: "arrow.down")
                    Text(String(format: "%.0f%% below average", pct))
                        .font(.system(size: 13, weight: .semibold))
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12).padding(.vertical, 6)
                .background(Color.green)
                .clipShape(Capsule())
            }
        }
        .padding(16)
        .background(Color(.systemGray6))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

// MARK: - Preview
#Preview {
    AlertDetailView(itemID: 1, alertLogID: 1)
}
