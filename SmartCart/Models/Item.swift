// Item.swift — SmartCart/Models/Item.swift

import Foundation

struct Item: Identifiable, Equatable {
    let id: Int64
    let nameNormalised: String
    let nameDisplay: String
    let category: String?
    let unit: String?
    let createdAt: Date
}
