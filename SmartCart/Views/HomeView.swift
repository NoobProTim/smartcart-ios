// HomeView.swift — SmartCart/Views/HomeView.swift
//
// Root tab view. Shows:
//   1. "Today's Deals" horizontal strip — items with active flyer sales.
//   2. Smart List — all tracked items sorted by restock urgency.
//      Each row carries a RestockBadge driven by HomeViewModel.restockStatuses.
//
// Notification-denied in-app nudge banner (Fix from open gaps):
//   A slim banner slides in at the top when notification permission is .denied.
//   It is NOT a modal — it's a persistent in-app element that links to Settings.

import SwiftUI
import UserNotifications

struct HomeView: View {

    @StateObject private var vm = HomeViewModel()
    @State private var notifDenied = false
    @State private var showScanSheet = false
    @State private var selectedItem: UserItem? = nil
    @State private var showPurchaseSheet = false
    @State private var purchaseTarget: UserItem? = nil

    var body: some View {
        NavigationStack {
            ZStack(alignment: .top) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {

                        // MARK: Notification nudge banner (not a modal)
                        if notifDenied {
                            NotifNudgeBanner()
                                .padding(.horizontal)
                                .transition(.move(edge: .top).combined(with: .opacity))
                        }

                        // MARK: Today's Deals
                        if !vm.todaysDeals.isEmpty {
                            TodaysDealsStrip(deals: vm.todaysDeals)
                                .padding(.horizontal)
                        }

                        // MARK: Smart List
                        if vm.isLoading {
                            ProgressView()
                                .frame(maxWidth: .infinity, minHeight: 200)
                        } else if vm.items.isEmpty {
                            // Animated empty state CTA (open gap: onboarding skip)
                            EmptyCTAView(onTap: { showScanSheet = true })
                                .padding(.horizontal)
                        } else {
                            LazyVStack(spacing: 0) {
                                ForEach(vm.items) { item in
                                    SmartListRow(
                                        item: item,
                                        status: vm.restockStatuses[item.itemID] ?? .ok
                                    )
                                    .contentShape(Rectangle())
                                    .onTapGesture {
                                        selectedItem = item
                                    }
                                    .swipeActions(edge: .trailing, allowsFullSwipe: true) {
                                        Button {
                                            purchaseTarget = item
                                            showPurchaseSheet = true
                                        } label: {
                                            Label("Bought", systemImage: "cart.badge.plus")
                                        }
                                        .tint(.green)
                                    }
                                    Divider().padding(.leading, 16)
                                }
                            }
                            .background(Color(.systemBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 12))
                            .padding(.horizontal)
                        }
                    }
                    .padding(.top, 8)
                    .padding(.bottom, 32)
                }
            }
            .navigationTitle("SmartCart")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button {
                        showScanSheet = true
                    } label: {
                        Image(systemName: "camera.viewfinder")
                            .font(.title3)
                    }
                    .accessibilityLabel("Scan receipt")
                }
            }
            .sheet(isPresented: $showScanSheet) {
                ReceiptScanView()
            }
            .sheet(item: $selectedItem) { item in
                ItemDetailView(item: item)
            }
            .sheet(item: $purchaseTarget, isPresented: $showPurchaseSheet) { item in
                MarkPurchasedSheet(item: item, vm: vm)
            }
            .onAppear {
                vm.load()
                checkNotificationStatus()
            }
            .refreshable {
                vm.load()
            }
        }
    }

    private func checkNotificationStatus() {
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                withAnimation(.easeInOut(duration: 0.3)) {
                    notifDenied = settings.authorizationStatus == .denied
                }
            }
        }
    }
}

// MARK: - Notification nudge banner
// Shown inline at the top of the scroll view (not a modal) when permission is .denied.
private struct NotifNudgeBanner: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash.fill")
                .foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications are off")
                    .font(.subheadline.weight(.semibold))
                Text("Enable them to get price drop and restock alerts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    UIApplication.shared.open(url)
                }
            }
            .font(.subheadline.weight(.medium))
            .tint(.orange)
        }
        .padding(12)
        .background(Color.orange.opacity(0.12))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Today's Deals strip
private struct TodaysDealsStrip: View {
    let deals: [UserItem]
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Today\u{2019}s Deals")
                .font(.headline)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(deals) { item in
                        DealChip(item: item)
                    }
                }
            }
        }
    }
}

private struct DealChip: View {
    let item: UserItem
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.nameDisplay)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
            HStack(spacing: 4) {
                Image(systemName: "tag.fill")
                    .font(.caption2)
                Text("On sale")
                    .font(.caption)
            }
            .foregroundStyle(.green)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.green.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

// MARK: - Smart List row
private struct SmartListRow: View {
    let item: UserItem
    let status: RestockStatus

    var body: some View {
        HStack(spacing: 12) {
            // Item name + subtitle
            VStack(alignment: .leading, spacing: 3) {
                Text(item.nameDisplay)
                    .font(.body)
                if let days = item.daysUntilRestock {
                    Text(restockSubtitle(days: days, status: status))
                        .font(.caption)
                        .foregroundStyle(captionColor(status: status))
                } else {
                    Text("No restock estimate yet")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }
            Spacer()
            RestockBadge(status: status)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private func restockSubtitle(days: Int, status: RestockStatus) -> String {
        switch status {
        case .due:           return days < 0 ? "Overdue by \(abs(days))d" : "Due today"
        case .approaching:   return "In \(days) day\(days == 1 ? "" : "s")"
        case .ok:            return "In \(days) day\(days == 1 ? "" : "s")"
        case .seasonalSuppressed: return "Seasonal item"
        }
    }

    private func captionColor(status: RestockStatus) -> Color {
        switch status {
        case .due:           return .red
        case .approaching:   return .orange
        case .ok:            return .secondary
        case .seasonalSuppressed: return .secondary
        }
    }
}

// MARK: - Mark as Purchased sheet
// Lightweight sheet for the swipe action.
// Full quantity picker and price field in ItemDetailView.
private struct MarkPurchasedSheet: View {
    let item: UserItem
    @ObservedObject var vm: HomeViewModel
    @Environment(\.dismiss) private var dismiss
    @State private var priceText = ""
    @State private var quantity  = 1

    var body: some View {
        NavigationStack {
            Form {
                Section("Price paid (optional)") {
                    TextField("e.g. 3.99", text: $priceText)
                        .keyboardType(.decimalPad)
                }
                Section("Quantity") {
                    Stepper("\(quantity) unit\(quantity == 1 ? "" : "s")", value: $quantity, in: 1...99)
                }
            }
            .navigationTitle(item.nameDisplay)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        let price = Double(priceText.trimmingCharacters(in: .whitespaces))
                        vm.markAsPurchased(item: item, price: price, quantity: quantity)
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
