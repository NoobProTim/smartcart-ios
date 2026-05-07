// UserStore.swift — SmartCart/Models/UserStore.swift
// Join table between user's tracked list and the stores table.
// Maps to `user_stores`.
//
// ⚠️ P2-3 NOTE: This table is currently NOT written during onboarding.
// Store selection is tracked via user_settings keys ("store_selected_{id}").
// Until that inconsistency is resolved, do not read from user_stores in production code.

import Foundation

struct UserStore: Identifiable {
    let id: Int64
    let storeID: Int64
    let addedAt: Date
}
