// SettingsView.swift
// SmartCart — Views/SettingsView.swift
//
// App settings screen. Sections:
//   1. Stores       — add/remove tracked grocery chains
//   2. Location     — postal code with Canadian format validation (P1-9)
//   3. Notifications — toggle with iOS Settings deep-link if permission denied
//   4. Alert preferences — daily cap display, sale alerts, expiry reminders
//   5. About        — app version + build number

import SwiftUI
import Combine
import UserNotifications

// MARK: - SettingsViewModel

@MainActor
final class SettingsViewModel: ObservableObject {

    // Notifications
    @Published var notificationsEnabled = false
    @Published var notificationsDeniedByOS = false  // true = iOS permission denied
    @Published var dailyAlertCap: Int = 3
    @Published var saleAlertsEnabled = true
    @Published var expiryReminderEnabled = true
    @Published var expiryReminderDays: Int = 1

    // Location
    @Published var postalCode = ""
    @Published var postalCodeError: String? = nil   // P1-9: validation error

    // Stores
    @Published var allStores: [Store] = []
    @Published var selectedStoreIDs: Set<Int64> = []

    // All available chains (used for Add Store flow)
    let availableStoreNames = [
        "No Frills", "Loblaws", "Metro", "Food Basics",
        "Sobeys", "FreshCo", "Giant Tiger", "Walmart", "Costco", "T&T"
    ]

    func load() {
        // Notification permission check
        UNUserNotificationCenter.current().getNotificationSettings { settings in
            DispatchQueue.main.async {
                self.notificationsDeniedByOS = settings.authorizationStatus == .denied
                self.notificationsEnabled    = settings.authorizationStatus == .authorized
            }
        }

        // User settings from SQLite
        notificationsEnabled    = DatabaseManager.shared.getSetting(key: "notification_enabled")      == "1"
        saleAlertsEnabled       = DatabaseManager.shared.getSetting(key: "sale_alerts_enabled")        == "1"
        expiryReminderEnabled   = DatabaseManager.shared.getSetting(key: "flyer_expiry_reminder")      == "1"
        expiryReminderDays      = Int(DatabaseManager.shared.getSetting(key: "expiry_reminder_days_before") ?? "1") ?? 1
        dailyAlertCap           = Int(DatabaseManager.shared.getSetting(key: "daily_alert_cap")         ?? "3") ?? 3
        postalCode              = DatabaseManager.shared.getSetting(key: "user_postal_code")            ?? ""

        // Stores
        allStores       = DatabaseManager.shared.fetchSelectedStores()
        selectedStoreIDs = Set(allStores.map { $0.id })
    }

    // MARK: Postal code (P1-9)
    // Canadian postal code format: A1A 1A1 or A1A1A1 (letter-digit-letter digit-letter-digit)
    // Accepts with or without the middle space.
    func savePostalCode() {
        let clean = postalCode.uppercased().replacingOccurrences(of: " ", with: "")
        let regex = #"^[A-Z]\d[A-Z]\d[A-Z]\d$"#
        guard clean.range(of: regex, options: .regularExpression) != nil else {
            postalCodeError = "Enter a valid Canadian postal code (e.g. K7L 3N6)"
            return
        }
        postalCodeError = nil
        DatabaseManager.shared.setSetting(key: "user_postal_code", value: clean)
    }

    // MARK: Store management
    func toggleStore(storeID: Int64, storeName: String) {
        if selectedStoreIDs.contains(storeID) {
            selectedStoreIDs.remove(storeID)
            DatabaseManager.shared.setSetting(key: "store_selected_\(storeID)", value: "0")
        } else {
            selectedStoreIDs.insert(storeID)
            DatabaseManager.shared.setSetting(key: "store_selected_\(storeID)", value: "1")
        }
    }

    func addStore(name: String) {
        let storeID = DatabaseManager.shared.upsertStore(name: name)
        selectedStoreIDs.insert(storeID)
        DatabaseManager.shared.setSetting(key: "store_selected_\(storeID)", value: "1")
        allStores = DatabaseManager.shared.fetchSelectedStores()
    }

    // MARK: Notification toggle
    // If the user enables from Settings and OS hasn't denied: request permission.
    // If OS has denied: open iOS Settings.
    func handleNotificationToggle(newValue: Bool) {
        if notificationsDeniedByOS {
            // Can't re-request after denial — send to iOS Settings
            guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
            UIApplication.shared.open(url)
            return
        }
        if newValue {
            UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
                DispatchQueue.main.async {
                    self.notificationsEnabled = granted
                    DatabaseManager.shared.setSetting(key: "notification_enabled", value: granted ? "1" : "0")
                }
            }
        } else {
            notificationsEnabled = false
            DatabaseManager.shared.setSetting(key: "notification_enabled", value: "0")
        }
    }
}

// MARK: - SettingsView

struct SettingsView: View {
    @StateObject private var vm = SettingsViewModel()
    @State private var showAddStore = false

