//
//  DensityDatabase.swift
//  SUPERWAAGE
//
//  Comprehensive kitchen material density database
//  Optimized for precision weighing of cooking ingredients
//

import Foundation

/// A kitchen material with name, density, and category
struct MaterialPreset: Identifiable, Hashable, Codable {
    var id = UUID()
    let name: String
    let density: Double // g/cm³
    let category: MaterialCategory
    let densityRange: ClosedRange<Double>? // Min-Max range for loose materials
    let packingFactor: Double? // For powders (loose vs packed)

    init(name: String, density: Double, category: MaterialCategory, densityRange: ClosedRange<Double>? = nil, packingFactor: Double? = nil) {
        self.name = name
        self.density = density
        self.category = category
        self.densityRange = densityRange
        self.packingFactor = packingFactor
    }
}

/// Material categories for kitchen use
enum MaterialCategory: String, CaseIterable, Codable {
    case flour = "Mehl & Mehle"
    case sugar = "Zucker & Süßstoffe"
    case salt = "Salz"
    case grains = "Getreide & Reis"
    case spices = "Gewürze & Kräuter"
    case powder = "Pulver & Backmittel"
    case dairy = "Butter & Fette"
    case nuts = "Nüsse & Samen"
    case liquids = "Flüssigkeiten"
    case custom = "Benutzerdefiniert"
}

/// Enhanced density database for kitchen materials
class DensityDatabase {

    // MARK: - Flour & Flour Types
    static let flourPresets: [MaterialPreset] = [
        MaterialPreset(name: "Weizenmehl Type 405", density: 0.60, category: .flour, densityRange: 0.55...0.65),
        MaterialPreset(name: "Weizenmehl Type 550", density: 0.62, category: .flour, densityRange: 0.58...0.66),
        MaterialPreset(name: "Weizenmehl Type 1050", density: 0.64, category: .flour, densityRange: 0.60...0.68),
        MaterialPreset(name: "Vollkornmehl", density: 0.66, category: .flour, densityRange: 0.62...0.70),
        MaterialPreset(name: "Dinkelmehl", density: 0.58, category: .flour, densityRange: 0.54...0.62),
        MaterialPreset(name: "Roggenmehl", density: 0.63, category: .flour, densityRange: 0.59...0.67),
        MaterialPreset(name: "Maismehl", density: 0.72, category: .flour, densityRange: 0.68...0.76),
        MaterialPreset(name: "Reismehl", density: 0.80, category: .flour, densityRange: 0.75...0.85),
        MaterialPreset(name: "Kartoffelstärke", density: 0.70, category: .flour, densityRange: 0.65...0.75),
        MaterialPreset(name: "Speisestärke", density: 0.68, category: .flour, densityRange: 0.64...0.72),
    ]

    // MARK: - Sugar Types
    static let sugarPresets: [MaterialPreset] = [
        MaterialPreset(name: "Kristallzucker (weiß)", density: 0.85, category: .sugar, densityRange: 0.80...0.90),
        MaterialPreset(name: "Puderzucker", density: 0.56, category: .sugar, densityRange: 0.50...0.62, packingFactor: 1.4),
        MaterialPreset(name: "Brauner Zucker", density: 0.72, category: .sugar, densityRange: 0.68...0.76),
        MaterialPreset(name: "Rohrzucker", density: 0.88, category: .sugar, densityRange: 0.84...0.92),
        MaterialPreset(name: "Hagelzucker", density: 0.90, category: .sugar, densityRange: 0.85...0.95),
        MaterialPreset(name: "Kandiszucker", density: 0.92, category: .sugar, densityRange: 0.88...0.96),
        MaterialPreset(name: "Honig", density: 1.42, category: .sugar, densityRange: 1.35...1.50),
        MaterialPreset(name: "Ahornsirup", density: 1.33, category: .sugar, densityRange: 1.30...1.37),
    ]

    // MARK: - Salt
    static let saltPresets: [MaterialPreset] = [
        MaterialPreset(name: "Tafelsalz (fein)", density: 1.20, category: .salt, densityRange: 1.15...1.25),
        MaterialPreset(name: "Meersalz (grob)", density: 0.95, category: .salt, densityRange: 0.90...1.00),
        MaterialPreset(name: "Meersalz (fein)", density: 1.18, category: .salt, densityRange: 1.12...1.24),
        MaterialPreset(name: "Himalayasalz", density: 1.03, category: .salt, densityRange: 0.98...1.08),
        MaterialPreset(name: "Fleur de Sel", density: 0.88, category: .salt, densityRange: 0.85...0.92),
    ]

