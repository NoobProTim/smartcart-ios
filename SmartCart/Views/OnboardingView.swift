// OnboardingView.swift
// SmartCart — Views/OnboardingView.swift
//
// First-launch flow. Three steps:
//   1. Store picker — which grocery chains to track
//   2. Postal code  — used by Flipp to localise flyer results
//   3. Notifications — request UNUserNotificationCenter permission
//
// onComplete() is called by the final step and received by RootView,
// which sets onboarding_complete = "1" and shows HomeView.

import SwiftUI
import UserNotifications

struct OnboardingView: View {
    let onComplete: () -> Void

    @State private var currentStep = 0
    @State private var selectedStores: Set<String> = []
    @State private var postalCode = ""
    @State private var notificationGranted: Bool? = nil

    private let availableStores = [
        "No Frills", "Loblaws", "Metro", "Food Basics",
        "Sobeys", "FreshCo", "Giant Tiger", "Walmart", "Costco", "T&T"
    ]

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                ForEach(0..<3) { step in
                    Circle()
                        .fill(step == currentStep ? Color.accentColor : Color.secondary.opacity(0.3))
                        .frame(width: 8, height: 8)
                        .animation(.easeInOut(duration: 0.2), value: currentStep)
                }
            }
            .padding(.top, 24).padding(.bottom, 8)

            TabView(selection: $currentStep) {
                storePickerStep.tag(0)
                postalCodeStep.tag(1)
                notificationStep.tag(2)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))
            .animation(.easeInOut(duration: 0.3), value: currentStep)
        }
        .background(Color(.systemBackground).ignoresSafeArea())
    }

    private var storePickerStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(
                title: "Which stores do you shop at?",
                subtitle: "SmartCart tracks prices and flyers for your chosen stores."
            )
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
            Spacer()
            OnboardingNextButton(label: "Next", isEnabled: !selectedStores.isEmpty) {
                for storeName in selectedStores {
                    let storeID = DatabaseManager.shared.upsertStore(name: storeName)
                    DatabaseManager.shared.setSetting(key: "store_selected_\(storeID)", value: "1")
                }
                currentStep = 1
            }
        }
        .padding(.bottom, 40)
    }

    private var postalCodeStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(
                title: "What's your postal code?",
                subtitle: "Used to find flyers and sales near you. Never shared."
            )
            TextField("e.g. K7L 3N6", text: $postalCode)
                .textInputAutocapitalization(.characters)
                .keyboardType(.asciiCapable)
                .font(.system(size: 24, weight: .medium, design: .monospaced))
                .padding(.horizontal, 20)
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
                OnboardingNextButton(label: "Next", isEnabled: true) {
                    let normalised = postalCode.uppercased().replacingOccurrences(of: " ", with: "")
                    if !normalised.isEmpty {
                        DatabaseManager.shared.setSetting(key: "user_postal_code", value: normalised)
                    }
                    currentStep = 2
                }
            }
            .padding(.horizontal, 20)
        }
        .padding(.bottom, 40)
    }

    private var notificationStep: some View {
        VStack(alignment: .leading, spacing: 24) {
            OnboardingHeader(
                title: "Get price alerts",
                subtitle: "SmartCart notifies you when a tracked item hits a new low or goes on sale. Maximum 3 alerts per day."
            )
            VStack(alignment: .leading, spacing: 16) {
                NotificationBenefit(icon: "chart.line.downtrend.xyaxis", text: "Historical price low detected")
                NotificationBenefit(icon: "tag.fill", text: "Sale or flyer event at your stores")
                NotificationBenefit(icon: "clock.badge.exclamationmark", text: "Sale expiring tomorrow — last chance")
            }
            .padding(.horizontal, 20)
            Spacer()
            VStack(spacing: 12) {
                OnboardingNextButton(
                    label: notificationGranted == true ? "Alerts enabled ✔" : "Enable Alerts",
                    isEnabled: notificationGranted != true
                ) { requestNotificationPermission() }
                Button("Maybe later") { onComplete() }
                    .font(.system(size: 14)).foregroundStyle(.secondary)
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

    private func requestNotificationPermission() {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            DispatchQueue.main.async {
                notificationGranted = granted
                DatabaseManager.shared.setSetting(key: "notification_enabled", value: granted ? "1" : "0")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.6) { onComplete() }
            }
        }
    }
}

struct OnboardingHeader: View {
    let title: String
    let subtitle: String
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.system(size: 26, weight: .bold)).foregroundStyle(.primary)
            Text(subtitle).font(.system(size: 15)).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20).padding(.top, 16)
    }
}

struct OnboardingNextButton: View {
    let label: String
    let isEnabled: Bool
    let action: () -> Void
    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 16, weight: .semibold)).foregroundStyle(.white)
                .frame(maxWidth: .infinity).padding(.vertical, 16)
                .background(isEnabled ? Color.accentColor : Color.secondary.opacity(0.4))
                .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .disabled(!isEnabled).padding(.horizontal, 20).accessibilityLabel(label)
    }
}

struct StoreChip: View {
    let name: String
    let isSelected: Bool
    let onTap: () -> Void
    var body: some View {
        Button(action: onTap) {
            Text(name).font(.system(size: 14, weight: .medium))
                .padding(.horizontal, 14).padding(.vertical, 8)
                .background(isSelected ? Color.accentColor : Color.clear)
                .foregroundStyle(isSelected ? .white : Color.primary)
                .overlay(RoundedRectangle(cornerRadius: 20)
                    .stroke(isSelected ? Color.accentColor : Color.secondary.opacity(0.4), lineWidth: 1.5))
                .clipShape(RoundedRectangle(cornerRadius: 20))
        }
        .accessibilityLabel("\(name), \(isSelected ? "selected" : "not selected")")
    }
}

struct NotificationBenefit: View {
    let icon: String
    let text: String
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).font(.system(size: 18)).foregroundStyle(Color.accentColor).frame(width: 28)
            Text(text).font(.system(size: 15)).foregroundStyle(.primary)
        }
    }
}

struct FlowLayout: Layout {
    var spacing: CGFloat = 8
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? 0
        var x: CGFloat = 0; var y: CGFloat = 0; var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > width { x = 0; y += rowHeight + spacing; rowHeight = 0 }
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: width, height: y + rowHeight)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var x = bounds.minX; var y = bounds.minY; var rowHeight: CGFloat = 0
        for view in subviews {
            let size = view.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX { x = bounds.minX; y += rowHeight + spacing; rowHeight = 0 }
            view.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing; rowHeight = max(rowHeight, size.height)
        }
    }
}
