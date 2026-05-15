// ContentView.swift — SmartCart/App/ContentView.swift
//
// Root tab container. Four tabs: Home, Flyers, My List, Settings.
// GroceryListViewModel lives here and is injected as an environment object
// so the tab badge and the list view share a single source of truth.

import SwiftUI

struct ContentView: View {
    @StateObject private var cartVM = GroceryListViewModel()

    var body: some View {
        TabView {
            HomeView()
                .tabItem { Label("Home", systemImage: "house") }

            FlyersView()
                .tabItem { Label("Flyers", systemImage: "tag") }

            NavigationStack {
                GroceryListView()
            }
            .tabItem { Label("My List", systemImage: "cart.fill") }
            .badge(cartVM.items.count > 0 ? cartVM.items.count : 0)

            NavigationStack {
                SettingsView()
            }
            .tabItem { Label("Settings", systemImage: "gearshape") }
        }
        .environmentObject(cartVM)
        .onAppear { cartVM.load() }
    }
}
