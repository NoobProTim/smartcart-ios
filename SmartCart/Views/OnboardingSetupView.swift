// OnboardingSetupView.swift
// SmartCart — Views/OnboardingSetupView.swift
//
// Task #2 — Part 3: Onboarding Setup (Store Selection + Postal Code)
//
// This replaces OnboardingView.swift as the definitive onboarding setup screen.
// It is shown AFTER OnboardingCarouselView (value prop slides).
//
// Steps:
//   1. Store picker — chip grid, at least 1 required to proceed
//   2. Postal code  — Canadian format validated (A1A 1A1), skip allowed
//   3. Notifications — UNUserNotificationCenter permission request with denial fallback
//
// PRISM P1-9: Canadian postal code format is validated before saving.
// PRISM P1-4: This screen is only reached after the carousel, never cold.

import SwiftUI
import UserNotifications

struct OnboardingSetupView: View {
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var selectedStores: Set<String> = []
    @State private var postalCode = ""
    @State private var postalCodeError: String? = nil
    @State private var notificationGranted: Bool? = nil
    @State private var showNotificationDenied = false

    private let availableStores = [
        "No Frills", "Loblaws", "Metro", "Food Basics",
        "Sobeys", "FreshCo", "Giant Tiger", "Walmart", "Costco", "T&T"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Step indicator
            HStack(spacing: 8) {
                ForEach(0..<3) { step in
                    Capsule()
                        .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.25))
                        .frame(width: step == currentStep ? 24 : 8, height: 8)
                        .animation(.spring(response: 0.3), value: currentStep)
                }
            }
            .padding(.top, 24).padding(.bottom, 8)

            TabView(selection: $currentStep) {
                storeStep.tag(0)
                postalStep.tag(1)
                notificationStep.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentStep)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    // MARK: — Step 1: Store picker
    private var storeStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeader(
                title: "Which stores do you shop at?",
                subtitle: "SmartCart tracks flyers and prices for your chosen stores."
            )
            ScrollView {
                FlowLayout(spacing: 10) {
                    ForEach(availableStores, id: \.self) { store in
                        StoreChip(
                            name: store,
                            isSelected: selectedStores.contains(store),
                            onTap: {
                                if selectedStores.contains(store) { selectedStores.remove(store) }
                                else { selectedStores.insert(store) }
                            }
                        )
                    }
                }
                .padding(.horizontal, 20)
            }
            Spacer()
            primaryButton(label: "Next", isEnabled: !selectedStores.isEmpty) {
                for storeName in selectedStores {
                    let storeID = DatabaseManager.shared.upsertStore(name: storeName)
                    DatabaseManager.shared.setSetting(key: "store_selected_\(storeID)", value: "1")
                }
                currentStep = 1
            }
        }
        .padding(.bottom, 40)
    }

    // MARK: — Step 2: Postal code
    private var postalStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeader(
                title: "What's your postal code?",
                subtitle: "Finds flyers near you. Never shared or stored off-device."
            )

            VStack(alignment: .leading, spacing: 6) {
                TextField("e.g. K7L 3N6", text: $postalCode)
                    .textInputAutocapitalization(.characters)
                    .keyboardType(.asciiCapable)
                    .font(.system(size: 24, weight: .medium, design: .monospaced))
                    .onChange(of: postalCode) { _ in postalCodeError = nil }
                    .padding(.horizontal, 20)
                    .accessibilityLabel("Postal code input")

                if let error = postalCodeError {
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(.red)
                        .padding(.horizontal, 20)
                        .transition(.opacity)
                }
            }

            Text("You can skip this and add it later in Settings.")
                .font(.system(size: 13)).foregroundStyle(.secondary)
                .padding(.horizontal, 20)

            Spacer()

            HStack(spacing: 12) {
                Button("Skip") { currentStep = 2 }
                    .font(.system(size: 15)).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity).padding(.vertical, 14)
                    .background(Color.secondary.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 12))
                    .accessibilityLabel("Skip postal code")
                    .padding(.leading, 20)

                primaryButton(label: "Next", isEnabled: true) {
                    let normalised = postalCode.uppercased().replacingOccurrences(of: " ", with: "")
                    if normalised.isEmpty {
                        // Empty is fine — same as skip
                        currentStep = 2
                    } else if isValidCanadianPostalCode(normalised) {
                        DatabaseManager.shared.setSetting(key: "user_postal_code", value: normalised)
                        currentStep = 2
                    } else {
                        withAnimation { postalCodeError = "Enter a valid Canadian postal code (e.g. K7L 3N6)" }
                    }
                }
            }
        }
        .padding(.bottom, 40)
    }

    // MARK: — Step 3: Notifications
    private var notificationStep: some View {
        VStack(alignment: .leading, spacing: 20) {
            stepHeader(
                title: "Get price alerts",
                subtitle: "We'll notify you when a tracked item hits a genuine low. Max 3 alerts per day."
            )

            VStack(alignment: .leading, spacing: 16) {
                benefitRow(icon: "chart.line.downtrend.xyaxis", text: "Historical price low detected")
                benefitRow(icon: "tag.fill",                    text: "Sale or flyer event at your stores")
                benefitRow(icon: "clock.badge.exclamationmark", text: "Sale expiring tomorrow — last chance")
            }
            .padding(.horizontal, 20)

            // Denial fallback banner — shown after permission is refused
            if showNotificationDenied {
                HStack(spacing: 10) {
                    Image(systemName: "bell.slash").foregroundStyle(.orange)
                    Text("You can enable alerts any time in iOS Settings → SmartCart.")
                        .font(.system(size: 13)).foregroundStyle(.secondary)
                }
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            Spacer()

            VStack(spacing: 12) {
                if notificationGranted != true {
                    primaryButton(
                        label: "Enable Alerts",
                        isEnabled: true
                    ) { requestNotifications() }
                } else {
                    primaryButton(label: "Alerts enabled \u2714", isEnabled: false) {}
                }

                Button("Maybe later") { onComplete() }
                    .font(.system(size: 14)).foregroundStyle(.secondary)
                    .accessibilityLabel("Skip notifications for now")
            }
        }
        .padding(.bottom, 40)
        .onAppear {
            UNUserNotificationCenter.current().getNotificationSettings { settings in
                DispatchQueue.main.async {
                    if settings.authorizationStatus == .authorized { notificationGranted = true }
                }
            }
        }
    }

    // MARK: — Helpers

    private func requestNotifications() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                notificationGranted = granted
                DatabaseManager.shared.setSetting(key: "notification_enabled", value: granted ? "1" : "0")
                if granted {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onComplete() }
                } else {
                    withAnimation { showNotificationDenied = true }
                }
            }
        }
    }

    // PRISM P1-9: Validates Canadian postal code format A1A1A1 (spaces stripped).
    // Valid: letters in positions 0,2,4; digits in positions 1,3,5.
    // First character must not be D, F, I, O, Q, or U (reserved by Canada Post).
    private func isValidCanadianPostalCode(_ code: String) -> Bool {
        let reserved: Set<Character> = ["D", "F", "I", "O", "Q", "U"]
        guard code.count == 6 else { return false }
        let chars = Array(code)
        let letterPositions = [0, 2, 4]
        let digitPositions  = [1, 3, 5]
        for i in letterPositions { guard chars[i].isLetter else { return false } }
        for i in digitPositions  { guard chars[i].isNumber else { return false } }
        guard !reserved.contains(chars[0]) else { return false }
        return true
    }

    private func stepHeader(title: String, subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 26, weight: .bold)).foregroundStyle(.primary)
            Text(subtitle).font(.system(size: 15)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.top, 16)
    }

    private func primaryButton(label: String, isEnabled: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(isEnabled ? Color.accentColor : Color.secondary.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!isEnabled).padding(.horizontal, 20).accessibilityLabel(label)
    }

    private func benefitRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Color.accentColor).frame(width: 28)
            Text(text).font(.system(size: 15)).foregroundStyle(.primary)
        }
    }
}
