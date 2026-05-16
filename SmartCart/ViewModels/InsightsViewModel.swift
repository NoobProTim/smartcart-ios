// InsightsViewModel.swift
// SmartCart
//
// ViewModel for the Insights tab.
// Reads purchase_history and price_history from SQLite to produce
// spend summaries, savings calculations, and rising-price warnings.
// All database work happens off the main thread; @Published properties
// are assigned on MainActor so SwiftUI updates safely.

import Foundation
import Combine

// MARK: - Supporting data shapes

/// One bar in the weekly spend chart (label + dollar amount).
struct WeeklySpendBar: Identifiable {
    let id = UUID()
    let label: String        // e.g. "W1", "W2"
    let amount: Double       // total spend for that calendar week
}

/// A single "you saved money on this item" row.
struct SavingsRow: Identifiable {
    let id = UUID()
    let itemName: String
    let reason: String       // e.g. "Bought 3× below your average"
    let savedAmount: Double  // positive dollar value
}

/// A single "this item is getting more expensive" warning row.
struct RisingPriceRow: Identifiable {
    let id = UUID()
    let itemName: String
    let changePercent: Double   // e.g. 18.0 means +18%
    let changeDollars: Double   // e.g. 1.20 means +$1.20
    let windowDays: Int         // e.g. 90
}

/// Per-store spend summary (for the pie/bar breakdown).
struct StoreSpend: Identifiable {
    let id = UUID()
    let storeName: String
    let amount: Double
}

// MARK: - ViewModel

@MainActor
final class InsightsViewModel: ObservableObject {

    // --- Published state that the View reads ---

    /// Total spend in the current calendar month, formatted as a dollar string.
    @Published var monthTotalFormatted: String = "$0.00"

    /// Dollar change vs. last month (negative = you spent less = good).
    @Published var monthDelta: Double = 0.0

    /// True when monthDelta means the user spent less than last month.
    @Published var deltaIsGood: Bool = true

    /// Four weekly spend bars for the current month.
    @Published var weeklyBars: [WeeklySpendBar] = []

    /// Top items where the user paid below their rolling average.
    @Published var topSavings: [SavingsRow] = []

    /// Per-store spend breakdown for the current month.
    @Published var storeSpends: [StoreSpend] = []

    /// Items whose average price has risen meaningfully over 90 days.
    @Published var risingPrices: [RisingPriceRow] = []

    /// True while the first data load is in progress.
    @Published var isLoading: Bool = false

    // --- Private helpers ---

    private let db = DatabaseManager.shared

    // MARK: - Public interface

    /// Call this from .onAppear or .task to populate all sections.
    func load() {
        Task {
            isLoading = true
            await computeAll()
            isLoading = false
        }
    }

    // MARK: - Computation

    /// Orchestrates all four data sections.
    private func computeAll() async {
        // Run sequentially — SQLite.swift is not safe for concurrent reads
        // on the same connection.
        let monthResult   = computeMonthSpend()
        let weekResult    = computeWeeklyBars()
        let savingsResult = computeTopSavings()
        let storeResult   = computeStoreSpends()
        let risingResult  = computeRisingPrices()

        monthTotalFormatted = formatDollars(monthResult.total)
        monthDelta          = monthResult.delta
        deltaIsGood         = monthResult.delta <= 0
        weeklyBars          = weekResult
        topSavings          = savingsResult
        storeSpends         = storeResult
        risingPrices        = risingResult
    }

    // MARK: - Month spend

    /// Returns (total spend this month, delta vs last month).
    private func computeMonthSpend() -> (total: Double, delta: Double) {
        let calendar = Calendar.current
        let now = Date()

        guard let thisMonthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) else { return (0, 0) }

        guard let lastMonthStart = calendar.date(
            byAdding: .month, value: -1, to: thisMonthStart
        ) else { return (0, 0) }

        let thisTotal = db.totalSpend(from: thisMonthStart, to: now)
        let lastTotal = db.totalSpend(from: lastMonthStart, to: thisMonthStart)
        let delta     = thisTotal - lastTotal

