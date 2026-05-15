// SmartCartApp.swift — SmartCart/App/SmartCartApp.swift
//
// App entry point. Registers background tasks and seeds the database
// before the first view appears.

import SwiftUI

@main
struct SmartCartApp: App {

    @StateObject private var notificationRouter = NotificationRouter()
    @State private var onboardingStep: OnboardingStep = .unknown

    private enum OnboardingStep { case unknown, carousel, setup, done }

    init() {
        BackgroundSyncManager.shared.registerBackgroundTask()
        BackgroundSyncManager.shared.scheduleNextRefresh()
        _ = DatabaseManager.shared
    }

    var body: some Scene {
        WindowGroup {
            Group {
                switch onboardingStep {
                case .unknown:
                    Color(.systemBackground).ignoresSafeArea()
                case .carousel:
                    OnboardingCarouselView(onComplete: {
                        onboardingStep = .setup
                    })
                case .setup:
                    OnboardingSetupView(onComplete: {
                        DatabaseManager.shared.setSetting(key: "onboarding_complete", value: "1")
                        onboardingStep = .done
                    })
                case .done:
                    ContentView()
                        .environmentObject(notificationRouter)
                }
            }
            .onAppear {
                let done = DatabaseManager.shared.getSetting(key: "onboarding_complete") == "1"
                onboardingStep = done ? .done : .carousel
            }
        }
    }
}
