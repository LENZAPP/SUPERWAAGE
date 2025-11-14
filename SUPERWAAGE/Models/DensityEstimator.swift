//
// DensityEstimator.swift
// SUPERWAAGE
//
// Professional density calculation with uncertainty propagation
// Combines measured mass (from BLE scale) and computed mesh volume for accurate density estimation
//
// Physics: ρ = m / V (density = mass / volume)
// Uncertainty: σ_ρ = ρ * √((σ_m/m)² + (σ_V/V)²)
//
// Usage:
//   var estimator = DensityEstimator()
//   estimator.massKg = 0.150  // From BLE scale
//   estimator.meshVolumeM3 = 0.000120  // From MeshVolume
//   let density = estimator.densityKgPerM3()  // Calculate density
//   let uncertainty = estimator.densityUncertainty()  // Get uncertainty
//

import Foundation
import simd

/// Professional density estimator with uncertainty quantification
public struct DensityEstimator {

    // MARK: - Measured Values

    /// Measured mass in kilograms (from BLE scale)
    public var massKg: Double = 0.0

    /// Computed mesh volume in cubic meters (from MeshVolume)
    public var meshVolumeM3: Double = 0.0

    // MARK: - Uncertainties

    /// Mass measurement uncertainty in kilograms
    /// Default: 5g (typical kitchen scale precision)
    public var massUncertaintyKg: Double = 0.005

    /// Volume measurement uncertainty in cubic meters
    /// Default: 5mL (0.000005 m³) - typical LiDAR mesh accuracy
    public var volumeUncertaintyM3: Double = 0.000005

    // MARK: - Initialization

    public init() {}

    public init(massKg: Double, volumeM3: Double) {
        self.massKg = massKg
        self.meshVolumeM3 = volumeM3
    }

    // MARK: - Density Calculations

    /// Calculate density in kg/m³
    /// - Returns: Density or nil if volume is zero/invalid
    public func densityKgPerM3() -> Double? {
        guard meshVolumeM3 > 0, massKg > 0 else { return nil }
        return massKg / meshVolumeM3
    }

    /// Calculate density in g/mL (more intuitive for food)
    /// - Returns: Density or nil if volume is zero/invalid
    /// - Note: 1 kg/m³ = 0.001 g/mL
    public func densityGPerMl() -> Double? {
        guard let densityKgM3 = densityKgPerM3() else { return nil }
        return densityKgM3 / 1000.0
    }

    /// Calculate density in g/cm³ (standard SI derived unit)
    /// - Returns: Density or nil if volume is zero/invalid
    /// - Note: 1 kg/m³ = 0.001 g/cm³
    public func densityGPerCm3() -> Double? {
        return densityGPerMl() // g/mL = g/cm³
    }

    // MARK: - Uncertainty Propagation

    /// Calculate density uncertainty using error propagation
    ///
    /// For ρ = m / V:
    /// σ_ρ = ρ * √((σ_m/m)² + (σ_V/V)²)
    ///
    /// - Returns: Absolute uncertainty in kg/m³, or nil if calculation impossible
    public func densityUncertainty() -> Double? {
        guard meshVolumeM3 > 0, massKg > 0 else { return nil }
        guard let density = densityKgPerM3() else { return nil }

        // Relative uncertainties squared
        let relativeMassUncertainty = massUncertaintyKg / massKg
        let relativeVolumeUncertainty = volumeUncertaintyM3 / meshVolumeM3

        // Combined relative uncertainty
        let combinedRelativeUncertainty = sqrt(
            pow(relativeMassUncertainty, 2) +
            pow(relativeVolumeUncertainty, 2)
        )

        // Absolute uncertainty
        return density * combinedRelativeUncertainty
    }

    /// Calculate relative uncertainty as percentage
    /// - Returns: Uncertainty as percentage (0-100), or nil if calculation impossible
    public func relativeUncertaintyPercent() -> Double? {
        guard let density = densityKgPerM3(),
              let uncertainty = densityUncertainty(),
              density > 0 else { return nil }

        return (uncertainty / density) * 100.0
    }

    // MARK: - Quality Metrics

    /// Determine measurement quality based on relative uncertainty
    /// - Returns: Quality rating: Excellent, Good, Fair, or Poor
    public func measurementQuality() -> MeasurementQuality {
        guard let relativeUncertainty = relativeUncertaintyPercent() else {
            return .invalid
        }

        if relativeUncertainty < 2.0 {
            return .excellent  // <2% uncertainty
        } else if relativeUncertainty < 5.0 {
            return .good       // 2-5% uncertainty
        } else if relativeUncertainty < 10.0 {
            return .fair       // 5-10% uncertainty
        } else {
            return .poor       // >10% uncertainty
        }
    }

