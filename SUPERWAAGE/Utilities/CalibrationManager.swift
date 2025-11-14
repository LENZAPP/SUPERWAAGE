//
//  CalibrationManager.swift
//  SUPERWAAGE
//
//  Enhanced calibration system for precise measurements
//  Adapted from Kuechenwaage project
//

import Foundation
import Combine
import simd

/// Result of a calibration attempt
struct CalibrationResult {
    let success: Bool
    let scaleFactor: Float?
    let accuracy: Float  // 0-100%
    let deviation: Float  // Percentage deviation
    let message: String
}

/// Manages device-specific calibration for accurate measurements
/// Enhanced with reference object support and accuracy tracking
class CalibrationManager: ObservableObject {
    // Singleton instance
    static let shared = CalibrationManager()

    @Published private(set) var calibrationFactor: Float? = nil
    @Published private(set) var isCalibrated: Bool = false
    @Published private(set) var lastCalibrationDate: Date?
    @Published private(set) var referenceObjectUsed: KnownObject?
    @Published private(set) var calibrationAccuracy: Float = 0.0  // 0-100%

    // ✨ NEW: Enhanced calibration with depth bias
    @Published private(set) var depthBiasCoefficients: [Double]? = nil
    @Published private(set) var enhancedCalibration: EnhancedCalibrationResult? = nil

    private let calibrationKey = "SUPERWAAGE_CalibrationFactor"
    private let isCalbratedKey = "SUPERWAAGE_IsCalibrated"
    private let calibrationDateKey = "SUPERWAAGE_CalibrationDate"
    private let referenceObjectKey = "SUPERWAAGE_ReferenceObject"
    private let accuracyKey = "SUPERWAAGE_CalibrationAccuracy"
    private let enhancedCalibrationKey = "SUPERWAAGE_EnhancedCalibration"

    // Maximum allowed deviation for calibration
    private let maxDeviationPercent: Float = 50.0

    private init() {
        loadCalibration()
    }

    /// Calibrate using a known object with accuracy validation
    /// - Parameters:
    ///   - knownObject: Reference object with known dimensions
    ///   - scannedPoints: Scanned point cloud
    /// - Returns: CalibrationResult with success status and accuracy
    func calibrate(with knownObject: KnownObject, scannedPoints: [simd_float3]) -> CalibrationResult {
        guard !scannedPoints.isEmpty else {
            return CalibrationResult(success: false, scaleFactor: nil, accuracy: 0, deviation: 0, message: "Keine Punkte gescannt")
        }

        // Calculate bounding box from scanned points
        let minX = scannedPoints.map { $0.x }.min() ?? 0
        let maxX = scannedPoints.map { $0.x }.max() ?? 0
        let measured_m = maxX - minX

        let measured_cm = measured_m * 100.0
        guard measured_cm > 0 else {
            return CalibrationResult(success: false, scaleFactor: nil, accuracy: 0, deviation: 0, message: "Ungültige Messung")
        }

        // Calculate scale factor
        let scaleFactor = knownObject.length_cm / measured_cm

        // Calculate deviation percentage
        let deviation = abs(scaleFactor - 1.0) * 100.0

        // Validate deviation
        guard deviation <= maxDeviationPercent else {
            return CalibrationResult(
                success: false,
                scaleFactor: nil,
                accuracy: 0,
                deviation: deviation,
                message: "Abweichung zu groß: \(String(format: "%.1f%%", deviation)). Bitte Referenzobjekt besser positionieren."
            )
        }

        // Calculate accuracy (inverse of deviation, capped at 100%)
        let accuracy = max(0, min(100, 100.0 - deviation))

        // Save calibration
        self.calibrationFactor = scaleFactor
        self.isCalibrated = true
        self.lastCalibrationDate = Date()
        self.referenceObjectUsed = knownObject
        self.calibrationAccuracy = accuracy
        saveCalibration()

        return CalibrationResult(
            success: true,
            scaleFactor: scaleFactor,
            accuracy: accuracy,
            deviation: deviation,
            message: "Kalibrierung erfolgreich mit \(knownObject.name)"
        )
    }

