//
//  AccuracyEvaluator.swift
//  SUPERWAAGE
//
//  Advanced accuracy evaluation system with material-specific error estimation
//  Apple Senior Developer level implementation
//

import Foundation
import simd
import ARKit

// MARK: - Accuracy Result
struct AccuracyResult {
    let volumeM3: Float
    let weightG: Float
    let estimatedErrorPercent: Float
    let confidenceLevel: Float  // 0.0 to 1.0
    let qualityScore: Float     // 0.0 to 1.0
    let recommendations: [String]
    let errorBreakdown: ErrorBreakdown

    struct ErrorBreakdown {
        let pointCountError: Float
        let distanceError: Float
        let confidenceError: Float
        let materialError: Float
        let calibrationError: Float
        let meshQualityError: Float
    }
}

// MARK: - Scan Quality Metrics
struct ScanQualityMetrics {
    let pointCount: Int
    let averageConfidence: Float
    let distance_m: Float
    let meshDensity: Float  // Points per m²
    let coverageScore: Float  // 0.0 to 1.0
    let isCalibrated: Bool
}

// MARK: - Accuracy Evaluator
class AccuracyEvaluator {

    // MARK: - Constants
    private let optimalPointCount: Int = 5000
    private let minPointCount: Int = 100
    private let optimalDistance_m: Float = 0.3 // 30cm
    private let maxReliableDistance_m: Float = 1.5
    private let minConfidence: Float = 0.5
    private let optimalConfidence: Float = 0.85

    // MARK: - Evaluation
    /// Comprehensive accuracy evaluation with material-specific error estimation
    func evaluateAccuracy(
        metrics: ScanQualityMetrics,
        materialCategory: MaterialCategory,
        calibrationFactor: Float? = nil
    ) -> AccuracyResult {

        // Calculate individual error components
        let pointError = calculatePointCountError(metrics.pointCount)
        let distanceError = calculateDistanceError(metrics.distance_m)
        let confidenceError = calculateConfidenceError(metrics.averageConfidence)
        let materialError = calculateMaterialError(materialCategory)
        let calibrationError = calculateCalibrationError(calibrationFactor)
        let meshQualityError = calculateMeshQualityError(metrics.meshDensity, coverage: metrics.coverageScore)

        // Combined error (RMS - Root Mean Square)
        let totalError = sqrt(
            pow(pointError, 2) +
            pow(distanceError, 2) +
            pow(confidenceError, 2) +
            pow(materialError, 2) +
            pow(calibrationError, 2) +
            pow(meshQualityError, 2)
        )

        // Calculate confidence level
        let confidence = calculateConfidenceLevel(metrics: metrics)

        // Calculate quality score
        let quality = calculateQualityScore(metrics: metrics, totalError: totalError)

        // Generate recommendations
        let recommendations = generateRecommendations(
            metrics: metrics,
            pointError: pointError,
            distanceError: distanceError,
            confidenceError: confidenceError,
            meshQualityError: meshQualityError
        )

        let breakdown = AccuracyResult.ErrorBreakdown(
            pointCountError: pointError,
            distanceError: distanceError,
            confidenceError: confidenceError,
            materialError: materialError,
            calibrationError: calibrationError,
            meshQualityError: meshQualityError
        )

        return AccuracyResult(
            volumeM3: 0.0, // To be filled by caller
            weightG: 0.0,  // To be filled by caller
            estimatedErrorPercent: totalError * 100.0,
            confidenceLevel: confidence,
            qualityScore: quality,
            recommendations: recommendations,
            errorBreakdown: breakdown
        )
    }

    // MARK: - Error Calculations

    /// Point count impact on accuracy
    private func calculatePointCountError(_ pointCount: Int) -> Float {
        if pointCount >= optimalPointCount {
            return 0.01 // 1% error for optimal point count
        } else if pointCount < minPointCount {
            return 0.15 // 15% error for insufficient points
        } else {
            // Linear interpolation between min and optimal
            let ratio = Float(pointCount - minPointCount) / Float(optimalPointCount - minPointCount)
            return 0.15 - (ratio * 0.14) // 15% down to 1%
        }
    }

    /// Distance impact on accuracy (LiDAR accuracy degrades with distance)
    private func calculateDistanceError(_ distance_m: Float) -> Float {
        if distance_m <= optimalDistance_m {
            return 0.02 // 2% error at optimal distance
        } else if distance_m > maxReliableDistance_m {
            return 0.20 // 20% error beyond reliable range
        } else {
            // Exponential degradation
            let factor = (distance_m - optimalDistance_m) / (maxReliableDistance_m - optimalDistance_m)
            return 0.02 + (pow(factor, 1.5) * 0.18)
        }
    }

    /// Confidence impact on accuracy
    private func calculateConfidenceError(_ averageConfidence: Float) -> Float {
        if averageConfidence >= optimalConfidence {
            return 0.01 // 1% error for high confidence
        } else if averageConfidence < minConfidence {
            return 0.12 // 12% error for low confidence
        } else {
            let ratio = (averageConfidence - minConfidence) / (optimalConfidence - minConfidence)
            return 0.12 - (ratio * 0.11)
        }
    }

