// FlyersView.swift — SmartCart/Views/FlyersView.swift
//
// The Deals tab. Shows this week's best prices from the user's stores.
//
// Layout (matches wireframe index-4.html):
//   1. "Best prices this week" horizontal carousel (dark cards)
//   2. Category filter chips (All, Dairy, Meat, Produce, Bakery, Pantry)
//   3. Deal list rows (store badge, name, sale/reg price, % off, + button)
//   4. "Browse Store Flyers" section — tappable store tiles drilling into
//      FlyerBrowserView (GAP-2 fix: this section was missing)
//
// GAP-1 fix: navigationTitle changed from "Flyers" to "Deals".
// GAP-2 fix: Browse Store Flyers section added at bottom of scroll view.

import SwiftUI

struct FlyersView: View {
    @StateObject private var vm = FlyersViewModel()
    @EnvironmentObject private var cartVM: GroceryListViewModel

    // Controls navigation to FlyerBrowserView for a specific store.
    // Nil means no navigation is active.
    @State private var selectedFlyerStore: String? = nil

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    bestPriceCarousel
                    categoryChips
                    dealList
                    browseStoreFlyers      // GAP-2: new section
                }
            }
            .navigationTitle("Deals")     // GAP-1: was "Flyers"
            .navigationSubtitle("This week's best prices near you")
            .searchable(text: $vm.searchText, prompt: "Search deals...")
            .overlay {
                if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground).opacity(0.6))
                }
            }
            // Navigate to FlyerBrowserView when a store tile is tapped.
            // The store name is passed in but FlyerBrowserView currently
            // shows the gated "pending approval" card regardless of store —
            // the store name is wired in for when the WKWebView is enabled.
            .navigationDestination(item: $selectedFlyerStore) { storeName in
                FlyerBrowserView(storeName: storeName)
            }
        }
        .task { await vm.load() }
    }

    // MARK: - bestPriceCarousel
    // Horizontal dark cards for the top deals this week.
    private var bestPriceCarousel: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Best prices this week")
                .font(.system(size: 11, weight: .semibold).smallCaps())
                .textCase(nil)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 10) {
                    ForEach(vm.bestDeals) { deal in
                        BestPriceCard(deal: deal)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 4)
            }
        }
    }

    // MARK: - categoryChips
    // Filter chips: All | Dairy | Meat | Produce | Bakery | Pantry
    private var categoryChips: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DealCategory.allCases, id: \.self) { cat in
                    Button {
                        vm.selectedCategory = cat
                    } label: {
                        Text("\(cat.emoji) \(cat.rawValue)")
                            .font(.system(size: 13, weight: vm.selectedCategory == cat ? .semibold : .regular))
                            .foregroundStyle(vm.selectedCategory == cat ? .white : Color(.label))
                            .padding(.horizontal, 14)
                            .padding(.vertical, 6)
                            .background(
                                vm.selectedCategory == cat
                                    ? Color(.label)
                                    : Color(.secondarySystemGroupedBackground)
                            )
                            .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .animation(.spring(duration: 0.2), value: vm.selectedCategory)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
        }
    }

    // MARK: - dealList
    // Filtered list of deals. Empty state shown when no results match the filter.
    private var dealList: some View {
        LazyVStack(spacing: 8) {
            if vm.filteredDeals.isEmpty && !vm.isLoading {
                Text("No deals found")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 40)
            } else {
                ForEach(vm.filteredDeals) { deal in
                    DealRow(
                        deal: deal,
                        isAdded: vm.addedIDs.contains(deal.id)
                    ) {
                        vm.addToCart(deal)
                        cartVM.load()
                    }
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    // MARK: - browseStoreFlyers
    // GAP-2 fix: "Browse Store Flyers" section matching the wireframe.
    // Shows a section header and one tile per user store. Tapping a tile
    // navigates to FlyerBrowserView (which currently shows the pending-
    // approval card until Flipp legal clears).
    private var browseStoreFlyers: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Section header
            Text("Browse Store Flyers")
                .font(.system(size: 11, weight: .semibold).smallCaps())
                .textCase(nil)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.top, 20)
                .padding(.bottom, 10)

            // Section subheading
            Text("See full weekly circulars for your stores")
                .font(.system(size: 13))
                .foregroundStyle(.secondary)
                .padding(.horizontal, 20)
                .padding(.bottom, 12)

            // Store tiles — one per user store (from vm.userStores)
            LazyVStack(spacing: 8) {
                ForEach(vm.userStores, id: \.self) { storeName in
                    Button {
                        selectedFlyerStore = storeName
                    } label: {
                        FlyerStoreTile(storeName: storeName, deals: vm.filteredDeals.filter {
                            $0.storeName.lowercased() == storeName.lowercased()
                        })
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 32)
        }
    }
}

// MARK: - FlyerStoreTile
// One tappable row in the Browse Store Flyers section.
// Shows store name (with colour badge), valid date range from the first
// active deal for that store, and the top 3 deal names as a preview.
private struct FlyerStoreTile: View {
    let storeName: String
    let deals: [FlyerDeal]      // Active deals at this store, for preview

    // Date range label — derived from the first deal's expiry label if available.
    private var dateRange: String {
        deals.first?.flyerDateRange ?? deals.first?.expiryLabel ?? ""
    }

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                // Store name badge
                StoreBadgeView(name: storeName)

                // Date range (e.g. "May 15–21")
                if !dateRange.isEmpty {
                    Text(dateRange)
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                }

                // Preview: up to 3 deal names from this store
                if !deals.isEmpty {
                    let preview = deals.prefix(3).map { $0.name }.joined(separator: "  ·  ")
                    Text(preview)
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }

            Spacer()

            Image(systemName: "chevron.right")
                .font(.system(size: 13, weight: .medium))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - BestPriceCard
private struct BestPriceCard: View {
    let deal: FlyerDeal

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top) {
                Text(deal.emoji)
                    .font(.system(size: 24))
                    .frame(width: 44, height: 44)
                    .background(Color.white.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

                Spacer()

                VStack(alignment: .trailing, spacing: 4) {
                    Text("BEST")
                        .font(.system(size: 9, weight: .black))
                        .foregroundStyle(Color.yellow)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 3)
                        .background(Color.yellow.opacity(0.15))
                        .clipShape(RoundedRectangle(cornerRadius: 5, style: .continuous))

                    Text(deal.storeName.uppercased())
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundStyle(Color.white.opacity(0.45))
                        .lineLimit(1)
                }
            }
            .padding(.bottom, 10)

            Text(deal.name)
                .font(.system(size: 12, weight: .medium))
                .foregroundStyle(Color.white.opacity(0.65))
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 8)

            Text(deal.salePrice, format: .currency(code: "CAD"))
                .font(.system(size: 26, weight: .black))
                .foregroundStyle(.white)
                .monospacedDigit()
                .padding(.bottom, 6)

            HStack(spacing: 6) {
                if let reg = deal.regularPrice {
                    Text(reg, format: .currency(code: "CAD"))
                        .font(.system(size: 11))
                        .foregroundStyle(Color.white.opacity(0.28))
                        .strikethrough()
                        .monospacedDigit()
                }
                if let savings = deal.savingsAmount {
                    Text("Save \(savings, format: .currency(code: "CAD"))")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.green)
                }
            }
        }
        .padding(13)
        .frame(width: 155, alignment: .leading)
        .background(Color(white: 0.11))
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(Color.white.opacity(0.07), lineWidth: 1)
        )
    }
}

