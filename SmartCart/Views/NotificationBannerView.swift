// NotificationBannerView.swift
// SmartCart — Views/NotificationBannerView.swift
//
// Amber nudge banner shown on HomeView when notification permission is denied.
// Displayed as a safeAreaInset — NOT a modal or alert.

import SwiftUI

struct NotificationBannerView: View {
    let onDismiss: () -> Void
    let onEnable: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "bell.slash.fill").font(.system(size: 16)).foregroundStyle(.white.opacity(0.9))
            VStack(alignment: .leading, spacing: 2) {
                Text("Notifications are off").font(.system(size: 13, weight: .semibold)).foregroundStyle(.white)
                Text("Enable to receive price alerts.").font(.system(size: 12)).foregroundStyle(.white.opacity(0.85))
            }
            Spacer()
            Button(action: onEnable) {
                Text("Enable").font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Color(.systemBackground))
                    .padding(.horizontal, 12).padding(.vertical, 6)
                    .background(.white.opacity(0.25)).clipShape(Capsule())
            }
            .accessibilityLabel("Enable notifications in Settings")
            Button(action: onDismiss) {
                Image(systemName: "xmark").font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.8)).padding(6)
            }
            .accessibilityLabel("Dismiss notification banner")
        }
        .padding(.horizontal, 16).padding(.vertical, 12)
        .background(RoundedRectangle(cornerRadius: 14).fill(Color.orange))
        .padding(.horizontal, 16).padding(.bottom, 8)
    }
}
