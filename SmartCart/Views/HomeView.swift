// HomeView.swift — SmartCart/Views/HomeView.swift
// P1-D: ItemDetailView is now wired for both itemList NavigationLinks
//       and the NotificationRouter deep-link destination.

import SwiftUI
import UserNotifications

struct HomeView: View {
    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject private var notificationRouter: NotificationRouter

    @State private var showScanner             = false
    @State private var deepLinkedItemID: Int64? = nil
    @State private var showNotificationBanner  = false
    @State private var isRefreshing            = false
    @State private var lastRefreshDate: Date?  = DatabaseManager.shared.lastSyncDate()

    var body: some View {
        NavigationStack {
            ZStack {
                if viewModel.items.isEmpty && !viewModel.isLoading {
                    EmptyCTAView(onScanTapped: { showScanner = true })
                } else {
                    itemList
                }
            }
            .navigationTitle("SmartCart")
            .navigationBarTitleDisplayMode(.large)
            .toolbar { toolbarContent }
            .background(
                NavigationLink(
                    destination: deepLinkDestination,
                    isActive: Binding(
                        get: { deepLinkedItemID != nil },
                        set: { if !$0 { deepLinkedItemID = nil } }
                    )
                ) { EmptyView() }
            )
            .safeAreaInset(edge: .bottom) {
                if showNotificationBanner {
                    NotificationBannerView(
                        onDismiss: { withAnimation { showNotificationBanner = false } },
                        onEnable:  { openNotificationSettings() }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
        }
        .sheet(isPresented: $showScanner) {
            ReceiptScanView()
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

    // MARK: - Item list
    private var itemList: some View {
        List {
            let deals = viewModel.todaysDeals
            if !deals.isEmpty {
                Section {
                    ForEach(deals) { item in
                        // P1-D: was Text("Item Detail — Part 7 WIP")
                        NavigationLink(destination: ItemDetailView(itemID: item.itemID)) {
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

            Section {
                ForEach(viewModel.items) { item in
                    // P1-D: was Text("Item Detail — Part 7 WIP")
                    NavigationLink(destination: ItemDetailView(itemID: item.itemID)) {
                        ItemRowView(item: item)
                    }
                }
            } header: {
                HStack {
                    Text("Smart List")
                        .font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
                    Spacer()
                    if let date = lastRefreshDate {
                        Text("Updated \(date.relativeShort())")
                            .font(.system(size: 11)).foregroundStyle(.tertiary)
                    }
                }
                .accessibilityLabel("Smart list section")
            }
        }
        .listStyle(.insetGrouped)
        .refreshable {
            guard canRefresh() else { return }
            isRefreshing = true
            await BackgroundSyncManager.shared.manualRefresh()
            lastRefreshDate = Date()
            viewModel.load()
            isRefreshing = false
        }
    }

    // MARK: - Toolbar
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

    // MARK: - Deep-link destination
    @ViewBuilder
    private var deepLinkDestination: some View {
        // P1-D: was Text("Item Detail for … — Part 7 WIP")
        if let itemID = deepLinkedItemID {
            ItemDetailView(itemID: itemID)
        } else {
            EmptyView()
        }
    }

    // MARK: - Helpers
    private func canRefresh() -> Bool {
        guard let last = lastRefreshDate else { return true }
        return Date().timeIntervalSince(last) > Constants.minRefreshIntervalSeconds
    }

    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                let denied = settings.authorizationStatus == .denied ||
                             settings.authorizationStatus == .notDetermined
                showNotificationBanner = denied && !viewModel.items.isEmpty
            }
        }
    }

    private func openNotificationSettings() {
        guard let url = URL(string: UIApplication.openNotificationSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}

// MARK: - Item row
private struct ItemRowView: View {
    let item: UserItem

    var body: some View {
        HStack(spacing: 12) {
            Circle()
                .fill(item.hasActiveAlert ? Color.orange : Color.clear)
                .frame(width: 8, height: 8)
                .accessibilityLabel(item.hasActiveAlert ? "Price alert active" : "")

            VStack(alignment: .leading, spacing: 3) {
                Text(item.nameDisplay)
                    .font(.system(size: 15,
                                  weight: item.isInRestockWindow ? .semibold : .regular))
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

extension Date {
    func relativeShort() -> String {
        let s = Int(Date().timeIntervalSince(self))
        if s < 60    { return "just now" }
        if s < 3600  { return "\(s / 60)m ago" }
        if s < 86400 { return "\(s / 3600)h ago" }
        return "\(s / 86400)d ago"
    }
}
