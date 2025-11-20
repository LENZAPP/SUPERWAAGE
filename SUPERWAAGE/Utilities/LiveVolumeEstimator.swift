//
//  LiveVolumeEstimator.swift
//  SUPERWAAGE
//
//  Real-time volume estimation during scanning
//  Provides instant feedback without full mesh processing
//

import Foundation
import simd

/// Real-time volume estimator for live scan feedback
/// Uses fast bounding box approximation with stability tracking
@MainActor
class LiveVolumeEstimator {

    // MARK: - Properties

    /// History of volume estimates for stability calculation
    private var estimateHistory: [Double] = []

    /// Maximum history size for variance calculation
    private let maxHistorySize = 15

    /// Last computed estimate
    private(set) var lastEstimate: Double = 0.0

    /// Last stability score (0.0 to 1.0)
    private(set) var lastStability: Double = 0.0

    /// Minimum points required for estimation
    private let minPointsRequired = 100

    /// Sample rate (process 1 in N points for speed)
    private let sampleRate = 10

    /// Typical fill factor for bounding box to actual volume
    /// Most objects are 60-75% of their bounding box volume
    private let fillFactor: Double = 0.65

    // MARK: - Public Methods

    /// Estimate volume from point cloud in real-time
    /// - Parameters:
    ///   - points: Array of 3D points
    ///   - confidence: Optional confidence values for each point
    /// - Returns: Tuple of (estimated volume in cm³, stability 0-1)
    func estimateVolumeLive(
        from points: [SIMD3<Float>],
        confidence: [Float]? = nil
    ) -> (volume: Double, stability: Double) {
        // Early exit if insufficient data
        guard points.count >= minPointsRequired else {
            return (0.0, 0.0)
        }

        // Filter by confidence if available
        let filteredPoints: [SIMD3<Float>]
        if let conf = confidence, conf.count == points.count {
            filteredPoints = zip(points, conf)
                .filter { $0.1 >= 0.5 }  // Medium confidence or higher
                .map { $0.0 }
        } else {
            filteredPoints = points
        }

        guard filteredPoints.count >= minPointsRequired else {
            return (lastEstimate, lastStability)
        }

        // Sample points for performance (every Nth point)
        let sampledPoints = stride(from: 0, to: filteredPoints.count, by: sampleRate)
            .map { filteredPoints[$0] }

        // Calculate oriented bounding box for better fit
        let volume = calculateOrientedBoundingBoxVolume(from: sampledPoints)

        // Update history
        estimateHistory.append(volume)
        if estimateHistory.count > maxHistorySize {
            estimateHistory.removeFirst()
        }

        // Calculate stability
        let stability = calculateStability()

        // Store for next iteration
        lastEstimate = volume
        lastStability = stability

        return (volume, stability)
    }

    /// Reset estimator state
    func reset() {
        estimateHistory.removeAll()
        lastEstimate = 0.0
        lastStability = 0.0
    }

    /// Get recommendation text based on stability
    func getRecommendation(stability: Double, pointCount: Int) -> String {
        switch (stability, pointCount) {
        case (0.9..., 500...):
            return "✅ Scan abgeschlossen - sehr stabil!"
        case (0.8..<0.9, 500...):
            return "🎯 Fast fertig - noch etwas bewegen"
        case (0.7..<0.8, 300...):
            return "📍 Gute Abdeckung - weiter scannen"
        case (_, 0..<300):
            return "🔄 Mehr Daten benötigt - Objekt umkreisen"
        case (0.5..<0.7, _):
            return "⚡ Langsamer bewegen für Stabilität"
        default:
            return "📊 Scanning läuft..."
        }
    }

    // MARK: - Private Methods

