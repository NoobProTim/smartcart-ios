// AlertsView.swift — SmartCart/Views/AlertsView.swift
//
// Alerts & Deals tab — shows every active deal and replenishment alert
// across the user's tracked items, with filter chips and per-card CTAs.

import SwiftUI
import Combine

// MARK: - AlertBadgeType

enum AlertBadgeType {
    case allTimeLow, onSale, runningLow, watching

    var label: String {
        switch self {
        case .allTimeLow:  return "ALL-TIME LOW"
        case .onSale:      return "ON SALE"
        case .runningLow:  return "RUNNING LOW"
        case .watching:    return "WATCHING"
        }
    }

    var color: Color {
        switch self {
        case .allTimeLow:  return .red
        case .onSale:      return .green
        case .runningLow:  return .blue
        case .watching:    return Color(.systemGray)
        }
    }

    var icon: String {
        switch self {
        case .allTimeLow:  return "arrow.down.circle.fill"
        case .onSale:      return "tag.fill"
        case .runningLow:  return "bell.fill"
        case .watching:    return "pin.fill"
        }
    }
}

// MARK: - AlertDeal

struct AlertDeal: Identifiable {
    let id = UUID()
    let item: UserItem
    let sale: FlyerSale?
    let badgeType: AlertBadgeType
    let storeName: String?

    var savings: Double? {
        guard let sale, let reg = sale.regularPrice else { return nil }
        return max(0, reg - sale.salePrice)
    }

    var discountPercent: Double? {
        sale?.discountPercent(fallbackRegularPrice: item.lastPurchasedPrice)
    }

    var replenishmentNote: String? {
        guard let days = item.daysUntilRestock else { return nil }
        if days <= 0 { return "Due now" }
        let goodTiming = (badgeType == .onSale || badgeType == .allTimeLow) && item.isInRestockWindow
        return "Due in ~\(days) day\(days == 1 ? "" : "s")\(goodTiming ? " · Good timing" : "")"
    }
}

// MARK: - AlertsViewModel

@MainActor
final class AlertsViewModel: ObservableObject {

    enum Filter: String, CaseIterable {
        case all        = "All"
        case onSale     = "On Sale"
        case runningLow = "Running Low"
        case watching   = "Watching"

        var icon: String {
            switch self {
            case .all:        return ""
            case .onSale:     return "🔥"
            case .runningLow: return "🔔"
            case .watching:   return "📌"
            }
        }
    }

    @Published var deals: [AlertDeal] = []
    @Published var dismissedIDs: Set<UUID> = []
    @Published var activeFilter: Filter = .all

    private let db = DatabaseManager.shared

    var visibleDeals: [AlertDeal] {
        let active = deals.filter { !dismissedIDs.contains($0.id) }
        switch activeFilter {
        case .all:        return active
        case .onSale:     return active.filter { $0.badgeType == .onSale || $0.badgeType == .allTimeLow }
        case .runningLow: return active.filter { $0.badgeType == .runningLow }
        case .watching:   return active.filter { $0.badgeType == .watching }
        }
    }

    var onSaleCount: Int   { deals.filter { $0.badgeType == .onSale || $0.badgeType == .allTimeLow }.count }
    var runningLowCount: Int { deals.filter { $0.badgeType == .runningLow }.count }
    var watchingCount: Int { deals.filter { $0.badgeType == .watching }.count }

    var potentialSavings: Double {
        deals.filter { !dismissedIDs.contains($0.id) }.compactMap { $0.savings }.reduce(0, +)
    }

    func count(for filter: Filter) -> Int {
        switch filter {
        case .all:        return deals.filter { !dismissedIDs.contains($0.id) }.count
        case .onSale:     return onSaleCount
        case .runningLow: return runningLowCount
        case .watching:   return watchingCount
        }
    }

