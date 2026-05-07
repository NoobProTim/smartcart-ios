// HomeView.swift
// SmartCart — Views/HomeView.swift
//
// Task #2 — Part 4: Home / Smart List (WIP)
//
// This is the main screen after onboarding. It shows the user's tracked grocery
// items sorted by how soon they need restocking, with alerted items pinned at top.
//
// Sections:
//   • Today's Deals   — ALL current lows regardless of alert cap (always visible)
//   • Smart List      — user's tracked items, sorted by restock proximity
//
// Pull-to-refresh wired to BackgroundSyncManager.shared.manualRefresh(),
// but only when last sync was > 1 hour ago (to avoid hammering Flipp API).
//
// Notification deep-link: NotificationRouter publishes itemIDToOpen;
// HomeView listens and pushes ItemDetailView with a 0.3s delay.
//
// Empty state: EmptyCTAView with Scan a Receipt CTA.
// Notification permission denied: NotificationBannerView amber nudge.
//
// STATUS: WIP — ReceiptScannerView, ItemDetailView navigation stubs only.

import SwiftUI
import UserNotifications

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject private var notificationRouter: NotificationRouter

    @State private var showScanner = false
    @State private var deepLinkedItemID: Int64? = nil
    @State private var showNotificationBanner = false
    @State private var isRefreshing = false
    @State private var lastRefreshDate: Date? = DatabaseManager.shared.lastSyncDate()

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.items.isEmpty && !viewModel.isLoading {
                    // First-time empty state
                    EmptyCTAView(onScanTapped: { showScanner = true })
                } else {
                    itemList
                }
            }
            .navigationTitle("SmartCart")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            // Notification deep-link invisible NavigationLink
            .background(
                NavigationLink(
                    destination: deepLinkDestination,
                    isActive: Binding(
                        get: { deepLinkedItemID != nil },
                        set: { if !$0 { deepLinkedItemID = nil } }
                    )
                ) { EmptyView() }
            )
            // Notification permission banner (safeAreaInset keeps list below it)
            .safeAreaInset(edge: .bottom) {
                if showNotificationBanner {
                    NotificationBannerView(
                        onDismiss: { withAnimation { showNotificationBanner = false } },
                        onEnable: { openNotificationSettings() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            // Stub — ReceiptScannerView wired in Task #2 Part 5
            Text("Receipt Scanner — coming in Part 5")
        }
        .onAppear {
            viewModel.load()
            checkNotificationPermission()
        }
        .onReceive(notificationRouter.$itemIDToOpen) { itemID in
            guard let itemID else { return }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                deepLinkedItemID = itemID
                notificationRouter.itemIDToOpen = nil
            }
        }
        .accessibilityLabel("SmartCart home screen")
    }

    // MARK: — Item list with sections
    private var itemList: some View {
        List {
            // Today's Deals section — all active price lows, no cap
            let deals = viewModel.todaysDeals
            if !deals.isEmpty {
                Section {
                    ForEach(deals) { item in
                        NavigationLink(destination: Text("Item Detail — Part 7 WIP")) {
                            ItemRowView(item: item)
                        }
                    }
                } header: {
                    Label("Today's Deals", systemImage: "tag.fill")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(Color.accentColor)
                        .accessibilityLabel("Today's deals section")
                }
            }

            // Smart List section
            Section {
                ForEach(viewModel.items) { item in
                    NavigationLink(destination: Text("Item Detail — Part 7 WIP")) {
                        ItemRowView(item: item)
                    }
                }
            } header: {
                HStack {
                    Text("Smart List").font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if let date = lastRefreshDate {
                        Text("Updated \(date.relativeShort())").font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                .accessibilityLabel("Smart list section")
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            // Only refresh if last sync was > 1 hour ago
            guard canRefresh() else { return }
            isRefreshing = true
            await BackgroundSyncManager.shared.manualRefresh()
            lastRefreshDate = Date()
            viewModel.load()
            isRefreshing = false
        }
    }

    // MARK: — Toolbar
    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        ToolbarItem(placement: .navigationBarTrailing) {
            Button(action: { showScanner = true }) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: 17, weight: .semibold))
            }
            .accessibilityLabel("Scan a receipt")
        }
    }

    // MARK: — Deep-link destination
    @ViewBuilder
    private var deepLinkDestination: some View {
        if let itemID = deepLinkedItemID,
           let item = viewModel.items.first(where: { $0.itemID == itemID }) {
            // ItemDetailView wired in Task #2 Part 7
            Text("Item Detail for \(item.nameDisplay) — Part 7 WIP")
        } else {
            EmptyView()
        }
    }

    // MARK: — Helpers

    private func canRefresh() -> Bool {
        guard let last = lastRefreshDate else { return true }
        return Date().timeIntervalSince(last) > 3600 // 1 hour
    }

    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let denied = settings.authorizationStatus == .denied ||
                             settings.authorizationStatus == .notDetermined
                // Only show if the user has items and hasn't dismissed this session
                showNotificationBanner = denied && !viewModel.items.isEmpty
            }
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: — Item row
// One row in the Smart List. Shows name, next restock date, alert badge, and current price.
private struct ItemRowView: View {
    let item: UserItem

    var body: some View {
        HStack(spacing: 12) {
            // Alert dot — per-item, not global (Fix P1-5)
            if item.hasActiveAlert {
                Circle().fill(Color.orange).frame(width: 8, height: 8)
                    .accessibilityLabel("Price alert active")
            } else {
                Circle().fill(Color.clear).frame(width: 8, height: 8)
            }

            VStack(alignment: .leading, spacing: 3) {
                Text(item.nameDisplay)
                    .font(.system(size: 15, weight: item.isInRestockWindow ? .semibold : .regular))
                    .foregroundStyle(.primary)

                if let restock = item.nextRestockDate {
                    Text(restockLabel(restock))
                        .font(.system(size: 12))
                        .foregroundStyle(item.isInRestockWindow ? Color.accentColor : .secondary)
                }
            }

            Spacer()

            if let price = item.lastPurchasedPrice {
                Text(String(format: "$%.2f", price))
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
        .accessibilityLabel("\(item.nameDisplay), \(item.isInRestockWindow ? "restock soon" : "")")
    }

    private func restockLabel(_ date: Date) -> String {
        let days = Calendar.current.dateComponents([.day], from: Date(), to: date).day ?? 0
        if days <= 0 { return "Restock now" }
        if days == 1 { return "Restock tomorrow" }
        return "Restock in \(days) days"
    }
}

// MARK: — Date helper
extension Date {
    // Returns a short relative string e.g. "just now", "2 min ago", "3h ago"
    func relativeShort() -> String {
        let seconds = Int(Date().timeIntervalSince(self))
        if seconds < 60  { return "just now" }
        if seconds < 3600 { return "\(seconds / 60)m ago" }
        if seconds < 86400 { return "\(seconds / 3600)h ago" }
        return "\(seconds / 86400)d ago"
    }
}
