// NotificationRouter.swift — SmartCart/App/NotificationRouter.swift
// Shared object that carries a notification tap's itemID from
// SmartCartApp (the UNUserNotificationCenterDelegate) to HomeView.
// Injected as an @EnvironmentObject so HomeView can react to it.

import Foundation
import Combine

final class NotificationRouter: ObservableObject {
    @Published var itemIDToOpen: Int64? = nil
}
