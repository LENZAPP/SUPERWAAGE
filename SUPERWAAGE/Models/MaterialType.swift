//
//  MaterialType.swift
//  SUPERWAAGE
//
//  Material definitions with density and packing factors
//

import Foundation

struct MaterialType: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let density: Float  // g/cm³
    let packingFactor: Float  // Accounts for granularity and air gaps
    let category: MaterialCategory
    let icon: String

    // MARK: - Material Categories
    enum MaterialCategory: String, CaseIterable {
        case powder = "Pulver"
        case granular = "Körnig"
        case solid = "Fest"
        case liquid = "Flüssig"
    }

    // MARK: - Predefined Materials
    static let sugar = MaterialType(
        name: "Zucker (feinkörnig)",
        density: 0.85,
        packingFactor: 0.92,
        category: .granular,
        icon: "🍬"
    )

    static let flour = MaterialType(
        name: "Mehl (staubig)",
        density: 0.59,
        packingFactor: 0.65,
        category: .powder,
        icon: "🌾"
    )

    static let salt = MaterialType(
        name: "Salz (feinkörnig)",
        density: 2.16,
        packingFactor: 0.85,
        category: .granular,
        icon: "🧂"
    )

    static let rice = MaterialType(
        name: "Reis (Körner)",
        density: 0.75,
        packingFactor: 0.70,
        category: .granular,
        icon: "🍚"
    )

    static let water = MaterialType(
        name: "Wasser",
        density: 1.00,
        packingFactor: 1.00,
        category: .liquid,
        icon: "💧"
    )

    static let milk = MaterialType(
        name: "Milch",
        density: 1.03,
        packingFactor: 1.00,
        category: .liquid,
        icon: "🥛"
    )

    static let butter = MaterialType(
        name: "Butter (weich)",
        density: 0.91,
        packingFactor: 0.98,
        category: .solid,
        icon: "🧈"
    )

    static let honey = MaterialType(
        name: "Honig",
        density: 1.42,
        packingFactor: 1.00,
        category: .liquid,
        icon: "🍯"
    )

    static let cocoa = MaterialType(
        name: "Kakao (Pulver)",
        density: 0.52,
        packingFactor: 0.60,
        category: .powder,
        icon: "🍫"
    )

    static let bakingPowder = MaterialType(
        name: "Backpulver",
        density: 0.90,
        packingFactor: 0.75,
        category: .powder,
        icon: "🥐"
    )

    static let yeast = MaterialType(
        name: "Hefe (bröckelig)",
        density: 0.95,
        packingFactor: 0.70,
        category: .solid,
        icon: "🦠"
    )

    static let nuts = MaterialType(
        name: "Nüsse (gehackt)",
        density: 0.65,
        packingFactor: 0.60,
        category: .granular,
        icon: "🥜"
    )

    static let oats = MaterialType(
        name: "Haferflocken",
        density: 0.41,
        packingFactor: 0.55,
        category: .granular,
        icon: "🌾"
    )

    static let breadcrumbs = MaterialType(
        name: "Semmelbrösel",
        density: 0.35,
        packingFactor: 0.50,
        category: .powder,
        icon: "🍞"
    )

    static let chocolate = MaterialType(
        name: "Schokolade (Stücke)",
        density: 1.25,
        packingFactor: 0.75,
        category: .solid,
        icon: "🍫"
    )

    static let coffee = MaterialType(
        name: "Kaffee (gemahlen)",
        density: 0.40,
        packingFactor: 0.60,
        category: .powder,
        icon: "☕"
    )

    static let lentils = MaterialType(
        name: "Linsen",
        density: 0.80,
        packingFactor: 0.75,
        category: .granular,
        icon: "🫘"
    )

    static let pasta = MaterialType(
        name: "Nudeln",
        density: 0.70,
        packingFactor: 0.55,
        category: .solid,
        icon: "🍝"
    )

    // MARK: - Test & Calibration Materials

    static let softcoverBook = MaterialType(
        name: "Taschenbuch (Testmaterial)",
        density: 0.70,  // ~700 kg/m³ for paper book
        packingFactor: 1.00,  // Solid object, no air gaps
        category: .solid,
        icon: "📕"
    )

    static let euroCoin = MaterialType(
        name: "1 Euro Münze (Kalibration)",
        density: 7.50,  // 7.5g / 1cm³ volume
        packingFactor: 1.00,  // Solid metal, no air gaps
        category: .solid,
        icon: "💶"
    )

    // MARK: - All Materials Collection
    static let allMaterials: [MaterialType] = [
        .sugar, .flour, .salt, .rice,
        .water, .milk, .butter, .honey,
        .cocoa, .bakingPowder, .yeast, .nuts,
        .oats, .breadcrumbs, .chocolate, .coffee,
        .lentils, .pasta,
        .softcoverBook, .euroCoin
    ]

    static let materialsByCategory: [MaterialCategory: [MaterialType]] = {
        var dict: [MaterialCategory: [MaterialType]] = [:]
        for category in MaterialCategory.allCases {
            dict[category] = allMaterials.filter { $0.category == category }
        }
        return dict
    }()
}

// MARK: - Equatable & Hashable
extension MaterialType {
    static func == (lhs: MaterialType, rhs: MaterialType) -> Bool {
        lhs.name == rhs.name && lhs.density == rhs.density
    }

    func hash(into hasher: inout Hasher) {
        hasher.combine(name)
        hasher.combine(density)
    }
}
