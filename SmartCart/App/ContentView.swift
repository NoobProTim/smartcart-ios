// ContentView.swift — SmartCart/App/ContentView.swift
//
// Root tab container. Five tabs: Home, Deals, My List, Insights, Settings.
// GroceryListViewModel lives here as @StateObject and is injected as an
// environmentObject so every child screen shares one source of truth for
// the grocery list count (tab badge + list view).
//
// Sprint 2 fix: InsightsView wired at tag(3). Settings bumped to tag(4).
// GAP-1 fix: tab label changed from "Flyers" to "Deals" to match wireframe.

import SwiftUI

struct ContentView: View {
    @StateObject private var cartVM = GroceryListViewModel()
    // selectedTab is exposed as an environmentObject so child screens
    // (e.g. GroceryListView empty state) can switch tabs programmatically.
    @State var selectedTab = 1  // Deals tab until the user has list items

    var body: some View {
        TabView(selection: $selectedTab) {
            // Tab 0 — Home: Smart List + On Sale Now segment
            HomeView(onBrowseDealsTapped: { selectedTab = 1 })
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            // Tab 1 — Deals: Flipp deal discovery (GAP-1: was "Flyers")
            FlyersView()
                .tabItem { Label("Deals", systemImage: "tag") }
                .tag(1)

            // Tab 2 — My List: pre-shop grocery list with savings banner
            NavigationStack {
                GroceryListView()
            }
            .tabItem { Label("My List", systemImage: "cart.fill") }
            .badge(cartVM.items.count > 0 ? cartVM.items.count : 0)
            .tag(2)

            // Tab 3 — Insights: monthly spend, weekly chart, savings, store breakdown
            NavigationStack {
                InsightsView()
            }
            .tabItem { Label("Insights", systemImage: "chart.bar.fill") }
            .tag(3)

            // Tab 4 — Settings
            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(4)
        }
        .environmentObject(cartVM)
        .environment(\.selectedTab, $selectedTab)
        .onAppear {
            cartVM.load()
            // Return users who already have items land on Home.
            // New users (empty list) stay on the Deals discovery tab.
            if !cartVM.items.isEmpty { selectedTab = 0 }
        }
    }
}

// MARK: - SelectedTab environment key
// Lets any child view switch the root tab by writing to this binding.
// Usage: @Environment(\.selectedTab) private var selectedTab
private struct SelectedTabKey: EnvironmentKey {
    static let defaultValue: Binding<Int> = .constant(0)
}

extension EnvironmentValues {
    var selectedTab: Binding<Int> {
        get { self[SelectedTabKey.self] }
        set { self[SelectedTabKey.self] = newValue }
    }
}
