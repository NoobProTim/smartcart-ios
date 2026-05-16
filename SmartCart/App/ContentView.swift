// ContentView.swift — SmartCart/App/ContentView.swift
//
// Root tab container. Five tabs: Home, Flyers, My List, Insights, Settings.
// GroceryListViewModel lives here as @StateObject and is injected as an
// environmentObject so every child screen shares one source of truth for
// the grocery list count (tab badge + list view).
//
// Sprint 2 fix: InsightsView wired at tag(3). Settings bumped to tag(4).

import SwiftUI

struct ContentView: View {
    @StateObject private var cartVM = GroceryListViewModel()
    @State private var selectedTab = 1  // Flyers tab until the user has list items

    var body: some View {
        TabView(selection: $selectedTab) {

            // Tab 0 — Home: Smart List + On Sale Now segment
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }
                .tag(0)

            // Tab 1 — Flyers: Flipp deal discovery
            FlyersView()
                .tabItem { Label("Flyers", systemImage: "tag") }
                .tag(1)

            // Tab 2 — My List: pre-shop grocery list with savings banner
            NavigationStack {
                GroceryListView()
            }
            .tabItem { Label("My List", systemImage: "cart.fill") }
            .badge(cartVM.items.count > 0 ? cartVM.items.count : 0)
            .tag(2)

            // Tab 3 — Insights: monthly spend, weekly chart, savings, store breakdown
            // Sprint 2: this tab was built but not wired — fixed here.
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
        .onAppear {
            cartVM.load()
            // Return users who already have items land on Home.
            // New users (empty list) stay on the Flyers discovery tab.
            if !cartVM.items.isEmpty { selectedTab = 0 }
        }
    }
}