    /// Material-specific error based on category
    private func calculateMaterialError(_ category: MaterialCategory) -> Float {
        switch category {
        case .dairy:
            // Solid, well-defined shapes - low error
            return 0.02 // 2%
        case .liquids:
            // Liquids require container - moderate error
            return 0.05 // 5%
        case .flour, .powder:
            // Powders - irregular shapes, high error
            return 0.10 // 10%
        case .sugar, .salt:
            // Granular - moderate error
            return 0.06 // 6%
        case .grains:
            // Grains - moderate to high error
            return 0.07 // 7%
        case .nuts:
            // Irregular shapes - high error
            return 0.09 // 9%
        case .spices:
            // Very small particles - highest error
            return 0.12 // 12%
        case .custom:
            // Unknown material - conservative estimate
            return 0.10 // 10%
        }
    }

    /// Calibration impact on accuracy
    private func calculateCalibrationError(_ calibrationFactor: Float?) -> Float {
        guard let factor = calibrationFactor else {
            return 0.08 // 8% error without calibration
        }

        // Good calibration should be close to 1.0
        let deviation = abs(factor - 1.0)
        if deviation < 0.05 {
            return 0.01 // 1% error with excellent calibration
        } else if deviation < 0.15 {
            return 0.03 // 3% error with good calibration
        } else {
            return 0.06 // 6% error with poor calibration
        }
    }

    /// Mesh quality and coverage impact
    private func calculateMeshQualityError(_ meshDensity: Float, coverage: Float) -> Float {
        // Mesh density error (points per m²)
        let densityError: Float
        if meshDensity > 1000 {
            densityError = 0.01 // 1% for high density
        } else if meshDensity < 100 {
            densityError = 0.10 // 10% for low density
        } else {
            densityError = 0.10 - ((meshDensity - 100) / 900) * 0.09
        }

        // Coverage error
        let coverageError = (1.0 - coverage) * 0.15 // Up to 15% error for poor coverage

        return sqrt(pow(densityError, 2) + pow(coverageError, 2))
    }

    // MARK: - Confidence & Quality

    /// Calculate overall confidence level (0-1)
    private func calculateConfidenceLevel(metrics: ScanQualityMetrics) -> Float {
        var confidence: Float = 0.0

        // Point count contribution (30%)
        let pointRatio = min(Float(metrics.pointCount) / Float(optimalPointCount), 1.0)
        confidence += pointRatio * 0.30

        // Confidence contribution (40%)
        let confRatio = min(metrics.averageConfidence / optimalConfidence, 1.0)
        confidence += confRatio * 0.40

        // Distance contribution (15%)
        let distRatio = 1.0 - min(metrics.distance_m / maxReliableDistance_m, 1.0)
        confidence += distRatio * 0.15

        // Coverage contribution (15%)
        confidence += metrics.coverageScore * 0.15

        return min(confidence, 1.0)
    }

    /// Calculate overall quality score (0-1)
    private func calculateQualityScore(metrics: ScanQualityMetrics, totalError: Float) -> Float {
        // Lower error = higher quality
        let errorScore = max(0.0, 1.0 - totalError)

        // Combine with confidence
        let confidence = calculateConfidenceLevel(metrics: metrics)

        // Weighted average
        return (errorScore * 0.6) + (confidence * 0.4)
    }

    // MARK: - Recommendations

    /// Generate actionable recommendations to improve accuracy
    private func generateRecommendations(
        metrics: ScanQualityMetrics,
        pointError: Float,
        distanceError: Float,
        confidenceError: Float,
        meshQualityError: Float
    ) -> [String] {
        var recommendations: [String] = []

        // Point count recommendations
        if pointError > 0.08 {
            if metrics.pointCount < minPointCount {
                recommendations.append("⚠️ Zu wenig Datenpunkte! Scannen Sie das Objekt länger.")
            } else {
                recommendations.append("💡 Mehr Datenpunkte für bessere Genauigkeit sammeln.")
            }
        }

        // Distance recommendations
        if distanceError > 0.05 {
            if metrics.distance_m > maxReliableDistance_m {
                recommendations.append("⚠️ Zu weit entfernt! Gehen Sie näher ans Objekt (30-40cm).")
            } else if metrics.distance_m > optimalDistance_m + 0.2 {
                recommendations.append("💡 Näher herangehen für bessere Genauigkeit (30cm ideal).")
            }
        }

        // Confidence recommendations
        if confidenceError > 0.05 {
            recommendations.append("💡 Bessere Beleuchtung verwenden für höhere Scan-Qualität.")
            recommendations.append("💡 Objekt auf kontrastreicher Unterlage platzieren.")
        }

        // Mesh quality recommendations
        if meshQualityError > 0.08 {
            if metrics.coverageScore < 0.7 {
                recommendations.append("⚠️ Unvollständige Abdeckung! Scannen Sie von mehreren Winkeln.")
            }
            if metrics.meshDensity < 300 {
                recommendations.append("💡 Langsamer scannen für höhere Mesh-Dichte.")
            }
        }

        // Calibration recommendation
        if !metrics.isCalibrated {
            recommendations.append("🎯 Kalibrierung durchführen für höchste Genauigkeit.")
        }

        // Multi-scan recommendation for powders
        if metrics.coverageScore < 0.8 {
            recommendations.append("💡 Multi-Scan-Modus für unregelmäßige Formen nutzen.")
        }

        // If everything is good
        if recommendations.isEmpty {
            recommendations.append("✅ Ausgezeichnete Scan-Qualität!")
        }

        return recommendations
    }