    func load() {
        Task {
            let items = db.fetchUserItems()
            var result: [AlertDeal] = []
            var coveredIDs: Set<Int64> = []

            for item in items {
                let sales = db.fetchActiveSales(for: item.itemID)
                if let sale = sales.first {
                    let low = db.historicalLow(for: item.itemID)
                    let isAtLow = low.map { sale.salePrice <= $0.price + 0.01 } ?? false
                    let badge: AlertBadgeType = isAtLow ? .allTimeLow : .onSale
                    let name = db.fetchStoreName(for: sale.storeID)
                    result.append(AlertDeal(item: item, sale: sale, badgeType: badge, storeName: name))
                    coveredIDs.insert(item.itemID)
                }
            }

            for item in items where !coveredIDs.contains(item.itemID) {
                if item.isInRestockWindow {
                    result.append(AlertDeal(item: item, sale: nil, badgeType: .runningLow, storeName: nil))
                    coveredIDs.insert(item.itemID)
                } else if item.hasActiveAlert {
                    result.append(AlertDeal(item: item, sale: nil, badgeType: .watching, storeName: nil))
                    coveredIDs.insert(item.itemID)
                }
            }

            // All-time lows first, then on-sale, then running low, then watching
            result.sort { lhs, rhs in
                let priority: (AlertBadgeType) -> Int = {
                    switch $0 { case .allTimeLow: 0; case .onSale: 1; case .runningLow: 2; case .watching: 3 }
                }
                return priority(lhs.badgeType) < priority(rhs.badgeType)
            }

            deals = result
        }
    }

    func addToList(_ deal: AlertDeal) {
        db.addToGroceryList(itemID: deal.item.itemID, expectedPrice: deal.sale?.salePrice)
    }

    func dismiss(_ deal: AlertDeal) {
        withAnimation { dismissedIDs.insert(deal.id) }
    }
}

// MARK: - AlertsView

