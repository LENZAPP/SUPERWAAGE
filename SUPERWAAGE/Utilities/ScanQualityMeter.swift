//
//  ScanQualityMeter.swift
//  SUPERWAAGE
//
//  Real-time scan quality assessment for AR depth scanning
//  Provides 5 quality metrics: features, lighting, depth, motion, overlap
//

import Foundation
import ARKit
import simd

/// Real-time scan quality assessment
/// Returns quality score 0.0-1.0 and recommendations
class ScanQualityMeter {

    // MARK: - Quality Metrics

    struct QualityMetrics {
        let featureQuality: Float       // 0.0-1.0: Feature point density
        let lightingQuality: Float      // 0.0-1.0: Lighting conditions
        let depthQuality: Float         // 0.0-1.0: Depth data availability
        let motionQuality: Float        // 0.0-1.0: Camera motion stability
        let overlapQuality: Float       // 0.0-1.0: Coverage overlap
        let overallScore: Float         // 0.0-1.0: Weighted average
        let recommendations: [String]   // User guidance
    }

    // MARK: - Properties

    private var previousTransform: simd_float4x4?
    private var coverageGrid: Set<SIMD3<Int>> = []
    private let gridResolution: Float = 0.05 // 5cm cells

    // Tunable quality weights
    private let featureWeight: Float = 0.35
    private let lightingWeight: Float = 0.25
    private let depthWeight: Float = 0.20
    private let motionWeight: Float = 0.15
    private let overlapWeight: Float = 0.05

    // MARK: - Public Interface

    /// Evaluate quality from ARFrame
    func evaluateQuality(frame: ARFrame) -> QualityMetrics {
        let featureQuality = assessFeatures(frame: frame)
        let lightingQuality = assessLighting(frame: frame)
        let depthQuality = assessDepth(frame: frame)
        let motionQuality = assessMotion(frame: frame)
        let overlapQuality = assessOverlap(frame: frame)

        // Calculate weighted overall score
        let overallScore =
            featureQuality * featureWeight +
            lightingQuality * lightingWeight +
            depthQuality * depthWeight +
            motionQuality * motionWeight +
            overlapQuality * overlapWeight

        // Generate recommendations
        let recommendations = generateRecommendations(
            features: featureQuality,
            lighting: lightingQuality,
            depth: depthQuality,
            motion: motionQuality,
            overlap: overlapQuality
        )

        return QualityMetrics(
            featureQuality: featureQuality,
            lightingQuality: lightingQuality,
            depthQuality: depthQuality,
            motionQuality: motionQuality,
            overlapQuality: overlapQuality,
            overallScore: overallScore,
            recommendations: recommendations
        )
    }

    /// Reset coverage tracking
    func resetCoverage() {
        coverageGrid.removeAll()
        previousTransform = nil
    }

    // MARK: - Quality Assessment Methods

    /// Assess feature point density and distribution
    private func assessFeatures(frame: ARFrame) -> Float {
        guard let rawFeaturePoints = frame.rawFeaturePoints else {
            return 0.3 // Low score if no features
        }

        let featureCount = rawFeaturePoints.points.count

        // Good feature count: 500-2000+
        if featureCount >= 1000 {
            return 1.0
        } else if featureCount >= 500 {
            return 0.8
        } else if featureCount >= 200 {
            return 0.6
        } else {
            return 0.3
        }
    }

    /// Assess lighting conditions
    private func assessLighting(frame: ARFrame) -> Float {
        // Check if we have light estimation
        guard let lightEstimate = frame.lightEstimate else {
            return 0.5 // Neutral if no estimate
        }

        let ambientIntensity = lightEstimate.ambientIntensity

        // Good lighting: 800-1500 lumens
        // Too dark: <400, Too bright: >2000
        if ambientIntensity >= 800 && ambientIntensity <= 1500 {
            return 1.0
        } else if ambientIntensity >= 500 && ambientIntensity <= 2000 {
            return 0.7
        } else if ambientIntensity >= 300 {
            return 0.5
        } else {
            return 0.3 // Too dark
        }
    }

    /// Assess depth data quality
    private func assessDepth(frame: ARFrame) -> Float {
        guard let depthData = frame.sceneDepth else {
            return 0.0 // No LiDAR
        }

        // Sample depth confidence
        let _ = depthData.depthMap  // TODO: Could use for depth range analysis
        guard let confidenceMap = depthData.confidenceMap else {
            return 0.5 // No confidence data available
        }

        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
        }

        let width = CVPixelBufferGetWidth(confidenceMap)
        let height = CVPixelBufferGetHeight(confidenceMap)
        guard let confidencePtr = CVPixelBufferGetBaseAddress(confidenceMap)?.assumingMemoryBound(to: UInt8.self) else {
            return 0.5
        }

        // Sample confidence at center region (middle 50%)
        var highConfidenceCount = 0
        var totalSamples = 0

