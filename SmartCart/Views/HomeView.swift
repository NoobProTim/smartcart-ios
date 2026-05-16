// HomeView.swift
// SmartCart — Views/HomeView.swift
//
// The main screen of the app. Shows the user's Smart List sorted by
// replenishment urgency (items due for restock pinned at top, then
// alerted items, then alphabetical).
//
// Also contains:
//   - Segment picker: "My List" | "On Sale Now"
//   - "Today's Deals" section in My List tab — active sales on watchlisted items
//   - Pull-to-refresh wired to BackgroundSyncManager with staleness gate
//   - Last-updated subtitle under the nav title
//   - Notification permission denial banner (amber, safeAreaInset — not modal)
//   - Empty state CTA when Smart List is empty
//   - Deep-link handler for notification taps
//   - Scanner FAB — opens MultiShotCaptureView (Sprint 3: re-enabled)

import SwiftUI
import UserNotifications

struct HomeView: View {

    var onBrowseDealsTapped: (() -> Void)? = nil

    @StateObject private var viewModel = HomeViewModel()
    @EnvironmentObject private var notificationRouter: NotificationRouter
    @State private var deepLinkedItemID: Int64? = nil
    @State private var showNotificationBanner = false
    @State private var showScanner = false        // Sprint 3: controls scanner sheet
    @State private var showAddItem = false
    @State private var newItemName = ""
    @State private var refreshSubtitle: String? = nil
    @State private var isRefreshing = false
    @State private var groceryAddedTrigger = 0
    @State private var activeSegment: Int = 0     // 0 = My List, 1 = On Sale Now