        return (thisTotal, delta)
    }

    // MARK: - Weekly bars

    /// Splits the current calendar month into up to 4 week buckets.
    private func computeWeeklyBars() -> [WeeklySpendBar] {
        let calendar = Calendar.current
        let now = Date()

        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) else { return [] }

        var bars: [WeeklySpendBar] = []
        for weekIndex in 0..<4 {
            guard let weekStart = calendar.date(
                byAdding: .day, value: weekIndex * 7, to: monthStart
            ) else { continue }
            guard let weekEnd = calendar.date(
                byAdding: .day, value: 7, to: weekStart
            ) else { continue }

            if weekStart > now { break }

            let clampedEnd = min(weekEnd, now)
            let amount = db.totalSpend(from: weekStart, to: clampedEnd)
            bars.append(WeeklySpendBar(label: "W\(weekIndex + 1)", amount: amount))
        }
        return bars
    }

    // MARK: - Top savings

    /// Items where the user paid below their 90-day rolling average this month.
    private func computeTopSavings() -> [SavingsRow] {
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) else { return [] }

        let purchases = db.purchasesInRange(from: monthStart, to: now)
        var savingsByItem: [String: (count: Int, totalSaved: Double)] = [:]

        for purchase in purchases {
            guard purchase.price > 0 else { continue }
            let avg = db.rollingAveragePrice(itemID: purchase.itemID, days: 90)
            guard avg > 0, purchase.price < avg else { continue }

            let saved = avg - purchase.price
            let existing = savingsByItem[purchase.itemName] ?? (0, 0)
            savingsByItem[purchase.itemName] = (
                existing.count + 1,
                existing.totalSaved + saved
            )
        }

        let rows = savingsByItem.compactMap { name, data -> SavingsRow? in
            guard data.totalSaved > 0 else { return nil }
            let reason = data.count > 1
                ? "Bought \(data.count)× below your average"
                : "Bought below your average"
            return SavingsRow(itemName: name, reason: reason, savedAmount: data.totalSaved)
        }
        .sorted { $0.savedAmount > $1.savedAmount }

        return Array(rows.prefix(5))
    }

    // MARK: - Store spend breakdown

    /// Sums purchase_history by store_name for the current calendar month.
    private func computeStoreSpends() -> [StoreSpend] {
        let calendar = Calendar.current
        let now = Date()
        guard let monthStart = calendar.date(
            from: calendar.dateComponents([.year, .month], from: now)
        ) else { return [] }

        return db.spendByStore(from: monthStart, to: now)
            .sorted { $0.value > $1.value }
            .map { StoreSpend(storeName: $0.key, amount: $0.value) }
    }

    // MARK: - Rising prices

    /// Items whose average price rose ≥10% over the past 90 days vs prior 90 days.
    private func computeRisingPrices() -> [RisingPriceRow] {
        let now = Date()
        let calendar = Calendar.current

        guard let ninetyDaysAgo = calendar.date(byAdding: .day, value: -90, to: now),
              let oneEightyDaysAgo = calendar.date(byAdding: .day, value: -180, to: now)
        else { return [] }

        return db.fetchAllUserItems().compactMap { item in
            let recentAvg = db.averagePrice(itemID: item.itemID, from: ninetyDaysAgo, to: now)
            let priorAvg  = db.averagePrice(itemID: item.itemID, from: oneEightyDaysAgo, to: ninetyDaysAgo)

            guard recentAvg > 0, priorAvg > 0 else { return nil }

            let changePercent = ((recentAvg - priorAvg) / priorAvg) * 100.0
            let changeDollars = recentAvg - priorAvg

            guard changePercent >= 10.0 else { return nil }

            return RisingPriceRow(
                itemName: item.name,
                changePercent: changePercent,
                changeDollars: changeDollars,
                windowDays: 90
            )
        }
        .sorted { $0.changePercent > $1.changePercent }
    }

    // MARK: - Utilities

    /// Formats a Double as a CAD currency string (e.g. 284.5 → "$284.50").
    nonisolated private func formatDollars(_ value: Double) -> String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .currency
        formatter.currencyCode = "CAD"
        formatter.currencySymbol = "$"
        formatter.maximumFractionDigits = 2
        formatter.minimumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? "$0.00"
    }
}