    var body: some View {
        Form {
            storesSection
            locationSection
            notificationsSection
            alertPrefsSection
            aboutSection
        }
        .navigationTitle("Settings")
        .navigationBarTitleDisplayMode(.large)
        .onAppear { vm.load() }
        .sheet(isPresented: $showAddStore) {
            AddStoreSheet(availableNames: vm.availableStoreNames,
                          alreadyAdded: Set(vm.allStores.map { $0.name }),
                          onAdd: { vm.addStore(name: $0) })
        }
    }

    // MARK: Stores section
    private var storesSection: some View {
        Section(header: Text("Stores")) {
            if vm.allStores.isEmpty {
                Text("No stores added yet.")
                    .foregroundStyle(.secondary).font(.system(size: 15))
            } else {
                ForEach(vm.allStores, id: \.id) { store in
                    HStack {
                        Text(store.name).font(.system(size: 15))
                        Spacer()
                        if vm.selectedStoreIDs.contains(store.id) {
                            Image(systemName: "checkmark").foregroundStyle(Color.accentColor)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { vm.toggleStore(storeID: store.id, storeName: store.name) }
                }
            }
            Button(action: { showAddStore = true }) {
                Label("Add a Store", systemImage: "plus.circle")
            }
        }
    }

    // MARK: Location section (P1-9)
    private var locationSection: some View {
        Section(header: Text("Location"),
                footer: vm.postalCodeError.map { Text($0).foregroundStyle(.red) } ?? Text("Used to find flyers near you. Never shared.")) {
            HStack {
                Text("Postal Code")
                Spacer()
                TextField("K7L 3N6", text: $vm.postalCode)
                    .textInputAutocapitalization(.characters)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 120)
                    .submitLabel(.done)
                    .onSubmit { vm.savePostalCode() }
            }
        }
    }

    // MARK: Notifications section
    private var notificationsSection: some View {
        Section(header: Text("Notifications"),
                footer: vm.notificationsDeniedByOS
                    ? Text("Notifications are blocked. Tap the toggle to open iOS Settings.")
                        .foregroundStyle(.orange)
                    : nil) {
            Toggle(isOn: Binding(
                get: { vm.notificationsEnabled },
                set: { vm.handleNotificationToggle(newValue: $0) }
            )) {
                Label("Price Alerts", systemImage: vm.notificationsDeniedByOS
                      ? "bell.slash" : "bell.badge")
            }
        }
    }

    // MARK: Alert preferences section
    private var alertPrefsSection: some View {
        Section(header: Text("Alert Preferences")) {
            Toggle("Sale alerts", isOn: Binding(
                get: { vm.saleAlertsEnabled },
                set: {
                    vm.saleAlertsEnabled = $0
                    DatabaseManager.shared.setSetting(key: "sale_alerts_enabled", value: $0 ? "1" : "0")
                }
            ))

            Toggle("Expiry reminders", isOn: Binding(
                get: { vm.expiryReminderEnabled },
                set: {
                    vm.expiryReminderEnabled = $0
                    DatabaseManager.shared.setSetting(key: "flyer_expiry_reminder", value: $0 ? "1" : "0")
                }
            ))

            Picker("Remind me", selection: Binding(
                get: { vm.expiryReminderDays },
                set: {
                    vm.expiryReminderDays = $0
                    DatabaseManager.shared.setSetting(key: "expiry_reminder_days_before", value: "\($0)")
                }
            )) {
                Text("1 day before").tag(1)
                Text("2 days before").tag(2)
                Text("3 days before").tag(3)
            }
            .disabled(!vm.expiryReminderEnabled)

            HStack {
                Text("Daily alert limit")
                Spacer()
                Text("\(vm.dailyAlertCap) per day")
                    .foregroundStyle(.secondary).font(.system(size: 15))
            }
        }
    }

    // MARK: About section
    private var aboutSection: some View {
        Section(header: Text("About")) {
            HStack {
                Text("Version")
                Spacer()
                Text(appVersion).foregroundStyle(.secondary)
            }
            HStack {
                Text("Build")
                Spacer()
                Text(buildNumber).foregroundStyle(.secondary)
            }
        }
    }

    // Reads version and build from the app bundle.
    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "-"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "-"
    }
}

// MARK: - AddStoreSheet
// Bottom sheet for selecting a store to add from the pre-defined list.
struct AddStoreSheet: View {
    let availableNames: [String]
    let alreadyAdded: Set<String>
    let onAdd: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                ForEach(availableNames, id: \.self) { name in
                    HStack {
                        Text(name)
                        Spacer()
                        if alreadyAdded.contains(name) {
                            Text("Added").font(.system(size: 13)).foregroundStyle(.secondary)
                        }
                    }
                    .contentShape(Rectangle())
                    .onTapGesture {
                        guard !alreadyAdded.contains(name) else { return }
                        onAdd(name)
                        dismiss()
                    }
                    .foregroundStyle(alreadyAdded.contains(name) ? .secondary : .primary)
                }
            }
            .navigationTitle("Add a Store")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Cancel") { dismiss() } }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Preview
#Preview {
    NavigationStack {
        SettingsView()
    }
}
