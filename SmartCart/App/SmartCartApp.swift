// SmartCartApp.swift
// SmartCart — App/SmartCartApp.swift
//
// P1-6: AppDelegate implements UNUserNotificationCenterDelegate.
// Notification taps extract itemID from the identifier ("alert-{type}-{itemID}")
// and publish via NotificationRouter so HomeView can deep-link to ItemDetailView.

import SwiftUI
import UserNotifications

// Single-source-of-truth for notification-triggered navigation.
// Published on the main thread so SwiftUI views react immediately.
final class NotificationRouter: ObservableObject {
    static let shared = NotificationRouter()
    @Published var itemIDToOpen: Int64? = nil
}

class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {

    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    // Called when the user taps a notification — even when the app is in the foreground.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 didReceive response: UNNotificationResponse,
                                 withCompletionHandler completionHandler: @escaping () -> Void) {
        let id = response.notification.request.identifier
        // Identifier format: "alert-{type}-{itemID}" e.g. "alert-historical_low-42"
        if id.hasPrefix("alert-"),
           let idStr = id.split(separator: "-").last,
           let itemID = Int64(idStr) {
            DispatchQueue.main.async { NotificationRouter.shared.itemIDToOpen = itemID }
        }
        completionHandler()
    }

    // Show banner + sound even when the app is already open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                 willPresent notification: UNNotification,
                                 withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void) {
        completionHandler([.banner, .sound, .badge])
    }
}

@main
struct SmartCartApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var notificationRouter = NotificationRouter.shared

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(notificationRouter)
        }
    }
}