    // MARK: - Grains & Rice
    static let grainsPresets: [MaterialPreset] = [
        MaterialPreset(name: "Reis (weiß, langkorn)", density: 0.91, category: .grains, densityRange: 0.88...0.94),
        MaterialPreset(name: "Reis (Basmati)", density: 0.87, category: .grains, densityRange: 0.84...0.90),
        MaterialPreset(name: "Reis (Vollkorn)", density: 0.85, category: .grains, densityRange: 0.82...0.88),
        MaterialPreset(name: "Haferflocken", density: 0.41, category: .grains, densityRange: 0.38...0.44),
        MaterialPreset(name: "Quinoa", density: 0.75, category: .grains, densityRange: 0.72...0.78),
        MaterialPreset(name: "Couscous", density: 0.68, category: .grains, densityRange: 0.64...0.72),
        MaterialPreset(name: "Bulgur", density: 0.72, category: .grains, densityRange: 0.68...0.76),
        MaterialPreset(name: "Linsen (rot)", density: 0.82, category: .grains, densityRange: 0.78...0.86),
        MaterialPreset(name: "Kichererbsen", density: 0.78, category: .grains, densityRange: 0.74...0.82),
    ]

    // MARK: - Spices & Herbs
    static let spicesPresets: [MaterialPreset] = [
        MaterialPreset(name: "Paprika (Pulver)", density: 0.45, category: .spices, densityRange: 0.40...0.50),
        MaterialPreset(name: "Pfeffer (gemahlen)", density: 0.52, category: .spices, densityRange: 0.48...0.56),
        MaterialPreset(name: "Zimt (gemahlen)", density: 0.56, category: .spices, densityRange: 0.52...0.60),
        MaterialPreset(name: "Kurkuma", density: 0.58, category: .spices, densityRange: 0.54...0.62),
        MaterialPreset(name: "Kreuzkümmel", density: 0.48, category: .spices, densityRange: 0.44...0.52),
        MaterialPreset(name: "Oregano (getrocknet)", density: 0.32, category: .spices, densityRange: 0.28...0.36),
        MaterialPreset(name: "Basilikum (getrocknet)", density: 0.28, category: .spices, densityRange: 0.24...0.32),
        MaterialPreset(name: "Petersilie (getrocknet)", density: 0.25, category: .spices, densityRange: 0.22...0.28),
        MaterialPreset(name: "Thymian (getrocknet)", density: 0.35, category: .spices, densityRange: 0.31...0.39),
    ]

    // MARK: - Powders & Baking Agents
    static let powderPresets: [MaterialPreset] = [
        MaterialPreset(name: "Backpulver", density: 0.88, category: .powder, densityRange: 0.84...0.92),
        MaterialPreset(name: "Natron", density: 0.94, category: .powder, densityRange: 0.90...0.98),
        MaterialPreset(name: "Kakaopulver", density: 0.65, category: .powder, densityRange: 0.60...0.70),
        MaterialPreset(name: "Instant-Kaffee", density: 0.38, category: .powder, densityRange: 0.34...0.42),
        MaterialPreset(name: "Milchpulver", density: 0.64, category: .powder, densityRange: 0.60...0.68),
        MaterialPreset(name: "Vanillepudding-Pulver", density: 0.72, category: .powder, densityRange: 0.68...0.76),
        MaterialPreset(name: "Gelatine-Pulver", density: 0.70, category: .powder, densityRange: 0.66...0.74),
    ]

    // MARK: - Dairy & Fats
    static let dairyPresets: [MaterialPreset] = [
        MaterialPreset(name: "Butter", density: 0.91, category: .dairy, densityRange: 0.88...0.94),
        MaterialPreset(name: "Margarine", density: 0.93, category: .dairy, densityRange: 0.90...0.96),
        MaterialPreset(name: "Schmalz", density: 0.90, category: .dairy, densityRange: 0.87...0.93),
        MaterialPreset(name: "Kokosfett", density: 0.92, category: .dairy, densityRange: 0.89...0.95),
        MaterialPreset(name: "Frischkäse", density: 1.01, category: .dairy, densityRange: 0.98...1.04),
    ]

