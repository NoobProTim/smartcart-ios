// SettingsView.swift — SmartCart/Views/SettingsView.swift
//
// App settings screen backed by SettingsViewModel.

import SwiftUI

struct SettingsView: View {

    @StateObject private var vm = SettingsViewModel()

    var body: some View {
        NavigationStack {
            Form {
                // Notifications
                Section("Notifications") {
                    Toggle("Enable Alerts", isOn: $vm.notificationsEnabled)
                    if vm.notificationsEnabled {
                        Picker("Sensitivity", selection: $vm.alertSensitivity) {
                            Text("Aggressive").tag("aggressive")
                            Text("Balanced").tag("balanced")
                            Text("Conservative").tag("conservative")
                        }
                        HStack {
                            Text("Quiet Hours")
                            Spacer()
                            Text("\(vm.quietHoursStart) – \(vm.quietHoursEnd)")
                                .foregroundStyle(.secondary)
                        }
                    }
                }

                // Sale alerts (CR-001)
                Section("Sale Alerts") {
                    Toggle("Sale Alerts", isOn: $vm.saleAlertsEnabled)
                    if vm.saleAlertsEnabled {
                        Toggle("Only When Restock Due", isOn: $vm.saleAlertRestockOnly)
                        Picker("Min. Discount", selection: $vm.minDiscountThreshold) {
                            Text("Any").tag(0)
                            Text("10%").tag(10)
                            Text("20%").tag(20)
                            Text("30%").tag(30)
                        }
                        Toggle("Expiry Reminder", isOn: $vm.flyerExpiryReminderEnabled)
                        if vm.flyerExpiryReminderEnabled {
                            Picker("Days Before", selection: $vm.expiryReminderDaysBefore) {
                                Text("1 day").tag(1)
                                Text("2 days").tag(2)
                                Text("3 days").tag(3)
                            }
                        }
                    }
                }

                // Location
                Section("Location") {
                    HStack {
                        Text("Postal Code")
                        Spacer()
                        TextField("K1A 0A6", text: $vm.postalCode)
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(.secondary)
                            .autocorrectionDisabled()
                            .textInputAutocapitalization(.characters)
                    }
                }

                // About
                Section("About") {
                    LabeledContent("Version", value: appVersion)
                    LabeledContent("Build", value: buildNumber)
                }
            }
            .navigationTitle("Settings")
        }
    }

    private var appVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "—"
    }
    private var buildNumber: String {
        Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "—"
    }
}
