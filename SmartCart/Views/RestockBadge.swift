// RestockBadge.swift — SmartCart/Views/RestockBadge.swift
//
// Compact coloured badge shown on each Smart List row.
// Driven by RestockStatus from ReplenishmentEngine.
//
// Visual spec:
//   .due              — red pill, “Restock”
//   .approaching      — orange pill, “Soon”
//   .ok               — no badge (empty view, preserves row layout)
//   .seasonalSuppressed — gray pill, season snowflake icon

import SwiftUI

struct RestockBadge: View {
    let status: RestockStatus

    var body: some View {
        switch status {
        case .due:
            badge(text: "Restock", icon: "arrow.clockwise.circle.fill", tint: .red)
        case .approaching:
            badge(text: "Soon", icon: "clock.fill", tint: .orange)
        case .ok:
            // No badge — keeps trailing space stable so row heights don't jump.
            Color.clear
                .frame(width: 0, height: 24)
        case .seasonalSuppressed:
            badge(text: "Seasonal", icon: "snowflake", tint: .gray)
        }
    }

    @ViewBuilder
    private func badge(text: String, icon: String, tint: Color) -> some View {
        Label(text, systemImage: icon)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(tint.opacity(0.12))
            .clipShape(Capsule())
    }
}

// MARK: - Preview
#Preview {
    VStack(spacing: 12) {
        RestockBadge(status: .due)
        RestockBadge(status: .approaching)
        RestockBadge(status: .ok)
        RestockBadge(status: .seasonalSuppressed)
    }
    .padding()
}