    /// Check if result is within typical food density range
    /// - Returns: true if density is plausible for food items
    public func isPlausibleFoodDensity() -> Bool {
        guard let density = densityGPerMl() else { return false }

        // Typical food densities: 0.1 g/mL (light flour) to 2.0 g/mL (honey, syrup)
        // Water = 1.0 g/mL as reference
        return density >= 0.05 && density <= 3.0
    }

    // MARK: - Formatted Outputs

    /// Get formatted density string with uncertainty
    /// - Returns: String like "1.25 ± 0.03 g/mL"
    public func formattedDensity() -> String? {
        guard let density = densityGPerMl(),
              let uncertainty = densityUncertainty() else {
            return nil
        }

        let uncertaintyGPerMl = uncertainty / 1000.0
        return String(format: "%.3f ± %.3f g/mL", density, uncertaintyGPerMl)
    }

    /// Get formatted density with quality indicator
    /// - Returns: String like "1.25 g/mL (Good ±3.2%)"
    public func formattedDensityWithQuality() -> String? {
        guard let density = densityGPerMl(),
              let relativeUncertainty = relativeUncertaintyPercent() else {
            return nil
        }

        let quality = measurementQuality()
        return String(format: "%.3f g/mL (%@ ±%.1f%%)",
                     density,
                     quality.displayName,
                     relativeUncertainty)
    }

    // MARK: - Material Identification Support

    /// Compare with known material density
    /// - Parameters:
    ///   - referenceDensity: Known material density in g/mL
    ///   - tolerance: Acceptable difference (default 10%)
    /// - Returns: true if measured density matches reference within tolerance
    public func matches(referenceDensity: Double, tolerance: Double = 0.10) -> Bool {
        guard let measured = densityGPerMl() else { return false }

        let difference = abs(measured - referenceDensity)
        let allowedDifference = referenceDensity * tolerance

        return difference <= allowedDifference
    }

    /// Find closest material from database
    /// - Parameter materials: Array of (name, density in g/mL) tuples
    /// - Returns: Best matching material and difference
    public func closestMaterial(from materials: [(name: String, density: Double)]) -> (name: String, difference: Double)? {
        guard let measured = densityGPerMl() else { return nil }

        var closest: (name: String, difference: Double)?

        for material in materials {
            let difference = abs(measured - material.density)

            if closest == nil || difference < closest!.difference {
                closest = (material.name, difference)
            }
        }

        return closest
    }
}

// MARK: - Measurement Quality

public enum MeasurementQuality {
    case excellent  // <2% uncertainty
    case good       // 2-5% uncertainty
    case fair       // 5-10% uncertainty
    case poor       // >10% uncertainty
    case invalid    // Cannot calculate

    public var displayName: String {
        switch self {
        case .excellent: return "Excellent"
        case .good: return "Good"
        case .fair: return "Fair"
        case .poor: return "Poor"
        case .invalid: return "Invalid"
        }
    }

    public var emoji: String {
        switch self {
        case .excellent: return "🟢"
        case .good: return "🟡"
        case .fair: return "🟠"
        case .poor: return "🔴"
        case .invalid: return "⚫"
        }
    }

    public var description: String {
        switch self {
        case .excellent: return "Very accurate measurement"
        case .good: return "Good accuracy"
        case .fair: return "Acceptable accuracy"
        case .poor: return "Low accuracy - consider remeasuring"
        case .invalid: return "Invalid measurement"
        }
    }
}

// MARK: - Convenience Extensions

public extension DensityEstimator {

    /// Create from mesh volume calculation
    /// - Parameters:
    ///   - massKg: Measured mass in kg
    ///   - volumeM3: Mesh volume in m³
    ///   - massUncertainty: Mass uncertainty (default: 5g)
    ///   - volumeUncertainty: Volume uncertainty (default: 5mL)
    static func from(massKg: Double,
                    volumeM3: Double,
                    massUncertainty: Double = 0.005,
                    volumeUncertainty: Double = 0.000005) -> DensityEstimator {
        var estimator = DensityEstimator()
        estimator.massKg = massKg
        estimator.meshVolumeM3 = volumeM3
        estimator.massUncertaintyKg = massUncertainty
        estimator.volumeUncertaintyM3 = volumeUncertainty
        return estimator
    }

    /// Create from common units
    /// - Parameters:
    ///   - massGrams: Mass in grams
    ///   - volumeMilliliters: Volume in milliliters
    static func from(massGrams: Double, volumeMilliliters: Double) -> DensityEstimator {
        var estimator = DensityEstimator()
        estimator.massKg = massGrams / 1000.0
        estimator.meshVolumeM3 = volumeMilliliters / 1_000_000.0
        return estimator
    }
}
