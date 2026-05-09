// PricePoint.swift — SmartCart/Models/PricePoint.swift

import Foundation

enum PriceSource: String {
    case flipp
    case scraped
}

struct PricePoint: Identifiable {
    let id: Int64
    let itemID: Int64
    let storeID: Int64
    let price: Double
    let observedAt: Date
    let source: PriceSource
}
