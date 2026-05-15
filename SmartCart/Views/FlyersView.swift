// FlyersView.swift — SmartCart/Views/FlyersView.swift

import SwiftUI

struct FlyersView: View {
    @StateObject private var vm = FlyersViewModel()
    @EnvironmentObject private var cartVM: GroceryListViewModel

    var body: some View {
        NavigationStack {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    bestPriceCarousel
                    categoryChips
                    dealList
                }
            }
            .navigationTitle("Flyers")
            .navigationSubtitle("This week's best deals near you")
            .searchable(text: $vm.searchText, prompt: "Search deals...")
            .overlay {
                if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                        .background(Color(.systemBackground).opacity(0.6))
                }
            }
        }
        .task { await vm.load() }
    }

    // MARK: Best price carousel
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

    // MARK: Category chips
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

    // MARK: Deal list
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
        .padding(.bottom, 24)
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
                    if let label = deal.expiryLabel {
                        Text(label)
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