// MARK: - DealRow
private struct DealRow: View {
    let deal:    FlyerDeal
    let isAdded: Bool
    let onAdd:   () -> Void

    var body: some View {
        HStack(spacing: 10) {
            Text(deal.emoji)
                .font(.system(size: 24))
                .frame(width: 44, height: 44)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 5) {
                    StoreBadgeView(name: deal.storeName)
                    if let range = deal.flyerDateRange ?? deal.expiryLabel {
                        Text(range)
                            .font(.system(size: 10))
                            .foregroundStyle(.secondary)
                    }
                }

                Text(deal.name)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(1)

                HStack(spacing: 5) {
                    Text(deal.salePrice, format: .currency(code: "CAD"))
                        .font(.system(size: 15, weight: .bold))
                        .monospacedDigit()

                    if let reg = deal.regularPrice {
                        Text(reg, format: .currency(code: "CAD"))
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                            .strikethrough()
                            .monospacedDigit()
                    }

                    if let pct = deal.discountPercent {
                        Text("−\(pct)%")
                            .font(.system(size: 9, weight: .bold))
                            .foregroundStyle(.green)
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Color.green.opacity(0.12))
                            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
                    }
                }
            }

            Spacer()

            Button(action: onAdd) {
                Image(systemName: isAdded ? "checkmark" : "plus")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.white)
                    .frame(width: 30, height: 30)
                    .background(isAdded ? Color.green : Color(white: 0.11))
                    .clipShape(Circle())
                    .animation(.spring(duration: 0.2, bounce: 0.2), value: isAdded)
            }
            .buttonStyle(.plain)
            .disabled(isAdded)
            .sensoryFeedback(.success, trigger: isAdded)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(Color(.systemBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
    }
}

// MARK: - StoreBadgeView
struct StoreBadgeView: View {
    let name: String

    private var color: Color {
        let n = name.lowercased()
        if n.contains("no frills")  { return Color(red: 0.91, green: 0.14, blue: 0.16) }
        if n.contains("loblaws")    { return Color(red: 0.78, green: 0.06, blue: 0.18) }
        if n.contains("metro")      { return Color(red: 0.0,  green: 0.19, blue: 0.53) }
        if n.contains("walmart")    { return Color(red: 0.0,  green: 0.44, blue: 0.86) }
        if n.contains("highland")   { return Color(red: 0.18, green: 0.50, blue: 0.25) }
        if n.contains("sobeys")     { return Color(red: 0.82, green: 0.14, blue: 0.14) }
        return Color.secondary
    }

    var body: some View {
        Text(name.uppercased())
            .font(.system(size: 9, weight: .bold))
            .foregroundStyle(.white)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color)
            .clipShape(RoundedRectangle(cornerRadius: 4, style: .continuous))
            .lineLimit(1)
    }
}
