// AlertCandidate.swift — SmartCart/Models/AlertCandidate.swift
//
// Intermediate value type used by AlertEngine before writing to alert_log.
// Not persisted — discarded after each daily evaluation pass.

import Foundation

enum AlertType: String {
    case historicalLow  = "historical_low"
    case sale           = "sale"
    case expiry         = "expiry"
    case combined       = "combined"   // A + B merged
}

struct AlertCandidate {
    let itemID: Int64
    let storeID: Int64
    let type: AlertType
    let price: Double
    let regularPrice: Double?
    let saleEventID: Int64?     // nil for historical_low type
    let saleEndDate: Date?
    let itemName: String
    let storeName: String
    let monthsLow: Int?         // for historical_low / combined copy

    // Priority for sort: lower number fires first.
    var priority: Int {
        switch type {
        case .combined:      return 1
        case .historicalLow: return 2
        case .sale:          return 3
        case .expiry:        return 4
        }
    }
}