    /// Calibrate using known length
    /// - Parameters:
    ///   - knownLength_cm: Actual length in centimeters
    ///   - measured_m: Measured length in meters from AR
    func calibrate(knownLength_cm: Float, measured_m: Float) {
        let measured_cm = measured_m * 100.0
        guard measured_cm > 0 else { return }

        let scaleFactor = knownLength_cm / measured_cm
        self.calibrationFactor = scaleFactor
        self.isCalibrated = true
        saveCalibration()
    }

    /// ✅ NEW: Calibrate using 3D volume measurement (for Euro coin)
    /// - Parameters:
    ///   - knownObject: Reference object with known volume
    ///   - scannedVolume: Scanned volume in ml (cm³)
    ///   - scannedDimensions: Scanned dimensions in cm (x, y, z)
    /// - Returns: CalibrationResult with success status
    func calibrateWithVolume(
        with knownObject: KnownObject,
        scannedVolume: Float,
        scannedDimensions: SIMD3<Float>
    ) -> CalibrationResult {
        guard let expectedVolume = knownObject.volume_ml else {
            return CalibrationResult(
                success: false,
                scaleFactor: nil,
                accuracy: 0,
                deviation: 0,
                message: "Objekt unterstützt keine Volumenkalibrierung"
            )
        }

        guard scannedVolume > 0 else {
            return CalibrationResult(
                success: false,
                scaleFactor: nil,
                accuracy: 0,
                deviation: 0,
                message: "Ungültiges Scanvolumen"
            )
        }

        // Calculate volume-based scale factor
        // Volume scaling factor = ∛(expected/measured) for linear correction
        let volumeRatio = expectedVolume / scannedVolume

        // ✅ CRASH FIX: Validate volumeRatio before pow operation
        guard volumeRatio.isFinite && volumeRatio > 0 else {
            return CalibrationResult(
                success: false,
                scaleFactor: nil,
                accuracy: 0,
                deviation: 0,
                message: "Ungültiges Volumenverhältnis berechnet"
            )
        }

        let scaleFactor = pow(volumeRatio, 1.0/3.0)

        // ✅ CRASH FIX: Validate scaleFactor result
        guard scaleFactor.isFinite && scaleFactor > 0 else {
            return CalibrationResult(
                success: false,
                scaleFactor: nil,
                accuracy: 0,
                deviation: 0,
                message: "Ungültiger Skalierungsfaktor berechnet"
            )
        }

        // Calculate deviation
        let volumeDeviation = abs(volumeRatio - 1.0) * 100.0

        // Validate (allow up to 50% deviation for coin scans due to thickness challenges)
        guard volumeDeviation <= maxDeviationPercent else {
            return CalibrationResult(
                success: false,
                scaleFactor: nil,
                accuracy: 0,
                deviation: volumeDeviation,
                message: """
                Abweichung zu groß: \(String(format: "%.1f%%", volumeDeviation))
                Erwartet: \(String(format: "%.2f", expectedVolume)) ml
                Gemessen: \(String(format: "%.2f", scannedVolume)) ml
                """
            )
        }

        // Calculate accuracy
        let accuracy = max(0, min(100, 100.0 - volumeDeviation))

        // Save calibration
        self.calibrationFactor = scaleFactor
        self.isCalibrated = true
        self.lastCalibrationDate = Date()
        self.referenceObjectUsed = knownObject
        self.calibrationAccuracy = accuracy
        saveCalibration()

        return CalibrationResult(
            success: true,
            scaleFactor: scaleFactor,
            accuracy: accuracy,
            deviation: volumeDeviation,
            message: "Kalibrierung erfolgreich mit \(knownObject.name) • Genauigkeit: \(String(format: "%.1f%%", accuracy))"
        )
    }

    /// Apply calibration factor to a single measurement
    func applyCalibration(to measurement_m: Float) -> Float {
        guard let factor = calibrationFactor else { return measurement_m }
        return measurement_m * factor
    }

