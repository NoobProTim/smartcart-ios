// FlyerDeal.swift — SmartCart/Models/FlyerDeal.swift

import Foundation

enum DealCategory: String, CaseIterable, Hashable {
    case all     = "All"
    case meat    = "Meat"
    case dairy   = "Dairy"
    case eggs    = "Eggs"
    case bakery  = "Bakery"
    case produce = "Produce"
    case baking  = "Baking"

    var emoji: String {
        switch self {
        case .all:     return "🛒"
        case .meat:    return "🥩"
        case .dairy:   return "🥛"
        case .eggs:    return "🥚"
        case .bakery:  return "🍞"
        case .produce: return "🥦"
        case .baking:  return "🧂"
        }
    }

    nonisolated static func classify(from name: String) -> DealCategory {
        let n = name.lowercased()
        let dairyWords   = ["milk","butter","cream","yogurt","cheese","sour cream","cottage","margarine"]
        let meatWords    = ["chicken","beef","pork","turkey","salmon","fish","lamb","sausage","bacon","ham","steak","ground"]
        let eggWords     = ["egg"]
        let bakeryWords  = ["bread","bagel","bun","muffin","loaf","croissant","tortilla","pita","wrap"]
        let produceWords = ["apple","banana","tomato","lettuce","carrot","pepper","onion","potato","orange","berry","grape","cucumber","spinach","broccoli","celery","lemon","lime","avocado"]
        let bakingWords  = ["flour","sugar","baking","rice","oil","vinegar","salt","spice","sauce","pasta","cereal","oat","syrup"]

        if dairyWords.contains(where: { n.contains($0) })   { return .dairy }
        if meatWords.contains(where: { n.contains($0) })    { return .meat }
        if eggWords.contains(where: { n.contains($0) })     { return .eggs }
        if bakeryWords.contains(where: { n.contains($0) })  { return .bakery }
        if produceWords.contains(where: { n.contains($0) }) { return .produce }
        if bakingWords.contains(where: { n.contains($0) })  { return .baking }
        return .all
    }
}

struct FlyerDeal: Identifiable, Hashable {
    let id:           UUID
    let name:         String
    let storeName:    String
    let salePrice:    Double
    let regularPrice: Double?
    let validTo:      Date?
    let category:     DealCategory

    var emoji: String { category.emoji }

    var savingsAmount: Double? {
        guard let reg = regularPrice, reg > salePrice else { return nil }
        return reg - salePrice
    }

    var discountPercent: Int? {
        guard let reg = regularPrice, reg > salePrice, reg > 0 else { return nil }
        return Int(((reg - salePrice) / reg) * 100)
    }

    var expiryLabel: String? {
        guard let end = validTo else { return nil }
        let days = Calendar.current.dateComponents(
            [.day],
            from: Calendar.current.startOfDay(for: Date()),
            to: Calendar.current.startOfDay(for: end)
        ).day ?? 0
        if days < 0  { return nil }
        if days == 0 { return "ends today" }
        let fmt = DateFormatter()
        fmt.dateFormat = "MMM d"
        return "ends \(fmt.string(from: end))"
    }
}
