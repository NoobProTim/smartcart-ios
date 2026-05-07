// EmptyCTAView.swift
// SmartCart — Views/EmptyCTAView.swift
//
// Empty state shown on HomeView when the user has no tracked items.
// Animation: the receipt icon floats up and down gently (infinite loop).

import SwiftUI

struct EmptyCTAView: View {
    let onScanTapped: () -> Void
    @State private var isFloating = false
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle().fill(Color.accentColor.opacity(0.08)).frame(width: 120, height: 120)
                Image(systemName: "doc.text.viewfinder")
                    .font(.system(size: 56, weight: .light)).foregroundStyle(Color.accentColor)
                    .offset(y: isFloating ? -8 : 0)
                    .animation(.easeInOut(duration: 2.0).repeatForever(autoreverses: true), value: isFloating)
            }
            .padding(.bottom, 32).opacity(appeared ? 1 : 0)
            .animation(.easeOut(duration: 0.5).delay(0.1), value: appeared)

            Text("Scan your first receipt")
                .font(.system(size: 22, weight: .bold)).foregroundStyle(.primary)
                .multilineTextAlignment(.center).padding(.bottom, 10)
                .opacity(appeared ? 1 : 0).animation(.easeOut(duration: 0.5).delay(0.2), value: appeared)

            Text("SmartCart learns your prices and tells you\nwhen it's the right time to stock up.")
                .font(.system(size: 15)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).lineSpacing(4)
                .padding(.horizontal, 40).padding(.bottom, 40)
                .opacity(appeared ? 1 : 0).animation(.easeOut(duration: 0.5).delay(0.3), value: appeared)

            Button(action: onScanTapped) {
                HStack(spacing: 10) {
                    Image(systemName: "camera.viewfinder").font(.system(size: 18, weight: .semibold))
                    Text("Scan a Receipt").font(.system(size: 16, weight: .semibold))
                }
                .foregroundStyle(.white).padding(.horizontal, 32).padding(.vertical, 16)
                .background(Color.accentColor).clipShape(Capsule())
                .shadow(color: Color.accentColor.opacity(0.35), radius: 12, x: 0, y: 6)
            }
            .accessibilityLabel("Scan a grocery receipt to get started")
            .opacity(appeared ? 1 : 0).animation(.easeOut(duration: 0.5).delay(0.4), value: appeared)

            Spacer(); Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            appeared = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { isFloating = true }
        }
        .onDisappear { appeared = false; isFloating = false }
    }
}
