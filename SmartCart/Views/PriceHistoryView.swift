// PriceHistoryView.swift — SmartCart/Views/PriceHistoryView.swift
//
// Shows price history chart + active sales for a single tracked item.

import SwiftUI
import Charts

struct PriceHistoryView: View {

    let item: UserItem
    @StateObject private var vm: PriceHistoryViewModel
    @Environment(\.dismiss) private var dismiss

    init(item: UserItem) {
        self.item = item
        _vm = StateObject(wrappedValue: PriceHistoryViewModel(item: item))
    }

    var body: some View {
        NavigationStack {
            Group {
                if vm.isLoading {
                    ProgressView()
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    content
                }
            }
            .navigationTitle(item.nameDisplay)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                }
            }
            .onAppear { vm.load() }
        }
    }

    private var content: some View {
        List {
            // Price chart
            if !vm.pricePoints.isEmpty {
                Section("Price History") {
                    Chart(vm.pricePoints) { point in
                        LineMark(
                            x: .value("Date", point.observedAt),
                            y: .value("Price", point.price)
                        )
                        .foregroundStyle(.blue)
                        PointMark(
                            x: .value("Date", point.observedAt),
                            y: .value("Price", point.price)
                        )
                        .foregroundStyle(.blue)
                    }
                    .frame(height: 180)
                    .chartXAxis {
                        AxisMarks(values: .stride(by: .month)) {
                            AxisGridLine()
                            AxisValueLabel(format: .dateTime.month(.abbreviated))
                        }
                    }
                }
            }

            // Stats
            Section("Stats") {
                if let avg = vm.rollingAvg90 {
                    LabeledContent("90-day avg", value: "$\(String(format: "%.2f", avg))")
                }
                if let low = vm.historicalLow {
                    LabeledContent("90-day low", value: "$\(String(format: "%.2f", low))")
                }
                if let cycle = item.effectiveCycleDays {
                    LabeledContent("Restock cycle", value: "~\(cycle) days")
                }
                if let next = item.nextRestockDate {
                    LabeledContent("Next restock", value: next.formatted(date: .abbreviated, time: .omitted))
                }
            }

            // Active sales
            if !vm.activeSales.isEmpty {
                Section("Active Sales") {
                    ForEach(vm.activeSales) { sale in
                        VStack(alignment: .leading, spacing: 4) {
                            HStack {
                                Text("$\(String(format: "%.2f", sale.salePrice))")
                                    .font(.headline)
                                    .foregroundStyle(.green)
                                if let reg = sale.regularPrice {
                                    Text("(was $\(String(format: "%.2f", reg)))")
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                            }
                            if let end = sale.validTo {
                                Text("Sale ends \(end.formatted(date: .abbreviated, time: .omitted))")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            }
        }
    }
}
