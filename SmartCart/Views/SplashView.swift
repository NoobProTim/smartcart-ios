// SplashView.swift
// SmartCart — Views/SplashView.swift
//
// Task #2 — Part 1: Splash / Launch Screen
//
// Shown for ~1.8 seconds while the app initialises the database and
// checks onboarding_complete in user_settings.
// Fades out to OnboardingCarouselView (new user) or HomeView (returning user).
//
// Animation sequence:
//   0.0s — cart icon fades + scales in
//   0.4s — wordmark fades in
//   0.8s — tagline fades in
//   1.8s — whole view fades out, onComplete() fires

import SwiftUI

struct SplashView: View {
    let onComplete: () -> Void

    @State private var iconOpacity: Double = 0
    @State private var iconScale: CGFloat = 0.7
    @State private var wordmarkOpacity: Double = 0
    @State private var taglineOpacity: Double = 0
    @State private var screenOpacity: Double = 1

    var body: some View {
        ZStack {
            // Background — matches the app accent colour
            Color.accentColor.ignoresSafeArea()

            VStack(spacing: 0) {
                Spacer()

                // App icon mark
                ZStack {
                    Circle()
                        .fill(.white.opacity(0.15))
                        .frame(width: 110, height: 110)
                    Image(systemName: "cart.fill")
                        .font(.system(size: 52, weight: .semibold))
                        .foregroundStyle(.white)
                }
                .scaleEffect(iconScale)
                .opacity(iconOpacity)
                .padding(.bottom, 24)

                // Wordmark
                Text("SmartCart")
                    .font(.system(size: 36, weight: .bold, design: .rounded))
                    .foregroundStyle(.white)
                    .opacity(wordmarkOpacity)
                    .padding(.bottom, 10)

                // Tagline
                Text("Buy smart. Stock up at the right time.")
                    .font(.system(size: 15, weight: .regular))
                    .foregroundStyle(.white.opacity(0.8))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
                    .opacity(taglineOpacity)

                Spacer()
                Spacer()
            }
        }
        .opacity(screenOpacity)
        .onAppear { runAnimation() }
        .accessibilityLabel("SmartCart loading")
    }

    private func runAnimation() {
        // Step 1: icon appears
        withAnimation(.spring(response: 0.55, dampingFraction: 0.7).delay(0.1)) {
            iconOpacity = 1
            iconScale = 1
        }
        // Step 2: wordmark
        withAnimation(.easeOut(duration: 0.4).delay(0.4)) {
            wordmarkOpacity = 1
        }
        // Step 3: tagline
        withAnimation(.easeOut(duration: 0.4).delay(0.8)) {
            taglineOpacity = 1
        }
        // Step 4: fade out and hand off
        withAnimation(.easeIn(duration: 0.35).delay(1.8)) {
            screenOpacity = 0
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.1) {
            onComplete()
        }
    }
}