    // MARK: - Quality Thresholds

    /// Get quality rating as string
    func getQualityRating(qualityScore: Float) -> String {
        switch qualityScore {
        case 0.9...1.0: return "Exzellent"
        case 0.8..<0.9: return "Sehr gut"
        case 0.7..<0.8: return "Gut"
        case 0.6..<0.7: return "Befriedigend"
        case 0.5..<0.6: return "Ausreichend"
        default: return "Ungenügend"
        }
    }

    /// Check if scan meets minimum quality standards
    func meetsMinimumQuality(result: AccuracyResult) -> Bool {
        return result.confidenceLevel >= 0.5 &&
               result.qualityScore >= 0.5 &&
               result.estimatedErrorPercent <= 25.0
    }
}

// MARK: - Helper Extensions

extension ScanQualityMetrics {
    /// Create metrics from scan data
    static func from(
        points: [simd_float3],
        confidence: [Float],
        cameraPosition: simd_float3,
        isCalibrated: Bool
    ) -> ScanQualityMetrics {

        let avgConfidence = confidence.isEmpty ? 0.0 : confidence.reduce(0.0, +) / Float(confidence.count)

        // Calculate distance (average distance from camera to points)
        let distances = points.map { simd_distance($0, cameraPosition) }
        let avgDistance = distances.isEmpty ? 0.0 : distances.reduce(0.0, +) / Float(distances.count)

        // Calculate mesh density (points per square meter)
        let boundingBoxArea = calculateBoundingBoxArea(points: points)
        let meshDensity = boundingBoxArea > 0 ? Float(points.count) / boundingBoxArea : 0.0

        // Calculate coverage score
        let coverage = calculateCoverageScore(points: points)

        return ScanQualityMetrics(
            pointCount: points.count,
            averageConfidence: avgConfidence,
            distance_m: avgDistance,
            meshDensity: meshDensity,
            coverageScore: coverage,
            isCalibrated: isCalibrated
        )
    }

    private static func calculateBoundingBoxArea(points: [simd_float3]) -> Float {
        guard points.count > 1 else { return 0.0 }

        let minX = points.map { $0.x }.min() ?? 0
        let maxX = points.map { $0.x }.max() ?? 0
        let minY = points.map { $0.y }.min() ?? 0
        let maxY = points.map { $0.y }.max() ?? 0
        let minZ = points.map { $0.z }.min() ?? 0
        let maxZ = points.map { $0.z }.max() ?? 0

        // Surface area of bounding box
        let dx = maxX - minX
        let dy = maxY - minY
        let dz = maxZ - minZ

        return 2.0 * (dx * dy + dy * dz + dz * dx)
    }

    private static func calculateCoverageScore(points: [simd_float3]) -> Float {
        guard points.count > 10 else { return 0.0 }

        // Use spatial distribution analysis
        // Divide space into grid and check coverage
        let gridSize = 10
        var grid = Array(repeating: Array(repeating: Array(repeating: false, count: gridSize), count: gridSize), count: gridSize)

        guard let minX = points.map({ $0.x }).min(),
              let maxX = points.map({ $0.x }).max(),
              let minY = points.map({ $0.y }).min(),
              let maxY = points.map({ $0.y }).max(),
              let minZ = points.map({ $0.z }).min(),
              let maxZ = points.map({ $0.z }).max() else {
            return 0.0
        }

        let dx = maxX - minX
        let dy = maxY - minY
        let dz = maxZ - minZ

        guard dx > 0, dy > 0, dz > 0 else { return 0.0 }

        for point in points {
            let ix = Int((point.x - minX) / dx * Float(gridSize - 1))
            let iy = Int((point.y - minY) / dy * Float(gridSize - 1))
            let iz = Int((point.z - minZ) / dz * Float(gridSize - 1))

            if ix >= 0 && ix < gridSize && iy >= 0 && iy < gridSize && iz >= 0 && iz < gridSize {
                grid[ix][iy][iz] = true
            }
        }

        // Count filled cells
        var filledCells = 0
        var totalCells = 0
        for x in 0..<gridSize {
            for y in 0..<gridSize {
                for z in 0..<gridSize {
                    totalCells += 1
                    if grid[x][y][z] {
                        filledCells += 1
                    }
                }
            }
        }

        return Float(filledCells) / Float(totalCells)
    }
}
