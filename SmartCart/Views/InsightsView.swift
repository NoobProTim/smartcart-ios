// InsightsView.swift
// SmartCart
//
// The Insights tab — monthly spend total + delta, weekly bar chart,
// top savings, spend by store, and rising price warnings.
// Uses Swift Charts (iOS 16+) for the bar chart.
// All data comes from InsightsViewModel; no direct DB calls here.

import SwiftUI
import Charts

struct InsightsView: View {

    @StateObject private var viewModel = InsightsViewModel()

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.isLoading {
                    loadingView
                } else {
                    scrollContent
                }
            }
            .navigationTitle("Insights")
            .navigationBarTitleDisplayMode(.large)
        }
        .task {
            viewModel.load()
        }
    }

    // MARK: - Loading placeholder

    private var loadingView: some View {
        VStack(spacing: 16) {
            ProgressView()
            Text("Calculating your insights…")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Main scroll content

    private var scrollContent: some View {
        ScrollView {
            LazyVStack(spacing: 16) {
                monthlySpendCard
                weeklyChartCard
                if !viewModel.topSavings.isEmpty {
                    topSavingsCard
                }
                if !viewModel.storeSpends.isEmpty {
                    storeBreakdownCard
                }
                if !viewModel.risingPrices.isEmpty {
                    risingPricesCard
                }
                Color.clear.frame(height: 16)
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Monthly spend card

    private var monthlySpendCard: some View {
        InsightsCard {
            VStack(alignment: .leading, spacing: 4) {
                Text("Weekly Spend")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(.secondary)
                    .textCase(.uppercase)
                    .kerning(0.5)

                HStack(alignment: .firstTextBaseline, spacing: 0) {
                    Text(viewModel.monthTotalFormatted)
                        .font(.system(size: 36, weight: .bold))
                        .foregroundStyle(.primary)
                    Spacer()
                    deltaView
                }

                Text("This month")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
    }

    /// Arrow badge showing spend change vs last month.
    private var deltaView: some View {
        HStack(spacing: 4) {
            Image(systemName: viewModel.deltaIsGood ? "arrow.down" : "arrow.up")
                .font(.system(size: 13, weight: .semibold))
            Text(formatDeltaDollars(viewModel.monthDelta))
                .font(.system(size: 15, weight: .semibold))
        }
        .foregroundStyle(viewModel.deltaIsGood ? Color.green : Color.orange)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(
            (viewModel.deltaIsGood ? Color.green : Color.orange).opacity(0.12)
        )
        .clipShape(Capsule())
    }

    // MARK: - Weekly bar chart

    private var weeklyChartCard: some View {
        InsightsCard {
            VStack(alignment: .leading, spacing: 12) {
                if viewModel.weeklyBars.isEmpty {
                    Text("No spend data yet this month.")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 24)
                } else {
                    Chart(viewModel.weeklyBars) { bar in
                        BarMark(
                            x: .value("Week", bar.label),
                            y: .value("Spend", bar.amount)
                        )
                        .foregroundStyle(Color.accentColor.gradient)
                        .cornerRadius(6)
                    }
                    .chartYAxis {
                        AxisMarks(position: .leading) { value in
                            if let dollar = value.as(Double.self) {
                                AxisValueLabel {
                                    Text("$\(Int(dollar))")
                                        .font(.system(size: 11))
                                }
                            }
                        }
                    }
                    .chartXAxis {
                        AxisMarks { _ in
                            AxisValueLabel()
                        }
                    }
                    .frame(height: 160)
                }
            }
        }
    }

    // MARK: - Top savings card

    private var topSavingsCard: some View {
        InsightsCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Top Savings This Month")

                ForEach(viewModel.topSavings) { row in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.itemName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                            Text(row.reason)
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("+\(formatDollars(row.savedAmount))")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.green)
                    }
                    if row.id != viewModel.topSavings.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Store breakdown card

    private var storeBreakdownCard: some View {
        InsightsCard {
            VStack(alignment: .leading, spacing: 14) {
                sectionHeader("Spend by Store")

                let total = viewModel.storeSpends.reduce(0) { $0 + $1.amount }

                ForEach(viewModel.storeSpends) { store in
                    VStack(alignment: .leading, spacing: 4) {
                        HStack {
                            Text(store.storeName)
                                .font(.system(size: 14, weight: .medium))
                            Spacer()
                            Text(formatDollars(store.amount))
                                .font(.system(size: 14, weight: .semibold))
                                .foregroundStyle(.primary)
                        }
                        // Progress bar — store's share of total monthly spend
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color(.systemFill))
                                    .frame(height: 6)
                                RoundedRectangle(cornerRadius: 4)
                                    .fill(Color.accentColor)
                                    .frame(
                                        width: total > 0
                                            ? geo.size.width * CGFloat(store.amount / total)
                                            : 0,
                                        height: 6
                                    )
                            }
                        }
                        .frame(height: 6)
                    }
                }
            }
        }
    }

    // MARK: - Rising prices card

    private var risingPricesCard: some View {
        InsightsCard {
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 6) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .foregroundStyle(.orange)
                        .font(.system(size: 14))
                    sectionHeader("Rising Prices")
                }

                ForEach(viewModel.risingPrices) { row in
                    HStack(alignment: .top) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(row.itemName)
                                .font(.system(size: 15, weight: .medium))
                                .foregroundStyle(.primary)
                            Text("Up \(Int(row.changePercent.rounded()))% in \(row.windowDays) days")
                                .font(.system(size: 13))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Text("+\(formatDollars(row.changeDollars))")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(.orange)
                    }
                    if row.id != viewModel.risingPrices.last?.id {
                        Divider()
                    }
                }
            }
        }
    }

    // MARK: - Shared helpers

    private func sectionHeader(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium))
            .foregroundStyle(.secondary)
            .textCase(.uppercase)
            .kerning(0.5)
    }

    nonisolated private func formatDollars(_ value: Double) -> String {
        String(format: "$%.2f", abs(value))
    }

    nonisolated private func formatDeltaDollars(_ value: Double) -> String {
        String(format: "$%.2f", abs(value))
    }
}

// MARK: - InsightsCard

/// Reusable white card container used by every section on the Insights tab.
struct InsightsCard<Content: View>: View {
    let content: Content

    init(@ViewBuilder content: () -> Content) {
        self.content = content()
    }

    var body: some View {
        content
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