    /// Apply calibration to dimensions
    func calibrateDimensions(_ dimensions: SIMD3<Float>) -> SIMD3<Float> {
        guard let factor = calibrationFactor else { return dimensions }
        return dimensions * factor
    }

    /// Reset calibration to default
    func resetCalibration() {
        calibrationFactor = nil
        isCalibrated = false
        lastCalibrationDate = nil
        referenceObjectUsed = nil
        calibrationAccuracy = 0.0
        depthBiasCoefficients = nil
        enhancedCalibration = nil
        saveCalibration()
    }

    // MARK: - Enhanced Calibration (Quick Calibration)

    /// Save enhanced calibration result from Quick Calibration
    func saveEnhancedCalibration(_ result: EnhancedCalibrationResult) {
        self.enhancedCalibration = result
        self.calibrationFactor = Float(result.scaleFactor)
        self.isCalibrated = true
        self.lastCalibrationDate = result.timestamp
        self.calibrationAccuracy = Float(result.qualityScore)
        self.depthBiasCoefficients = result.depthBiasCoefficients

        saveCalibration()
    }

    /// Apply depth bias correction for a given distance
    func applyDepthBiasCorrection(distance: Float) -> Float {
        guard let coeffs = depthBiasCoefficients, !coeffs.isEmpty else {
            return distance
        }

        var correction: Double = 0.0
        for (i, coeff) in coeffs.enumerated() {
            correction += coeff * pow(Double(distance), Double(i))
        }

        return distance + Float(correction)
    }

    /// Check if calibration needs refresh (30 days)
    var needsRecalibration: Bool {
        guard let lastDate = lastCalibrationDate else { return true }
        let daysSinceCalibration = Calendar.current.dateComponents([.day], from: lastDate, to: Date()).day ?? 0
        return daysSinceCalibration > 30
    }

    /// Status description for UI display
    var statusDescription: String {
        guard isCalibrated else { return "Nicht kalibriert" }

        if needsRecalibration {
            return "Kalibrierung veraltet (>30 Tage)"
        }

        guard let accuracy = calibrationAccuracy as Float? else {
            return "Kalibriert"
        }

        switch accuracy {
        case 95...100:
            return "Exzellent kalibriert (\(String(format: "%.0f%%", accuracy)))"
        case 85..<95:
            return "Sehr gut kalibriert (\(String(format: "%.0f%%", accuracy)))"
        case 70..<85:
            return "Gut kalibriert (\(String(format: "%.0f%%", accuracy)))"
        case 50..<70:
            return "Befriedigend kalibriert (\(String(format: "%.0f%%", accuracy)))"
        default:
            return "Neu kalibrieren empfohlen (\(String(format: "%.0f%%", accuracy)))"
        }
    }

    /// Accuracy color indicator
    var accuracyColor: String {
        guard let accuracy = calibrationAccuracy as Float? else { return "gray" }

        switch accuracy {
        case 90...100: return "green"
        case 75..<90: return "yellow"
        case 50..<75: return "orange"
        default: return "red"
        }
    }

    // MARK: - Persistence

    private func saveCalibration() {
        if let factor = calibrationFactor {
            UserDefaults.standard.set(factor, forKey: calibrationKey)
        } else {
            UserDefaults.standard.removeObject(forKey: calibrationKey)
        }
        UserDefaults.standard.set(isCalibrated, forKey: isCalbratedKey)

        // Save calibration date
        if let date = lastCalibrationDate {
            UserDefaults.standard.set(date, forKey: calibrationDateKey)
        } else {
            UserDefaults.standard.removeObject(forKey: calibrationDateKey)
        }

        // Save reference object (as raw value)
        if let refObject = referenceObjectUsed {
            let objectName = refObject.name
            UserDefaults.standard.set(objectName, forKey: referenceObjectKey)
        } else {
            UserDefaults.standard.removeObject(forKey: referenceObjectKey)
        }

        // Save accuracy
        UserDefaults.standard.set(calibrationAccuracy, forKey: accuracyKey)

        // ✨ NEW: Save enhanced calibration
        if let enhanced = enhancedCalibration {
            if let encoded = try? JSONEncoder().encode(enhanced) {
                UserDefaults.standard.set(encoded, forKey: enhancedCalibrationKey)
            }
        } else {
            UserDefaults.standard.removeObject(forKey: enhancedCalibrationKey)
        }
    }