    var body: some View {
        NavigationStack {
            ZStack {
                listContent
                if viewModel.items.isEmpty {
                    NewUserEmptyStateView(
                        onScanTapped: { showScanner = true },
                        onBrowseDealsTapped: onBrowseDealsTapped
                    )
                    .transition(.opacity)
                }
            }
            .navigationTitle(greetingText)
            .navigationSubtitle(refreshSubtitle ?? "")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    HStack(spacing: 16) {
                        // Add item manually
                        Button { showAddItem = true } label: {
                            Image(systemName: "plus")
                        }
                        .accessibilityLabel("Add item manually")
                        // Sprint 3: scanner FAB re-enabled
                        Button { showScanner = true } label: {
                            Image(systemName: "camera.viewfinder")
                                .font(.system(size: 18))
                        }
                        .accessibilityLabel("Scan a receipt")
                    }
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
        // Sprint 3: scanner sheet re-enabled. Reloads list after dismissal
        // so any newly scanned items appear immediately.
        .sheet(isPresented: $showScanner, onDismiss: { viewModel.load() }) {
            MultiShotCaptureView()
        }
        .sheet(isPresented: $showAddItem) {
            addItemSheet
        }
        .sensoryFeedback(.success, trigger: groceryAddedTrigger)
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
    // Hosts the deal-count alert banner, the segment picker, and switches
    // between myListContent and onSaleContent based on activeSegment.
    @ViewBuilder
    private var listContent: some View {
        VStack(spacing: 0) {
            // Amber deal alert banner — visible on both segments
            if !viewModel.todaysDeals.isEmpty {
                HStack(spacing: 6) {
                    Image(systemName: "tag.fill")
                        .font(.system(size: 12))
                    Text("\(viewModel.todaysDeals.count) deal\(viewModel.todaysDeals.count == 1 ? "" : "s") active right now")
                        .font(.system(size: 13, weight: .medium))
                    Spacer()
                    Image(systemName: "chevron.right")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                .foregroundStyle(Color.accentColor)
                .padding(.horizontal, 16)
                .padding(.vertical, 10)
                .background(Color.accentColor.opacity(0.08))
            }

            // Segment picker: My List | On Sale Now
            Picker("", selection: $activeSegment) {
                Text("My List").tag(0)
                Text("On Sale Now").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(Color(.systemGroupedBackground))

            if activeSegment == 0 {
                myListContent
            } else {
                onSaleContent
            }
        }
    }

    // MARK: - myListContent
    // Savings card → Grocery List → Today's Deals → Your Items
    @ViewBuilder
    private var myListContent: some View {
        List {
            // Annual savings card — only shown when there are verified savings to display
            if viewModel.annualSavings > 0 {
                Section {
                    HStack(spacing: 16) {
                        Image(systemName: "dollarsign.circle.fill")
                            .font(.system(size: 36))
                            .foregroundStyle(.green)
                        VStack(alignment: .leading, spacing: 2) {
                            Text("You've saved")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                            Text(viewModel.annualSavings, format: .currency(code: "CAD"))
                                .font(.system(size: 22, weight: .bold))
                                .monospacedDigit()
                                .contentTransition(.numericText())
                                .animation(.spring(duration: 0.4), value: viewModel.annualSavings)
                            Text("vs. your average prices this year")
                                .font(.system(size: 12))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                    }
                    .padding(.vertical, 6)
                    .listRowBackground(
                        ZStack {
                            Color(.secondarySystemGroupedBackground)
                            LinearGradient(
                                colors: [Color.green.opacity(0.10), Color.clear],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        }
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                        .shadow(color: Color.green.opacity(0.08), radius: 4, y: 2)
                    )
                }
            }

            // Grocery list — items added from Flyers or manually
            if !viewModel.groceryList.isEmpty {
                Section {
                    ForEach(viewModel.groceryList) { entry in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(entry.nameDisplay)
                                    .font(.system(size: 15))
                                if let price = entry.expectedPrice {
                                    Text("Expected: \(price, format: .currency(code: "CAD"))")
                                        .font(.system(size: 13))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            Spacer()
                            Image(systemName: "cart")
                                .foregroundStyle(.secondary)
                        }
                        .swipeActions(edge: .trailing) {
                            Button(role: .destructive) {
                                DatabaseManager.shared.removeFromGroceryList(id: entry.id)
                                viewModel.load()
                            } label: {
                                Label("Remove", systemImage: "trash")
                            }
                        }
                    }
                } header: {
                    Text("Grocery List")
                        .font(.system(size: 11, weight: .semibold).smallCaps())
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }

            // Today's Deals — active sales on items the user already tracks
            if !viewModel.todaysDeals.isEmpty {
                Section {
                    ForEach(viewModel.todaysDeals) { item in
                        if let sale = DatabaseManager.shared.fetchActiveSales(for: item.itemID).first {
                            Button {
                                DatabaseManager.shared.addToGroceryList(
                                    itemID: item.itemID,
                                    expectedPrice: sale.salePrice
                                )
                                groceryAddedTrigger += 1
                                viewModel.load()
                            } label: {
                                DealRowView(
                                    deal: sale,
                                    itemName: item.nameDisplay,
                                    historicalLow: DatabaseManager.shared.historicalLow(for: item.itemID)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("Today's Deals")
                        .font(.system(size: 11, weight: .semibold).smallCaps())
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }

            // Main Smart List — all watched items sorted by urgency
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
                        .font(.system(size: 11, weight: .semibold).smallCaps())
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
        }
        .listStyle(.insetGrouped)
        .animation(.easeInOut(duration: 0.25), value: viewModel.items.count)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: viewModel.groceryList.count)
        .animation(.spring(duration: 0.35, bounce: 0.15), value: viewModel.annualSavings > 0)
    }

    // MARK: - onSaleContent
    // Second segment: shows all active deals on the user's watchlist items.
    // Empty state shows a tag icon and message instead of a blank screen.
    @ViewBuilder
    private var onSaleContent: some View {
        if viewModel.todaysDeals.isEmpty {
            VStack(spacing: 12) {
                Image(systemName: "tag")
                    .font(.system(size: 40))
                    .foregroundStyle(.secondary)
                Text("No active deals right now")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.top, 60)
        } else {
            List {
                Section {
                    ForEach(viewModel.todaysDeals) { item in
                        if let sale = DatabaseManager.shared.fetchActiveSales(for: item.itemID).first {
                            Button {
                                DatabaseManager.shared.addToGroceryList(
                                    itemID: item.itemID,
                                    expectedPrice: sale.salePrice
                                )
                                groceryAddedTrigger += 1
                                viewModel.load()
                            } label: {
                                DealRowView(
                                    deal: sale,
                                    itemName: item.nameDisplay,
                                    historicalLow: DatabaseManager.shared.historicalLow(for: item.itemID)
                                )
                            }
                            .buttonStyle(.plain)
                        }
                    }
                } header: {
                    Text("On Sale Now")
                        .font(.system(size: 11, weight: .semibold).smallCaps())
                        .foregroundStyle(.secondary)
                        .textCase(nil)
                }
            }
            .listStyle(.insetGrouped)
        }
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
    // Calls BackgroundSyncManager and updates the nav subtitle with the result.
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
    // Reads the last_price_refresh timestamp from DB and formats it as a
    // human-readable string for the navigation subtitle on appear.
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
    // Shows the amber banner in safeAreaInset if notifications are denied.
    private func checkNotificationPermission() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                showNotificationBanner = settings.authorizationStatus == .denied
            }
        }
    }

    // MARK: - greetingText
    private var greetingText: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12:  return "Good morning"
        case 12..<17: return "Good afternoon"
        default:      return "Good evening"
        }
    }
}

// MARK: - addItemSheet (extension on HomeView)
extension HomeView {
    var addItemSheet: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("e.g. Salted Butter", text: $newItemName)
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                        .onSubmit { submitAddItem() }
                } header: {
                    Text("Item name")
                }
            }
            .navigationTitle("Add Item")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { newItemName = ""; showAddItem = false }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Add") { submitAddItem() }
                        .disabled(newItemName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }
        }
        .presentationDetents([.medium])
    }

    private func submitAddItem() {
        let name = newItemName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }
        viewModel.addItem(nameDisplay: name)
        newItemName  = ""
        showAddItem = false
    }
}

// MARK: - NewUserEmptyStateView
struct NewUserEmptyStateView: View {
    let onScanTapped: () -> Void
    let onBrowseDealsTapped: (() -> Void)?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            VStack(spacing: 24) {
                Image(systemName: "cart.badge.plus")
                    .font(.system(size: 56))
                    .foregroundStyle(Color.accentColor)

                VStack(spacing: 8) {
                    Text("Welcome to SmartCart")
                        .font(.system(size: 22, weight: .bold))
                        .foregroundStyle(.primary)
                    Text("Scan a grocery receipt to start tracking prices and get smarter shopping alerts.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                VStack(spacing: 12) {
                    Button(action: onScanTapped) {
                        Label("Scan a Receipt", systemImage: "camera.viewfinder")
                            .font(.system(size: 16, weight: .semibold))
                            .foregroundStyle(.white)
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 16)
                            .background(Color.accentColor)
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                    }
                    .accessibilityLabel("Scan a receipt to get started")

                    if let onBrowseDealsTapped {
                        Button(action: onBrowseDealsTapped) {
                            Label("Browse This Week's Deals", systemImage: "tag")
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(Color.accentColor)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 14)
                                .background(Color.accentColor.opacity(0.10))
                                .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .accessibilityLabel("Browse deals on the Flyers tab")
                    }
                }
            }
            .padding(28)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .shadow(color: .black.opacity(0.06), radius: 12, y: 4)
            .padding(.horizontal, 24)
            Spacer()
            Spacer()
        }
        .background(Color(.systemGroupedBackground).ignoresSafeArea())
    }
}