struct AlertsView: View {
    @StateObject private var vm = AlertsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if vm.deals.isEmpty {
                    AlertsEmptyView()
                } else {
                    alertsContent
                }
            }
            .navigationTitle("Alerts & Deals")
            .navigationBarTitleDisplayMode(.large)
        }
        .onAppear { vm.load() }
    }

    private var alertsContent: some View {
        ScrollView {
            LazyVStack(spacing: 0, pinnedViews: [.sectionHeaders]) {
                // Summary banner
                if !vm.visibleDeals.isEmpty {
                    summaryBanner
                        .padding(.horizontal, 16)
                        .padding(.top, 12)
                        .padding(.bottom, 4)
                }

                // Filter chips
                Section(header: filterChipsRow) {
                    if vm.visibleDeals.isEmpty {
                        emptyFilterState
                    } else {
                        ForEach(vm.visibleDeals) { deal in
                            AlertCardView(deal: deal,
                                          onAddToList: { vm.addToList(deal) },
                                          onDismiss:   { vm.dismiss(deal) })
                            .padding(.horizontal, 16)
                            .padding(.bottom, 10)
                        }
                    }
                }

                // Preferences footer
                alertPreferences
                    .padding(.horizontal, 16)
                    .padding(.top, 8)
                    .padding(.bottom, 32)
            }
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: Summary banner

    private var summaryBanner: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text("\(vm.count(for: .all)) genuine deal\(vm.count(for: .all) == 1 ? "" : "s") right now")
                    .font(.system(size: 15, weight: .semibold))
                Text("All timed to your replenishment cycles")
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }
            Spacer()
            if vm.potentialSavings > 0 {
                VStack(alignment: .trailing, spacing: 2) {
                    Text(vm.potentialSavings, format: .currency(code: "CAD"))
                        .font(.system(size: 17, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(.green)
                    Text("potential savings")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.04), radius: 2, y: 1)
    }

    // MARK: Filter chips

    private var filterChipsRow: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(AlertsViewModel.Filter.allCases, id: \.self) { filter in
                    let count = vm.count(for: filter)
                    if filter == .all || count > 0 {
                        filterChip(filter: filter, count: count)
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
        .background(Color(.systemGroupedBackground))
    }

    private func filterChip(filter: AlertsViewModel.Filter, count: Int) -> some View {
        let isActive = vm.activeFilter == filter
        let label = filter.icon.isEmpty
            ? "\(filter.rawValue) (\(count))"
            : "\(filter.icon) \(filter.rawValue) (\(count))"
        return Button { withAnimation(.easeInOut(duration: 0.18)) { vm.activeFilter = filter } } label: {
            Text(label)
                .font(.system(size: 13, weight: isActive ? .semibold : .regular))
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isActive ? Color.accentColor : Color(.secondarySystemGroupedBackground))
                .foregroundStyle(isActive ? .white : .primary)
                .clipShape(Capsule())
                .shadow(color: isActive ? Color.accentColor.opacity(0.25) : .clear, radius: 4, y: 2)
        }
        .buttonStyle(.plain)
    }

    // MARK: Empty filter state

    private var emptyFilterState: some View {
        VStack(spacing: 10) {
            Image(systemName: vm.activeFilter == .onSale ? "tag" : "bell")
                .font(.system(size: 36))
                .foregroundStyle(.secondary)
            Text("No \(vm.activeFilter.rawValue.lowercased()) alerts right now")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 40)
    }

    // MARK: Alert preferences footer

    @State private var priceDropAlertsOn = true
    @State private var replenishmentAlertsOn = true
    @State private var alignedAlertsOnly = false

    private var alertPreferences: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Alert Preferences")
                .font(.system(size: 11, weight: .semibold).smallCaps())
                .foregroundStyle(.secondary)
                .padding(.bottom, 10)

            VStack(spacing: 0) {
                Toggle("Price Drop Alerts", isOn: $priceDropAlertsOn)
                    .font(.system(size: 15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onChange(of: priceDropAlertsOn) {
                        DatabaseManager.shared.setSetting(key: "sale_alerts_enabled", value: priceDropAlertsOn ? "1" : "0")
                    }

                Divider().padding(.leading, 16)

                Toggle("Replenishment Alerts", isOn: $replenishmentAlertsOn)
                    .font(.system(size: 15))
                    .padding(.horizontal, 16)
                    .padding(.vertical, 12)
                    .onChange(of: replenishmentAlertsOn) {
                        DatabaseManager.shared.setSetting(key: "replenishment_alerts_enabled", value: replenishmentAlertsOn ? "1" : "0")
                    }

                Divider().padding(.leading, 16)

                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Toggle("Quiet Hours", isOn: .constant(true))
                            .font(.system(size: 15))
                            .disabled(true)
                        Text("10 PM – 7 AM")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)

                Divider().padding(.leading, 16)

                Toggle(isOn: $alignedAlertsOnly) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Smart Timing")
                            .font(.system(size: 15))
                        Text("Only alert when sale + replenishment align")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .onChange(of: alignedAlertsOnly) {
                    DatabaseManager.shared.setSetting(key: "sale_alert_restock_only", value: alignedAlertsOnly ? "1" : "0")
                }
            }
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .onAppear {
            priceDropAlertsOn      = DatabaseManager.shared.getSetting(key: "sale_alerts_enabled")          != "0"
            replenishmentAlertsOn  = DatabaseManager.shared.getSetting(key: "replenishment_alerts_enabled") != "0"
            alignedAlertsOnly      = DatabaseManager.shared.getSetting(key: "sale_alert_restock_only")       == "1"
        }
    }
}

// MARK: - AlertCardView

struct AlertCardView: View {
    let deal: AlertDeal
    let onAddToList: () -> Void
    let onDismiss: () -> Void

    @State private var addedToList = false
    @State private var addTrigger = 0

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header row: emoji + name + badge
            HStack(alignment: .center, spacing: 12) {
                ZStack {
                    RoundedRectangle(cornerRadius: 10)
                        .fill(deal.badgeType.color.opacity(0.12))
                        .frame(width: 44, height: 44)
                    Text(groceryEmoji(for: deal.item.nameDisplay))
                        .font(.system(size: 24))
                }

                VStack(alignment: .leading, spacing: 3) {
                    Text(deal.item.nameDisplay)
                        .font(.system(size: 15, weight: .semibold))
                        .lineLimit(1)
                    HStack(spacing: 6) {
                        if let store = deal.storeName {
                            Text(store)
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        if let days = deal.sale?.expiresInDays() {
                            Text(days == 0 ? "Ends today" : "Ends in \(days)d")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                Spacer()

                Text(deal.badgeType.label)
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(deal.badgeType.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 3)
                    .background(deal.badgeType.color.opacity(0.10))
                    .clipShape(Capsule())
            }
            .padding(.horizontal, 14)
            .padding(.top, 14)
            .padding(.bottom, 10)

            // Price row
            if let sale = deal.sale {
                HStack(alignment: .firstTextBaseline, spacing: 8) {
                    Text(sale.salePrice, format: .currency(code: "CAD"))
                        .font(.system(size: 20, weight: .bold))
                        .monospacedDigit()
                        .foregroundStyle(deal.badgeType.color)

                    if let reg = sale.regularPrice {
                        Text(reg, format: .currency(code: "CAD"))
                            .font(.system(size: 14))
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                            .strikethrough(true, color: .secondary)
                    }

                    Spacer()

                    if let pct = deal.discountPercent {
                        Text("−\(Int(pct))%")
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundStyle(.white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(deal.badgeType.color)
                            .clipShape(Capsule())
                    }

                    if let savings = deal.savings, savings > 0 {
                        Text("Save \(savings, format: .currency(code: "CAD"))")
                            .font(.system(size: 12))
                            .foregroundStyle(.secondary)
                    }
                }
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            // Replenishment note
            if let note = deal.replenishmentNote {
                HStack(spacing: 5) {
                    Image(systemName: "clock")
                        .font(.system(size: 11))
                    Text(note)
                        .font(.system(size: 12))
                }
                .foregroundStyle(.secondary)
                .padding(.horizontal, 14)
                .padding(.bottom, 10)
            }

            Divider()

            // CTA row
            HStack(spacing: 0) {
                Button(action: onDismiss) {
                    Text("Dismiss")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 11)
                }

                Divider().frame(height: 36)

                Button {
                    if !addedToList {
                        onAddToList()
                        withAnimation { addedToList = true }
                        addTrigger += 1
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: addedToList ? "checkmark" : "cart.badge.plus")
                            .font(.system(size: 13))
                        Text(addedToList ? "Added" : "Add to List")
                            .font(.system(size: 14, weight: .medium))
                    }
                    .foregroundStyle(addedToList ? .green : Color.accentColor)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 11)
                }
                .sensoryFeedback(.success, trigger: addTrigger)
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(color: .black.opacity(0.05), radius: 3, y: 1)
    }
}

// MARK: - AlertsEmptyView

struct AlertsEmptyView: View {
    var body: some View {
        VStack(spacing: 20) {
            Spacer()
            Image(systemName: "bell.slash")
                .font(.system(size: 52))
                .foregroundStyle(.secondary)
            VStack(spacing: 6) {
                Text("No alerts yet")
                    .font(.title3.weight(.semibold))
                Text("SmartCart will ping you when something you\nactually buy hits a genuine low.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 10) {
                Label("Scan a receipt to start tracking prices", systemImage: "doc.viewfinder")
                Label("Add stores in Settings", systemImage: "storefront")
                Label("Turn on notifications when prompted", systemImage: "bell")
            }
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .padding(.top, 8)
            Spacer()
            Spacer()
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Emoji helper

private func groceryEmoji(for name: String) -> String {
    let n = name.lowercased()
    if n.contains("milk") || n.contains("cream")          { return "🥛" }
    if n.contains("butter")                                { return "🧈" }
    if n.contains("egg")                                   { return "🥚" }
    if n.contains("bread") || n.contains("bun")           { return "🍞" }
    if n.contains("chicken") || n.contains("poultry")     { return "🍗" }
    if n.contains("beef") || n.contains("steak")          { return "🥩" }
    if n.contains("pork") || n.contains("bacon")          { return "🥓" }
    if n.contains("fish") || n.contains("salmon")         { return "🐟" }
    if n.contains("apple")                                 { return "🍎" }
    if n.contains("banana")                                { return "🍌" }
    if n.contains("orange")                                { return "🍊" }
    if n.contains("cheese")                                { return "🧀" }
    if n.contains("yogurt") || n.contains("yoghurt")      { return "🍶" }
    if n.contains("coffee")                                { return "☕️" }
    if n.contains("water")                                 { return "💧" }
    if n.contains("juice")                                 { return "🧃" }
    if n.contains("pasta") || n.contains("noodle")        { return "🍝" }
    if n.contains("rice")                                  { return "🍚" }
    if n.contains("tomato")                                { return "🍅" }
    if n.contains("potato") || n.contains("fries")        { return "🥔" }
    if n.contains("onion")                                 { return "🧅" }
    if n.contains("carrot")                                { return "🥕" }
    if n.contains("lettuce") || n.contains("salad")       { return "🥗" }
    if n.contains("cereal") || n.contains("oat")          { return "🥣" }
    if n.contains("soap") || n.contains("detergent")      { return "🧼" }
    return "🛒"
}
