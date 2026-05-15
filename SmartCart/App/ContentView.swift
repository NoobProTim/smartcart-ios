// ContentView.swift — SmartCart/App/ContentView.swift
//
// Root tab container. Four tabs matching wireframe spec:
//   Home (cart), Alerts (bell), History (chart.line), Settings (gear)
// Scanner stays as FAB on HomeView — no dedicated Scan tab.

import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            HomeView()
                .tabItem {
                    Label("Home", systemImage: "house")
                }
            AlertsView()
                .tabItem {
                    Label("Alerts", systemImage: "bell")
                }
            HistoryTabView()
                .tabItem {
                    Label("History", systemImage: "chart.line.uptrend.xyaxis")
                }
            NavigationStack {
                SettingsView()
            }
            .tabItem {
                Label("Settings", systemImage: "gearshape")
            }
        }
    }
}

// MARK: - HistoryTabView
// Lists all tracked items; tapping one opens its individual PriceHistoryView.
struct HistoryTabView: View {
    @State private var items: [UserItem] = []

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "chart.line.uptrend.xyaxis")
                            .font(.system(size: 48))
                            .foregroundStyle(.secondary)
                        Text("No price history yet")
                            .font(.headline)
                        Text("Scan a receipt to start tracking prices.")
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    List(items) { item in
                        NavigationLink(destination: PriceHistoryView(item: item)) {
                            VStack(alignment: .leading, spacing: 3) {
                                Text(item.nameDisplay)
                                    .font(.system(size: 15, weight: .medium))
                                if let price = item.lastPurchasedPrice {
                                    Text("Last: \(price, format: .currency(code: "CAD"))")
                                        .font(.system(size: 12))
                                        .foregroundStyle(.secondary)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                    .listStyle(.insetGrouped)
                }
            }
            .navigationTitle("Price History")
            .onAppear { items = DatabaseManager.shared.fetchUserItems() }
        }
    }
}