    /// Calculate oriented bounding box volume for better fit than axis-aligned
    private func calculateOrientedBoundingBoxVolume(from points: [SIMD3<Float>]) -> Double {
        guard points.count >= 3 else { return 0.0 }

        // Calculate centroid
        let centroid = points.reduce(SIMD3<Float>.zero) { $0 + $1 } / Float(points.count)

        // Center points around origin
        let centeredPoints = points.map { $0 - centroid }

        // Calculate covariance matrix for PCA (Principal Component Analysis)
        // Note: We calculate this for future eigenvector analysis, but currently use simplified AABB
        var covariance = simd_float3x3(0)
        for point in centeredPoints {
            let outer = simd_float3x3(
                SIMD3<Float>(point.x * point.x, point.x * point.y, point.x * point.z),
                SIMD3<Float>(point.y * point.x, point.y * point.y, point.y * point.z),
                SIMD3<Float>(point.z * point.x, point.z * point.y, point.z * point.z)
            )
            covariance += outer
        }
        // Normalize covariance matrix (element-wise division)
        let scale = Float(centeredPoints.count)
        covariance = simd_float3x3(
            covariance.columns.0 / scale,
            covariance.columns.1 / scale,
            covariance.columns.2 / scale
        )

        // Simplified: Use axis-aligned bounding box on centered points
        // (Full PCA eigenvector calculation would be more accurate but slower)
        var minPoint = centeredPoints[0]
        var maxPoint = centeredPoints[0]

        for point in centeredPoints {
            minPoint = SIMD3<Float>(
                min(minPoint.x, point.x),
                min(minPoint.y, point.y),
                min(minPoint.z, point.z)
            )
            maxPoint = SIMD3<Float>(
                max(maxPoint.x, point.x),
                max(maxPoint.y, point.y),
                max(maxPoint.z, point.z)
            )
        }

        // Calculate volume
        let size = maxPoint - minPoint
        let volumeMeters = Double(size.x * size.y * size.z)
        let volumeCm3 = volumeMeters * 1_000_000.0

        // Apply fill factor (objects rarely fill entire bounding box)
        return volumeCm3 * fillFactor
    }

    /// Calculate stability based on recent estimate variance
    private func calculateStability() -> Double {
        guard estimateHistory.count >= 3 else {
            return 0.0  // Not enough data
        }

        // Calculate mean
        let mean = estimateHistory.reduce(0.0, +) / Double(estimateHistory.count)

        // Protect against division by zero
        guard mean > 1.0 else {
            return 0.0
        }

        // Calculate coefficient of variation (CV = std dev / mean)
        let squaredDiffs = estimateHistory.map { pow($0 - mean, 2) }
        let variance = squaredDiffs.reduce(0.0, +) / Double(estimateHistory.count)
        let stdDev = sqrt(variance)
        let coefficientOfVariation = stdDev / mean

        // Convert CV to stability score (0-1)
        // CV of 0.0 = perfect stability (1.0)
        // CV of 0.2 = 20% variation (0.0)
        let stability = max(0.0, min(1.0, 1.0 - (coefficientOfVariation / 0.2)))

        return stability
    }

    /// Calculate trend (is volume increasing, decreasing, or stable?)
    func getTrend() -> VolumeTrend {
        guard estimateHistory.count >= 5 else {
            return .unknown
        }

        // Compare recent vs earlier estimates
        let recent = Array(estimateHistory.suffix(3))
        let earlier = Array(estimateHistory.prefix(3))

        let recentAvg = recent.reduce(0.0, +) / Double(recent.count)
        let earlierAvg = earlier.reduce(0.0, +) / Double(earlier.count)

        let change = (recentAvg - earlierAvg) / earlierAvg

        if change > 0.05 {
            return .increasing
        } else if change < -0.05 {
            return .decreasing
        } else {
            return .stable
        }
    }
}

// MARK: - Supporting Types

enum VolumeTrend {
    case increasing
    case stable
    case decreasing
    case unknown

    var description: String {
        switch self {
        case .increasing: return "📈 Steigend"
        case .stable: return "📊 Stabil"
        case .decreasing: return "📉 Fallend"
        case .unknown: return "❓ Unbekannt"
        }
    }

    var emoji: String {
        switch self {
        case .increasing: return "📈"
        case .stable: return "✅"
        case .decreasing: return "⚠️"
        case .unknown: return "🔄"
        }
    }
}