    private func loadCalibration() {
        if UserDefaults.standard.object(forKey: calibrationKey) != nil {
            calibrationFactor = UserDefaults.standard.float(forKey: calibrationKey)
            isCalibrated = UserDefaults.standard.bool(forKey: isCalbratedKey)

            // Load calibration date
            if let date = UserDefaults.standard.object(forKey: calibrationDateKey) as? Date {
                lastCalibrationDate = date
            }

            // Load reference object
            if let objectName = UserDefaults.standard.string(forKey: referenceObjectKey) {
                referenceObjectUsed = KnownObject.fromName(objectName)
            }

            // Load accuracy
            calibrationAccuracy = UserDefaults.standard.float(forKey: accuracyKey)

            // ✨ NEW: Load enhanced calibration
            if let data = UserDefaults.standard.data(forKey: enhancedCalibrationKey),
               let enhanced = try? JSONDecoder().decode(EnhancedCalibrationResult.self, from: data) {
                enhancedCalibration = enhanced
                depthBiasCoefficients = enhanced.depthBiasCoefficients
            }
        }
    }

    // MARK: - Known Objects

    /// Standard reference objects for calibration
    enum KnownObject {
        case creditCard      // 85.6mm x 53.98mm
        case euroCard        // 85.0mm x 54.0mm
        case euroCoin1       // 23.25mm diameter
        case a4PaperWidth    // 210mm
        case iPhone14Pro     // 71.5mm width
        case custom(Float)

        var length_cm: Float {
            switch self {
            case .creditCard:
                return 8.56
            case .euroCard:
                return 8.50
            case .euroCoin1:
                return 2.325  // Diameter
            case .a4PaperWidth:
                return 21.0
            case .iPhone14Pro:
                return 7.15
            case .custom(let length):
                return length
            }
        }

        /// ✅ NEW: Thickness for 3D objects (cm)
        var thickness_cm: Float? {
            switch self {
            case .euroCoin1:
                return 0.22  // 2.20 mm = 0.22 cm
            default:
                return nil  // Not applicable for flat objects
            }
        }

        /// ✅ NEW: Volume for 3D objects (cm³ / ml)
        var volume_ml: Float? {
            switch self {
            case .euroCoin1:
                // Cylinder: V = π × r² × h
                let radius: Float = 2.325 / 2.0  // cm
                let height: Float = 0.22          // cm
                return Float.pi * radius * radius * height  // ≈ 0.935 ml
            default:
                return nil  // Not applicable
            }
        }

        var name: String {
            switch self {
            case .creditCard:
                return "Kreditkarte"
            case .euroCard:
                return "EC-Karte"
            case .euroCoin1:
                return "1 Euro Münze"
            case .a4PaperWidth:
                return "A4 Papier (Breite)"
            case .iPhone14Pro:
                return "iPhone 14 Pro"
            case .custom:
                return "Eigenes Objekt"
            }
        }

        /// Create KnownObject from name (for deserialization)
        static func fromName(_ name: String) -> KnownObject? {
            switch name {
            case "Kreditkarte":
                return .creditCard
            case "EC-Karte":
                return .euroCard
            case "1 Euro Münze":
                return .euroCoin1
            case "A4 Papier (Breite)":
                return .a4PaperWidth
            case "iPhone 14 Pro":
                return .iPhone14Pro
            default:
                return nil  // Custom objects not persisted
            }
        }

        /// All available reference objects for picker UI
        static var allCases: [KnownObject] {
            return [
                .euroCoin1,
                .euroCard,
                .creditCard,
                .a4PaperWidth,
                .iPhone14Pro
            ]
        }
    }
}
