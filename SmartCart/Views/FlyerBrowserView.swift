// FlyerBrowserView.swift — SmartCart/Views/FlyerBrowserView.swift
//
// Sprint 3: Full-flyer browse mode.
// This screen is GATED — it requires written Flipp API approval before
// the embedded WebView can be enabled. Until legal clearance is received,
// the screen shows a "Coming Soon" pending-approval card so the tab slot
// is reserved and users understand the feature is intentional.
//
// GAP-2 fix: now accepts a storeName parameter so FlyersView can pass
// the selected store through. The store name drives the pending-approval
// card heading and will drive the WKWebView URL once approved.
//
// When Flipp approval arrives:
//   1. Replace pendingApprovalContent with a WKWebView wrapper loading
//      the Flipp embed URL for the user's postal code + storeName.
//   2. Remove the gated banner.
//   3. Update Memory Blocks to mark Flipp compliance as resolved.

import SwiftUI

struct FlyerBrowserView: View {

    // Store name passed in from FlyersView when a store tile is tapped.
    // Shown in the card heading and will be used for the WKWebView URL.
    let storeName: String

    init(storeName: String = "") {
        self.storeName = storeName
    }

    // Set to true only after Flipp legal approval is confirmed.
    // Controlled by a DB setting so it can be toggled remotely via a
    // future admin flag without a new app build.
    private var isApproved: Bool {
        DatabaseManager.shared.getSetting(key: "flipp_browser_approved") == "1"
    }

    var body: some View {
        Group {
            if isApproved {
                // TODO(P2-FlyerBrowser): Replace with WKWebView embed
                // loading Flipp URL for user's postal code + storeName once approved.
                Text("Flyer browser enabled.")
                    .foregroundStyle(.secondary)
            } else {
                pendingApprovalContent
            }
        }
        .navigationTitle(storeName.isEmpty ? "Store Flyers" : storeName)
        .navigationBarTitleDisplayMode(.large)
    }

    // MARK: - pendingApprovalContent
    // Card shown while Flipp legal approval is pending.
    // Shows the selected store name prominently so it's clear which store
    // the user tapped. Explains why the screen is not yet interactive.
    private var pendingApprovalContent: some View {
        VStack(spacing: 0) {
            Spacer()

            VStack(spacing: 20) {
                // Store badge (if a store was selected)
                if !storeName.isEmpty {
                    StoreBadgeView(name: storeName)
                        .scaleEffect(1.4)
                }

                // Icon
                ZStack {
                    Circle()
                        .fill(Color.accentColor.opacity(0.10))
                        .frame(width: 80, height: 80)
                    Image(systemName: "doc.text.magnifyingglass")
                        .font(.system(size: 34))
                        .foregroundStyle(Color.accentColor)
                }

                // Title + body
                VStack(spacing: 8) {
                    Text(storeName.isEmpty ? "Full Flyer Browse" : "\(storeName) Flyers")
                        .font(.system(size: 20, weight: .bold))
                    Text("We're finalising our agreement with Flipp to show you full store flyers in-app. This feature will unlock automatically — no update needed.")
                        .font(.system(size: 15))
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 8)
                }

                // Status pill
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color.orange)
                        .frame(width: 7, height: 7)
                    Text("Pending approval")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 14)
                .padding(.vertical, 8)
                .background(Color(.secondarySystemGroupedBackground))
                .clipShape(Capsule())

                // What you can do now — directs user back to Deals tab
                Text("In the meantime, use the Deals tab to see this week's best prices from \(storeName.isEmpty ? "your stores" : storeName).")
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 16)
            }
            .padding(32)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 20))
            .padding(.horizontal, 24)

            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

#Preview {
    NavigationStack {
        FlyerBrowserView(storeName: "No Frills")
    }
}
