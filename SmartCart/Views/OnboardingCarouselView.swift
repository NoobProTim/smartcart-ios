// OnboardingCarouselView.swift
// SmartCart — Views/OnboardingCarouselView.swift
//
// Task #2 — Part 2: Onboarding Value Prop Carousel (Step 0)
//
// Three slides shown BEFORE the store picker. Addresses PRISM P1-4:
// new users previously jumped straight into store selection with no
// context about what SmartCart does.
//
// Slide content:
//   1. Scan receipts    — doc.text.viewfinder  — "Scan your receipts"
//   2. Track prices     — chart.line.uptrend   — "We track the prices"
//   3. Get alerts       — bell.badge.fill       — "Get alerted at the right time"
//
// "Get Started" on the last slide calls onComplete().
// "Skip" on any slide also calls onComplete().

import SwiftUI

private struct CarouselSlide {
    let icon: String
    let iconColor: Color
    let headline: String
    let body: String
}

private let slides: [CarouselSlide] = [
    CarouselSlide(
        icon: "doc.text.viewfinder",
        iconColor: .accentColor,
        headline: "Scan your receipts",
        body: "Point your camera at any grocery receipt. SmartCart reads every item and price automatically."
    ),
    CarouselSlide(
        icon: "chart.line.uptrend.xyaxis",
        iconColor: .green,
        headline: "We track the prices",
        body: "SmartCart builds a price history for everything you buy, learning what's normal and what's genuinely cheap."
    ),
    CarouselSlide(
        icon: "bell.badge.fill",
        iconColor: .orange,
        headline: "Get alerted at the right time",
        body: "When a price hits a real low just as you're running out, SmartCart lets you know. Maximum 3 alerts a day."
    )
]

struct OnboardingCarouselView: View {
    let onComplete: () -> Void

    @State private var currentIndex = 0

    var body: some View {
        ZStack(alignment: .topTrailing) {
            VStack(spacing: 0) {
                TabView(selection: $currentIndex) {
                    ForEach(slides.indices, id: \.self) { i in
                        SlideView(slide: slides[i]).tag(i)
                    }
                }
                .tabViewStyle(.page(indexDisplayMode: .never))
                .animation(.easeInOut(duration: 0.3), value: currentIndex)

                // Page dots
                HStack(spacing: 8) {
                    ForEach(slides.indices, id: \.self) { i in
                        Capsule()
                            .fill(i == currentIndex ? Color.accentColor : Color.secondary.opacity(0.3))
                            .frame(width: i == currentIndex ? 20 : 8, height: 8)
                            .animation(.spring(response: 0.3), value: currentIndex)
                    }
                }
                .padding(.bottom, 32)

                // CTA button
                Button(action: {
                    if currentIndex < slides.count - 1 {
                        withAnimation { currentIndex += 1 }
                    } else {
                        onComplete()
                    }
                }) {
                    Text(currentIndex == slides.count - 1 ? "Get Started" : "Next")
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundStyle(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 16)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: 14))
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 48)
                .accessibilityLabel(currentIndex == slides.count - 1 ? "Get started with SmartCart" : "Next slide")
            }

            // Skip button — always visible in top-right
            Button("Skip") { onComplete() }
                .font(.system(size: 14, weight: .medium))
                .foregroundStyle(.secondary)
                .padding(.top, 56)
                .padding(.trailing, 24)
                .accessibilityLabel("Skip onboarding")
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }
}

private struct SlideView: View {
    let slide: CarouselSlide
    @State private var appeared = false

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            ZStack {
                Circle()
                    .fill(slide.iconColor.opacity(0.1))
                    .frame(width: 140, height: 140)
                Image(systemName: slide.icon)
                    .font(.system(size: 60, weight: .light))
                    .foregroundStyle(slide.iconColor)
            }
            .scaleEffect(appeared ? 1 : 0.8)
            .opacity(appeared ? 1 : 0)
            .animation(.spring(response: 0.5, dampingFraction: 0.7).delay(0.05), value: appeared)
            .padding(.bottom, 40)

            Text(slide.headline)
                .font(.system(size: 28, weight: .bold))
                .foregroundStyle(.primary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.15), value: appeared)
                .padding(.bottom, 16)

            Text(slide.body)
                .font(.system(size: 16))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .lineSpacing(5)
                .padding(.horizontal, 36)
                .opacity(appeared ? 1 : 0)
                .animation(.easeOut(duration: 0.4).delay(0.25), value: appeared)

            Spacer()
        }
        .onAppear { appeared = true }
        .onDisappear { appeared = false }
    }
}