    // MARK: - Nuts & Seeds
    static let nutsPresets: [MaterialPreset] = [
        MaterialPreset(name: "Mandeln (ganz)", density: 0.65, category: .nuts, densityRange: 0.62...0.68),
        MaterialPreset(name: "Mandeln (gemahlen)", density: 0.55, category: .nuts, densityRange: 0.52...0.58),
        MaterialPreset(name: "Walnüsse", density: 0.52, category: .nuts, densityRange: 0.48...0.56),
        MaterialPreset(name: "Haselnüsse", density: 0.68, category: .nuts, densityRange: 0.64...0.72),
        MaterialPreset(name: "Erdnüsse", density: 0.64, category: .nuts, densityRange: 0.60...0.68),
        MaterialPreset(name: "Cashews", density: 0.58, category: .nuts, densityRange: 0.54...0.62),
        MaterialPreset(name: "Pinienkerne", density: 0.62, category: .nuts, densityRange: 0.58...0.66),
        MaterialPreset(name: "Sonnenblumenkerne", density: 0.48, category: .nuts, densityRange: 0.44...0.52),
        MaterialPreset(name: "Kürbiskerne", density: 0.54, category: .nuts, densityRange: 0.50...0.58),
        MaterialPreset(name: "Sesam", density: 0.62, category: .nuts, densityRange: 0.58...0.66),
        MaterialPreset(name: "Leinsamen", density: 0.70, category: .nuts, densityRange: 0.66...0.74),
        MaterialPreset(name: "Chiasamen", density: 0.68, category: .nuts, densityRange: 0.64...0.72),
    ]

    // MARK: - Liquids
    static let liquidsPresets: [MaterialPreset] = [
        MaterialPreset(name: "Wasser", density: 1.00, category: .liquids),
        MaterialPreset(name: "Milch (Vollmilch)", density: 1.03, category: .liquids, densityRange: 1.02...1.04),
        MaterialPreset(name: "Sahne (30%)", density: 1.01, category: .liquids, densityRange: 1.00...1.02),
        MaterialPreset(name: "Olivenöl", density: 0.92, category: .liquids, densityRange: 0.90...0.94),
        MaterialPreset(name: "Sonnenblumenöl", density: 0.92, category: .liquids, densityRange: 0.91...0.93),
        MaterialPreset(name: "Rapsöl", density: 0.91, category: .liquids, densityRange: 0.90...0.92),
        MaterialPreset(name: "Essig", density: 1.01, category: .liquids, densityRange: 1.00...1.02),
        MaterialPreset(name: "Sojasauce", density: 1.12, category: .liquids, densityRange: 1.10...1.14),
    ]

    // MARK: - All Presets
    static var allPresets: [MaterialPreset] {
        return flourPresets + sugarPresets + saltPresets + grainsPresets +
               spicesPresets + powderPresets + dairyPresets + nutsPresets + liquidsPresets
    }

    // MARK: - Search
    /// Search for materials matching the query
    static func search(_ query: String) -> [MaterialPreset] {
        guard !query.isEmpty else { return allPresets }

        let lowercaseQuery = query.lowercased()
        return allPresets.filter { preset in
            preset.name.lowercased().contains(lowercaseQuery) ||
            preset.category.rawValue.lowercased().contains(lowercaseQuery)
        }
    }

    /// Get presets by category
    static func presets(for category: MaterialCategory) -> [MaterialPreset] {
        switch category {
        case .flour: return flourPresets
        case .sugar: return sugarPresets
        case .salt: return saltPresets
        case .grains: return grainsPresets
        case .spices: return spicesPresets
        case .powder: return powderPresets
        case .dairy: return dairyPresets
        case .nuts: return nutsPresets
        case .liquids: return liquidsPresets
        case .custom: return []
        }
    }

    /// Get density for material name (with fuzzy matching)
    static func density(for materialName: String) -> Double? {
        // Exact match first
        if let preset = allPresets.first(where: { $0.name.lowercased() == materialName.lowercased() }) {
            return preset.density
        }

        // Fuzzy match
        if let preset = allPresets.first(where: { $0.name.lowercased().contains(materialName.lowercased()) }) {
            return preset.density
        }

        return nil
    }

    // MARK: - Default Preset
    /// Default material (white flour)
    static var defaultPreset: MaterialPreset {
        return flourPresets.first(where: { $0.name.contains("405") }) ?? flourPresets[0]
    }

    // MARK: - Statistics
    static var totalMaterialCount: Int {
        return allPresets.count
    }

    static var categoryCount: Int {
        return MaterialCategory.allCases.count - 1 // Exclude custom
    }
}

// MARK: - Helper Extensions
extension MaterialPreset {
    /// Get estimated error based on density range
    var estimatedError: Double? {
        guard let range = densityRange else { return nil }
        let spread = range.upperBound - range.lowerBound
        return spread / density // Relative error
    }

    /// Get adjusted density for packing (loose vs packed)
    func adjustedDensity(packed: Bool) -> Double {
        guard let factor = packingFactor else { return density }
        return packed ? density * factor : density
    }
}
