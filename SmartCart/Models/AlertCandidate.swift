// AlertCandidate.swift — SmartCart/Models/AlertCandidate.swift
//
// AlertType enum shared across AlertEngine and DatabaseManager extensions.
// The AlertCandidate struct lives in AlertEngine.swift where it is used.

import Foundation

enum AlertType: String {
    case historicalLow  = "historical_low"
    case sale           = "sale"
    case expiry         = "expiry"
    case combined       = "combined"
}