        let startX = width / 4
        let endX = width * 3 / 4
        let startY = height / 4
        let endY = height * 3 / 4
        let step = 20 // Sample every 20 pixels

        for y in stride(from: startY, to: endY, by: step) {
            for x in stride(from: startX, to: endX, by: step) {
                let idx = y * width + x
                let confidence = confidencePtr[idx]
                if confidence >= 2 { // High confidence
                    highConfidenceCount += 1
                }
                totalSamples += 1
            }
        }

        let confidenceRatio = Float(highConfidenceCount) / Float(totalSamples)

        if confidenceRatio >= 0.7 {
            return 1.0
        } else if confidenceRatio >= 0.5 {
            return 0.7
        } else if confidenceRatio >= 0.3 {
            return 0.5
        } else {
            return 0.3
        }
    }

    /// Assess camera motion stability
    private func assessMotion(frame: ARFrame) -> Float {
        let currentTransform = frame.camera.transform
        defer {
            previousTransform = currentTransform
        }

        guard let previousTransform = previousTransform else {
            return 1.0 // First frame is stable
        }

        // Calculate translation distance
        let currentPosition = SIMD3<Float>(currentTransform.columns.3.x,
                                           currentTransform.columns.3.y,
                                           currentTransform.columns.3.z)
        let previousPosition = SIMD3<Float>(previousTransform.columns.3.x,
                                            previousTransform.columns.3.y,
                                            previousTransform.columns.3.z)
        let translation = distance(currentPosition, previousPosition)

        // Calculate rotation angle
        let rotationDelta = simd_mul(simd_inverse(previousTransform), currentTransform)
        let angle = acos(min(max((rotationDelta[0][0] + rotationDelta[1][1] + rotationDelta[2][2] - 1.0) / 2.0, -1.0), 1.0))

        // Good motion: 0.01-0.05m translation, <0.1 rad rotation per frame
        let translationScore: Float = {
            if translation < 0.001 {
                return 0.5 // Too slow
            } else if translation < 0.05 {
                return 1.0 // Good
            } else if translation < 0.10 {
                return 0.7 // Bit fast
            } else {
                return 0.3 // Too fast
            }
        }()

        let rotationScore: Float = {
            if angle < 0.1 {
                return 1.0 // Stable
            } else if angle < 0.2 {
                return 0.7 // Acceptable
            } else {
                return 0.3 // Too fast
            }
        }()

        return (translationScore + rotationScore) / 2.0
    }

    /// Assess spatial coverage overlap
    private func assessOverlap(frame: ARFrame) -> Float {
        let currentTransform = frame.camera.transform
        let position = SIMD3<Float>(currentTransform.columns.3.x,
                                    currentTransform.columns.3.y,
                                    currentTransform.columns.3.z)

        // Discretize position to grid cell
        let gridX = Int(round(position.x / gridResolution))
        let gridY = Int(round(position.y / gridResolution))
        let gridZ = Int(round(position.z / gridResolution))
        let gridCell = SIMD3<Int>(gridX, gridY, gridZ)

        // Check if we've been here before
        let isNewArea = !coverageGrid.contains(gridCell)
        coverageGrid.insert(gridCell)

        // Reward new coverage, but also accept some revisiting for robustness
        if isNewArea {
            return 1.0 // New area
        } else if coverageGrid.count > 10 {
            return 0.7 // Acceptable revisit (have some coverage already)
        } else {
            return 0.5 // Too much overlap early
        }
    }

    // MARK: - Recommendations

    /// Generate user-friendly recommendations
    private func generateRecommendations(
        features: Float,
        lighting: Float,
        depth: Float,
        motion: Float,
        overlap: Float
    ) -> [String] {
        var recommendations: [String] = []

        if features < 0.5 {
            recommendations.append("Point at textured surfaces")
        }

        if lighting < 0.5 {
            recommendations.append("Improve lighting")
        }

        if depth < 0.5 {
            recommendations.append("Move closer to object")
        }

        if motion < 0.5 {
            recommendations.append("Move slower and smoother")
        }

        if overlap < 0.5 {
            recommendations.append("Cover new areas")
        }

        // Positive feedback
        if features >= 0.8 && lighting >= 0.8 && depth >= 0.8 {
            recommendations.append("Good scan quality!")
        }

        return recommendations
    }
}

// MARK: - Usage Example

/*

 let qualityMeter = ScanQualityMeter()

 func session(_ session: ARSession, didUpdate frame: ARFrame) {
     let metrics = qualityMeter.evaluateQuality(frame: frame)

     print("Quality: \(Int(metrics.overallScore * 100))%")
     print("Features: \(metrics.featureQuality)")
     print("Lighting: \(metrics.lightingQuality)")
     print("Depth: \(metrics.depthQuality)")
     print("Motion: \(metrics.motionQuality)")

     for recommendation in metrics.recommendations {
         print("💡 \(recommendation)")
     }

     // Update UI
     self.qualityScore = Double(metrics.overallScore)
     self.recommendations = metrics.recommendations
 }

 */
