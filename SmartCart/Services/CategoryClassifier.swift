// CategoryClassifier.swift
// SmartCart — Services/CategoryClassifier.swift
//
// HIGH-4 fix (Task #6):
//   Before this file existed, every new item imported from a receipt defaulted
//   to Constants.defaultReplenishmentDays (14 days) regardless of what it was.
//   That meant bread, milk, and laundry detergent all had the same 14-day cycle
//   on first import — detergent would alert weekly and bread would alert monthly.
//
// PURPOSE:
//   Maps a normalised item name to a GroceryCategory, then maps that category
//   to a sensible starting replenishment cycle in days.
//   This is a SEED value only — ReplenishmentEngine.inferCycleDays() will replace
//   it with a true inferred value once the user has >= 3 purchase records.
//
// DESIGN RULES:
//   1. classify() is purely functional — no stored state, no DB calls.
//   2. Keyword matching uses lowercase contains() — fast and locale-safe.
//   3. Categories and cycles are tuned for a Canadian household grocery basket.
//   4. Unknown items return nil (suggestedCycleDays = nil → engine default of 14 days).
//   5. All keyword arrays are sorted longest-match-first within each case to
//      avoid short substrings matching before more specific terms.
//      (e.g. "almond milk" must match before "milk")

import Foundation

// Broad grocery categories used only inside this classifier.
// Not persisted — category is not stored on UserItem or ParsedReceiptItem.
private enum GroceryCategory {
    case freshProduceFast    // Lettuce, berries, herbs  — spoil in ~5 days
    case freshProduceSlow    // Apples, potatoes, onions — last ~14 days
    case dairy               // Milk, yogurt, cheese     — ~7 days
    case bread               // Bread, buns, tortillas   — ~7 days
    case meat                // Chicken, beef, fish      — ~7 days
    case frozenOrCanned      // Frozen meals, canned goods — ~30 days
    case dryPantry           // Pasta, rice, flour        — ~45 days
    case beverages           // Juice, soda, water        — ~14 days
    case snacks              // Chips, crackers, granola  — ~14 days
    case condiments          // Ketchup, salsa, mustard   — ~60 days
    case cleaningHousehold   // Dish soap, laundry, paper towels — ~30 days
    case personalCare        // Shampoo, toothpaste, deodorant   — ~45 days
    case babyPet             // Baby formula, pet food           — ~21 days
}

// The cycle-days value for each category.
// These are calibrated starting points — ReplenishmentEngine replaces them
// with inferred values after enough purchase history accumulates.
private let categoryCycleDays: [GroceryCategory: Int] = [
    .freshProduceFast:  5,
    .freshProduceSlow:  14,
    .dairy:             7,
    .bread:             7,
    .meat:              7,
    .frozenOrCanned:    30,
    .dryPantry:         45,
    .beverages:         14,
    .snacks:            14,
    .condiments:        60,
    .cleaningHousehold: 30,
    .personalCare:      45,
    .babyPet:           21
]

enum CategoryClassifier {

    // MARK: - classify(normalisedName:)
    // Takes a normalised item name (lowercase, trimmed) and returns a suggested
    // replenishment cycle in days, or nil if no category match is found.
    // Nil means ReplenishmentEngine will use Constants.defaultReplenishmentDays.
    static func classify(normalisedName: String) -> Int? {
        let name = normalisedName.lowercased()
        guard let category = matchCategory(name) else { return nil }
        return categoryCycleDays[category]
    }

