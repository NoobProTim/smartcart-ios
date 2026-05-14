// HomeView.swift
// SmartCart — Views/HomeView.swift
//
// The main screen of the app. Shows the user's Smart List sorted by
// replenishment urgency (items due for restock pinned at top, then
// alerted items, then alphabetical).
//
// Also contains:
//   - "Today's Deals" section — all active sales regardless of alert cap
//   - Pull-to-refresh wired to BackgroundSyncManager with staleness gate
//   - Last-updated subtitle under the nav title
//   - Notification permission denial banner (amber, safeAreaInset — not modal)
//   - Empty state CTA when Smart List is empty
//   - Deep-link handler for notification taps (P1-6)
//
// UPDATED IN TASK #3 (P1-7):
// Pull-to-refresh now calls BackgroundSyncManager.manualRefresh() and
// handles the RefreshResult enum to show "Prices updated just now" or
// "Last updated X hours ago" as the nav subtitle.

import SwiftUI
import UserNotifications

struct HomeView: View {

    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject private var notificationRouter: NotificationRouter
    @State private var deepLinkedItemID: Int64? = nil
    @State private var showNotificationBanner = false
    @State private var showScanner = false
    @State private var refreshSubtitle: String? = nil
    @State private var isRefreshing = false

    var body: some View {
        NavigationStack {
            ZStack {
                listContent
                if viewModel.items.isEmpty {
                    EmptyCTAView(onScanTapped: { showScanner = true })
                        .transition(.opacity)
                }
            }
            .navigationTitle("Smart List")
            .navigationSubtitle(refreshSubtitle ?? "")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showScanner = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.system(size: 18))
                    }
                    .accessibilityLabel("Scan a receipt")
                }
            }
            .refreshable {
                await performPullToRefresh()
            }
            .safeAreaInset(edge: .bottom) {
                if showNotificationBanner {
                    NotificationBannerView(
                        onDismiss: { showNotificationBanner = false },
                        onEnable: {
                            if let url = URL(string: UIApplication.openSettingsURLString) {
                                UIApplication.shared.open(url)
                            }
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                    .animation(.easeInOut(duration: 0.3), value: showNotificationBanner)
                }
            }
            .navigationDestination(isPresented: Binding(
                get: { deepLinkedItemID != nil },
                set: { if !$0 { deepLinkedItemID = nil } }
            )) {
                deepLinkDestination
            }
        }
        .sheet(isPresented: $showScanner, onDismiss: { viewModel.load() }) {
            MultiShotCaptureView()
        }
        .onAppear {
            viewModel.load()
            checkNotificationPermission()
            updateRefreshSubtitle()
        }
        .onReceive(notificationRouter.$itemIDToOpen) { itemID in
            guard let itemID else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                deepLinkedItemID = itemID
                notificationRouter.itemIDToOpen = nil
            }
        }
    }

    // MARK: - listContent
    @ViewBuilder
    private var listContent: some View {
        List {
            if !viewModel.todaysDeals.isEmpty {
                Section {
                    ForEach(viewModel.todaysDeals) { item in
                        if let sale = DatabaseManager.shared.fetchActiveSales(for: item.itemID).first {
                            DealRowView(deal: sale, itemName: item.nameDisplay)
                        }
                    }
                } header: {
                    Text("Today's Deals")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }

            Section {
                ForEach(viewModel.items) { item in
                    NavigationLink(destination: ItemDetailView(itemID: item.itemID)) {
                        SmartListRowView(item: item)
                    }
                    .accessibilityLabel("\(item.nameDisplay)\(item.isInRestockWindow ? ", due for restock" : "")")
                }
            } header: {
                if !viewModel.items.isEmpty {
                    Text("Your Items")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.easeInOut(duration: 0.25), value: viewModel.items.count)
    }

    // MARK: - deepLinkDestination
    @ViewBuilder
    private var deepLinkDestination: some View {
        if let itemID = deepLinkedItemID,
           let item = viewModel.items.first(where: { $0.itemID == itemID }) {
            ItemDetailView(itemID: item.itemID)
        } else {
            Text("Item not found").foregroundStyle(.secondary)
        }
    }

    // MARK: - performPullToRefresh()
    private func performPullToRefresh() async {
        let result = await BackgroundSyncManager.shared.manualRefresh()
        await MainActor.run {
            switch result {
            case .refreshed:
                refreshSubtitle = "Prices updated just now"
            case .skippedNotStale(let lastDate):
                refreshSubtitle = "Last updated \(relativeTimeString(from: lastDate))"
            case .noItems:
                refreshSubtitle = nil
            }
            viewModel.load()
        }
    }

    // MARK: - updateRefreshSubtitle()
    private func updateRefreshSubtitle() {
        let lastRefreshString = DatabaseManager.shared.getSetting(key: "last_price_refresh") ?? ""
        guard let lastRefreshDate = ISO8601DateFormatter().date(from: lastRefreshString) else {
            refreshSubtitle = nil
            return
        }
        let elapsed = Date().timeIntervalSince(lastRefreshDate)
        if elapsed < 60 {
            refreshSubtitle = "Prices updated just now"
        } else {
            refreshSubtitle = "Last updated \(relativeTimeString(from: lastRefreshDate))"
        }
    }

    // MARK: - relativeTimeString(from:)
    private func relativeTimeString(from date: Date) -> String {
        let elapsed = Date().timeIntervalSince(date)
        let minutes = Int(elapsed / 60)
        let hours = Int(elapsed / 3600)
        if minutes < 1 { return "just now" }
        if minutes < 60 { return "\(minutes) minute\(minutes == 1 ? "" : "s") ago" }
        return "\(hours) hour\(hours == 1 ? "" : "s") ago"
    }

    // MARK: - checkNotificationPermission()
    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                showNotificationBanner = settings.authorizationStatus == .denied
            }
        }
    }
}