// MARK: - SmartListRowView
// One row in the Smart List. Shows urgency dot, item name, alert badge,
// restock date subtitle, and last-purchased price on the trailing side.
struct SmartListRowView: View {
    let item: UserItem

    var body: some View {
        HStack(spacing: 12) {
            // Blue urgency dot — visible only when item is in restock window
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
                        .fontDesign(.rounded)
                        .foregroundStyle(item.isInRestockWindow ? Color.accentColor : .secondary)
                }
            }

            Spacer()

            if let price = item.lastPurchasedPrice {
                Text(String(format: "$%.2f", price))
                    .font(.system(size: 14))
                    .monospacedDigit()
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
// Reusable row for showing a FlyerSale on any screen.
// Shows store name (or fallback), historical-low badge, sale price, and expiry.
struct DealRowView: View {
    let deal: FlyerSale
    var itemName: String = ""
    var storeName: String = ""
    var historicalLow: (price: Double, label: String)? = nil

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
                if let low = historicalLow {
                    HStack(spacing: 3) {
                        Image(systemName: "arrow.down")
                            .font(.system(size: 9, weight: .bold))
                        Text(low.price, format: .currency(code: "CAD"))
                            .font(.system(size: 11, weight: .semibold))
                            .monospacedDigit()
                    }
                    .foregroundStyle(.green)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(Color.green.opacity(0.12))
                    .clipShape(Capsule())
                }
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 2) {
                Text(String(format: "$%.2f", deal.salePrice))
                    .font(.system(size: 14, weight: .semibold))
                    .monospacedDigit()
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