    // MARK: - matchCategory(_:)
    // Keyword → GroceryCategory mapping.
    // Evaluated in order — more specific terms are listed before generic ones
    // within each case to prevent short substrings stealing the match.
    // Returns nil when no keyword matches.
    private static func matchCategory(_ name: String) -> GroceryCategory? {

        // --- Fast-spoiling fresh produce ---
        let freshFastKeywords = [
            "lettuce", "spinach", "arugula", "kale", "mixed greens", "baby greens",
            "strawberr", "raspberry", "blueberr", "blackberr",
            "cilantro", "parsley", "basil", "dill", "mint",
            "mushroom", "bean sprout", "green onion", "scallion"
        ]
        if freshFastKeywords.contains(where: { name.contains($0) }) { return .freshProduceFast }

        // --- Slow-spoiling fresh produce ---
        let freshSlowKeywords = [
            "apple", "orange", "banana", "grape", "mango", "pineapple",
            "watermelon", "cantaloupe", "peach", "plum", "pear", "kiwi",
            "potato", "sweet potato", "yam", "carrot", "beet", "parsnip",
            "onion", "garlic", "ginger", "cabbage", "broccoli", "cauliflower",
            "celery", "cucumber", "pepper", "zucchini", "squash", "tomato",
            "avocado", "lemon", "lime", "grapefruit"
        ]
        if freshSlowKeywords.contains(where: { name.contains($0) }) { return .freshProduceSlow }

        // --- Dairy ---
        // "almond milk" / "oat milk" checked first so they don't fall into dairy.
        let nonDairyMilk = ["almond milk", "oat milk", "soy milk", "coconut milk", "rice milk"]
        if nonDairyMilk.contains(where: { name.contains($0) }) { return .beverages }
        let dairyKeywords = [
            "milk", "skim", "2%", "homo milk",
            "yogurt", "yoghurt", "kefir",
            "cheddar", "mozzarella", "parmesan", "brie", "feta", "gouda", "cheese",
            "butter", "cream", "sour cream", "cream cheese", "cottage cheese",
            "egg"
        ]
        if dairyKeywords.contains(where: { name.contains($0) }) { return .dairy }

        // --- Bread & bakery ---
        let breadKeywords = [
            "bread", "sourdough", "baguette", "ciabatta", "rye",
            "bun", "roll", "bagel", "english muffin", "croissant",
            "tortilla", "wrap", "pita", "naan", "flatbread"
        ]
        if breadKeywords.contains(where: { name.contains($0) }) { return .bread }

        // --- Meat, poultry, seafood ---
        let meatKeywords = [
            "chicken", "turkey", "beef", "pork", "lamb", "veal",
            "ground beef", "ground turkey", "ground pork",
            "steak", "roast", "chop", "rib",
            "salmon", "tilapia", "cod", "tuna", "shrimp", "fish",
            "bacon", "ham", "sausage", "hot dog", "deli"
        ]
        if meatKeywords.contains(where: { name.contains($0) }) { return .meat }

        // --- Frozen & canned ---
        let frozenCannedKeywords = [
            "frozen", "ice cream", "gelato", "sorbet",
            "canned", "can of", "tin of",
            "soup", "broth", "stock",
            "beans", "lentil", "chickpea", "black bean", "kidney bean"
        ]
        if frozenCannedKeywords.contains(where: { name.contains($0) }) { return .frozenOrCanned }

        // --- Dry pantry ---
        let dryPantryKeywords = [
            "pasta", "spaghetti", "penne", "fusilli", "linguine", "macaroni",
            "rice", "quinoa", "barley", "oat", "oatmeal", "granola",
            "flour", "sugar", "baking powder", "baking soda", "yeast",
            "cereal", "corn flakes", "cheerio",
            "cracker", "breadcrumb", "panko",
            "nut butter", "peanut butter", "almond butter",
            "jam", "jelly", "marmalade", "honey", "maple syrup"
        ]
        if dryPantryKeywords.contains(where: { name.contains($0) }) { return .dryPantry }

        // --- Beverages ---
        let beverageKeywords = [
            "juice", "orange juice", "apple juice",
            "soda", "pop", "cola", "sprite", "ginger ale", "sparkling water",
            "water", "mineral water",
            "coffee", "espresso", "tea", "herbal tea",
            "energy drink", "sports drink",
            "almond milk", "oat milk", "soy milk"  // re-listed as safety net
        ]
        if beverageKeywords.contains(where: { name.contains($0) }) { return .beverages }

        // --- Snacks ---
        let snackKeywords = [
            "chip", "crisp", "popcorn", "pretzel", "rice cake",
            "chocolate", "candy", "gummy", "licorice",
            "cookie", "biscuit", "wafer",
            "granola bar", "protein bar", "energy bar", "trail mix", "nut"
        ]
        if snackKeywords.contains(where: { name.contains($0) }) { return .snacks }

        // --- Condiments & sauces ---
        let condimentKeywords = [
            "ketchup", "mustard", "mayonnaise", "mayo", "relish",
            "salsa", "hot sauce", "sriracha", "tabasco",
            "soy sauce", "oyster sauce", "fish sauce", "worcestershire",
            "vinegar", "olive oil", "vegetable oil", "canola oil",
            "salad dressing", "ranch", "caesar dressing",
            "pasta sauce", "marinara", "tomato sauce", "pesto",
            "bbq sauce", "teriyaki"
        ]
        if condimentKeywords.contains(where: { name.contains($0) }) { return .condiments }

        // --- Cleaning & household ---
        let cleaningKeywords = [
            "dish soap", "dishwasher", "laundry", "detergent", "fabric softener",
            "bleach", "all-purpose cleaner", "bathroom cleaner", "toilet cleaner",
            "paper towel", "toilet paper", "tissue", "garbage bag", "trash bag",
            "sponge", "scrub", "mop", "broom",
            "zip loc", "plastic wrap", "aluminum foil", "parchment"
        ]
        if cleaningKeywords.contains(where: { name.contains($0) }) { return .cleaningHousehold }

        // --- Personal care ---
        let personalCareKeywords = [
            "shampoo", "conditioner", "body wash", "shower gel",
            "toothpaste", "toothbrush", "mouthwash", "floss",
            "deodorant", "antiperspirant",
            "razor", "shaving cream", "shaving gel",
            "moisturizer", "lotion", "sunscreen",
            "tampon", "pad", "liner",
            "vitamin", "supplement", "probiotic"
        ]
        if personalCareKeywords.contains(where: { name.contains($0) }) { return .personalCare }

        // --- Baby & pet ---
        let babyPetKeywords = [
            "baby formula", "infant formula", "baby food", "baby wipe",
            "diaper", "nappy",
            "pet food", "cat food", "dog food", "cat litter", "dog treat",
            "kibble"
        ]
        if babyPetKeywords.contains(where: { name.contains($0) }) { return .babyPet }

        // No category match — caller stores nil and engine uses the 14-day default.
        return nil
    }
}