// MARK: - SmartListRowView
struct SmartListRowView: View {
    let item: UserItem

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(item.isInRestockWindow ? Color.accentColor : Color.clear)
                .frame(width: 8, height: 8)

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(item.nameDisplay)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(.primary)
                    if item.hasActiveAlert {
                        Image(systemName: "bell.badge.fill")
                            .font(.system(size: 11))
                            .foregroundStyle(Color.accentColor)
                    }
                }
                if let restockDate = item.nextRestockDate {
                    Text(restockSubtitle(restockDate: restockDate))
                        .font(.system(size: 12))
                        .foregroundStyle(item.isInRestockWindow ? Color.accentColor : .secondary)
                }
            }

            Spacer()

            if let price = item.lastPurchasedPrice {
                Text(String(format: "$%.2f", price))
                    .font(.system(size: 14))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func restockSubtitle(restockDate: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: restockDate).day ?? 0
        if days <= 0 { return "Restock now" }
        if days == 1 { return "Due tomorrow" }
        if days <= Constants.restockWindowDays { return "Due in \(days) days" }
        return "Due \(formattedDate(restockDate))"
    }

    private func formattedDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        return formatter.string(from: date)
    }
}

// MARK: - DealRowView
struct DealRowView: View {
    let deal: FlyerSale
    var itemName: String = ""
    var storeName: String = ""

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "tag.fill")
                .font(.system(size: 14))
                .foregroundStyle(Color.accentColor)
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 2) {
                Text(itemName.isEmpty ? "Sale item" : itemName)
                    .font(.system(size: 14, weight: .medium))
                Text(storeName.isEmpty ? "Your store" : storeName)
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "$%.2f", deal.salePrice))
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(Color.accentColor)
                if let days = deal.expiresInDays() {
                    Text(days == 0 ? "Ends today" : "Ends in \(days)d")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding(.vertical, 2)
    }
}
