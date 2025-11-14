//
//  QuickCalibrationModels.swift
//  SUPERWAAGE
//
//  Data models for Quick Accuracy Calibration
//  Supports multi-angle calibration with depth bias regression
//

import Foundation
import ARKit
import Vision
import simd

// MARK: - Enhanced Calibration Result

/// Comprehensive calibration result with depth bias correction
struct EnhancedCalibrationResult: Codable, Equatable {
    /// Linear scale factor (meters per pixel or similar)
    let scaleFactor: Double

    /// Depth bias correction coefficients [a, b, c, ...] for polynomial regression
    /// depthBias = a + b*distance + c*distance²
    let depthBiasCoefficients: [Double]

    /// Quality score 0-100%
    let qualityScore: Double

    /// Reference object used for calibration
    let referenceObject: ReferenceObjectType

    /// Number of frames used
    let frameCount: Int

    /// Timestamp of calibration
    let timestamp: Date

    /// Mean squared error of the regression
    let mse: Double

    /// Expected accuracy range
    var expectedAccuracy: String {
        if qualityScore >= 90 {
            return "±1–2g (kleine Objekte), ±3–8g (größere Objekte)"
        } else if qualityScore >= 75 {
            return "±1–3g (kleine Objekte), ±5–12g (größere Objekte)"
        } else {
            return "±2–5g (kleine Objekte), ±8–20g (größere Objekte)"
        }
    }

    /// Apply depth bias correction for a given distance
    func applyDepthBiasCorrection(distance: Double) -> Double {
        var correction = 0.0
        for (i, coefficient) in depthBiasCoefficients.enumerated() {
            correction += coefficient * pow(distance, Double(i))
        }
        return correction
    }
}

// MARK: - Reference Object Types

/// Reference objects for calibration
enum ReferenceObjectType: String, Codable, CaseIterable, Identifiable {
    case euroCoin = "euro_coin"
    case bankCard = "bank_card"
    case cube5cm = "cube_5cm"

    var id: String { rawValue }

    /// Display name (German)
    var displayName: String {
        switch self {
        case .euroCoin: return "1-Euro-Münze"
        case .bankCard: return "Bankkarte"
        case .cube5cm: return "5-cm-Würfel"
        }
    }

    /// Real-world dimensions in meters
    var dimensions: ReferenceObjectDimensions {
        switch self {
        case .euroCoin:
            return ReferenceObjectDimensions(
                width: 0.02325,    // 23.25mm
                height: 0.0022,    // 2.20mm
                depth: 0.02325,    // circular
                shape: .circular
            )
        case .bankCard:
            return ReferenceObjectDimensions(
                width: 0.0856,     // 85.60mm
                height: 0.0539,    // 53.98mm
                depth: 0.00076,    // 0.76mm
                shape: .rectangular
            )
        case .cube5cm:
            return ReferenceObjectDimensions(
                width: 0.05,       // 50mm
                height: 0.05,      // 50mm
                depth: 0.05,       // 50mm
                shape: .rectangular
            )
        }
    }

    /// SF Symbol icon
    var icon: String {
        switch self {
        case .euroCoin: return "eurosign.circle.fill"
        case .bankCard: return "creditcard.fill"
        case .cube5cm: return "cube.fill"
        }
    }

    /// Description text
    var description: String {
        switch self {
        case .euroCoin:
            return "Durchmesser: 23.25 mm"
        case .bankCard:
            return "Breite: 85.60 mm"
        case .cube5cm:
            return "Kante: 50 mm"
        }
    }
}

/// Physical dimensions of reference object
struct ReferenceObjectDimensions {
    let width: Double      // meters
    let height: Double     // meters (thickness)
    let depth: Double      // meters
    let shape: ObjectShape

    enum ObjectShape {
        case circular
        case rectangular
    }
}

// MARK: - Calibration Frame

/// Single calibration frame with AR data and detection results
struct CalibrationFrame: Equatable {
    /// Unique identifier
    let id = UUID()

    static func == (lhs: CalibrationFrame, rhs: CalibrationFrame) -> Bool {
        return lhs.id == rhs.id
    }

    /// Timestamp
    let timestamp: Date

    /// Reference object type
    let referenceObject: ReferenceObjectType

    /// Camera angle description
    let angleDescription: CalibrationAngle

    /// ARFrame data
    let cameraTransform: simd_float4x4
    let cameraIntrinsics: simd_float3x3

    /// Detected contour in image space (normalized 0-1)
    let detectedContour: [CGPoint]

    /// Depth data (if available)
    let depthMap: CVPixelBuffer?
    let depthEstimate: Float?  // Average depth in meters

    /// Detected dimensions in pixels
    let pixelWidth: Float
    let pixelHeight: Float

    /// Image for debugging
    let capturedImage: CVPixelBuffer

    /// Computed scale factor for this frame
    var scaleFactorEstimate: Double {
        let realWidth = referenceObject.dimensions.width
        guard pixelWidth > 0 else {
            print("❌ WARNING: pixelWidth is zero or negative: \(pixelWidth)")
            return 0.001  // Return small value to avoid division by zero
        }
        return realWidth / Double(pixelWidth)
    }
}

/// Required camera angles for multi-view calibration
enum CalibrationAngle: String, CaseIterable {
    case frontal = "Frontal"
    case leftAngle = "Leicht links"
    case topAngle = "Leicht von oben"

    var icon: String {
        switch self {
        case .frontal: return "camera.fill"
        case .leftAngle: return "camera.rotate.fill"
        case .topAngle: return "arrow.down.to.line.circle.fill"
        }
    }

    var instruction: String {
        switch self {
        case .frontal:
            return "Halte das Objekt frontal vor die Kamera"
        case .leftAngle:
            return "Drehe das Objekt leicht nach links"
        case .topAngle:
            return "Schaue leicht von oben auf das Objekt"
        }
    }
}

// MARK: - Calibration State

/// State machine for calibration flow
enum QuickCalibrationState: Equatable {
    case notStarted
    case selectingObject
    case capturingFrame(angle: CalibrationAngle, progress: Int, total: Int)
    case processing
    case completed(EnhancedCalibrationResult)
    case failed(String)

    var isActive: Bool {
        switch self {
        case .notStarted, .completed, .failed:
            return false
        default:
            return true
        }
    }
}

// MARK: - Vision Detection Result

/// Result from Vision contour detection
struct ContourDetectionResult {
    let boundingBox: CGRect        // Normalized 0-1
    let confidence: Float          // 0-1
    let contourPoints: [CGPoint]   // Normalized 0-1
    let pixelWidth: Float          // in pixels
    let pixelHeight: Float         // in pixels
}
