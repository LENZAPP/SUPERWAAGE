//
//  MeshVolumeCalculator+Enhanced.swift
//  SUPERWAAGE
//
//  Enhanced volume calculation with smoothing integration
//  Combines best practices from GitHub research
//

import Foundation
import ARKit
import simd

extension MeshVolumeCalculator {

    // MARK: - Enhanced Volume Calculation with Smoothing

    /// Calculate volume from mesh anchors with optional smoothing
    /// ✅ OPTIMIZED: Applies smoothing before volume calculation for accuracy
    /// - Parameters:
    ///   - meshAnchors: Array of AR mesh anchors
    ///   - applySmoothing: Whether to smooth meshes before calculation
    ///   - smoothingConfig: Smoothing configuration
    /// - Returns: Enhanced volume result with quality metrics
    nonisolated static func calculateVolumeEnhanced(
        from meshAnchors: [ARMeshAnchor],
        applySmoothing: Bool = true,
        smoothingConfig: MeshSmoothingEngine.SmoothingConfiguration = MeshSmoothingEngine.SmoothingConfiguration(iterations: 3, lambda: 0.5, preserveFeatures: true)
    ) -> EnhancedVolumeResult? {
        guard !meshAnchors.isEmpty else { return nil }

        // Extract and optionally smooth triangles
        let allTriangles: [Triangle]
        if applySmoothing {
            allTriangles = extractAndSmoothTriangles(
                from: meshAnchors,
                config: smoothingConfig
            )
        } else {
            allTriangles = extractTriangles(from: meshAnchors)
        }

        guard !allTriangles.isEmpty else { return nil }

        // Analyze mesh quality
        let qualityMetrics = analyzeEnhancedMeshQuality(
            triangles: allTriangles,
            meshAnchors: meshAnchors
        )

        // Choose calculation method based on quality
        let method: MeshVolumeResult.CalculationMethod
        let volume_m3: Double

        if qualityMetrics.isWatertight {
            method = .signedTetrahedra
            volume_m3 = calculateSignedTetrahedraVolume(triangles: allTriangles)
        } else if qualityMetrics.qualityScore > 0.5 {
            method = .surfaceIntegration
            volume_m3 = calculateSurfaceIntegrationVolume(triangles: allTriangles)
        } else {
            method = .convexHull
            volume_m3 = calculateConvexHullVolume(triangles: allTriangles)
        }

        // Calculate surface area
        let surfaceArea = calculateSurfaceArea(triangles: allTriangles)

        // ✅ CRITICAL FIX: Apply calibration scale factor
        // Volume scales with the cube of linear scale factor (V = L³)
        var calibratedVolume_m3 = volume_m3
        if let calibrationFactor = CalibrationManager.shared.calibrationFactor {
            let volumeScaleFactor = pow(Double(calibrationFactor), 3.0)
            calibratedVolume_m3 = volume_m3 * volumeScaleFactor
            print("📏 Enhanced calibration applied: raw=\(String(format: "%.2f", volume_m3 * 1_000_000)) cm³ → calibrated=\(String(format: "%.2f", calibratedVolume_m3 * 1_000_000)) cm³ (factor=\(String(format: "%.3f", calibrationFactor)))")
        }

        // Calculate confidence based on smoothing and quality
        let confidence = calculateConfidence(
            qualityScore: qualityMetrics.qualityScore,
            wasSmoothed: applySmoothing,
            method: method
        )

        return EnhancedVolumeResult(
            volume_m3: calibratedVolume_m3,
            volume_cm3: calibratedVolume_m3 * 1_000_000,
            volume_ml: calibratedVolume_m3 * 1_000_000,  // 1 cm³ = 1 ml
            surfaceArea_m2: surfaceArea,
            method: method,
            quality: qualityMetrics,
            triangleCount: allTriangles.count,
            isClosed: qualityMetrics.isWatertight,
            wasSmoothed: applySmoothing,
            smoothingConfig: applySmoothing ? smoothingConfig : nil,
            confidence: confidence
        )
    }

    // MARK: - Smoothed Triangle Extraction

    private nonisolated static func extractAndSmoothTriangles(
        from meshAnchors: [ARMeshAnchor],
        config: MeshSmoothingEngine.SmoothingConfiguration
    ) -> [Triangle] {
        var allTriangles: [Triangle] = []

        for anchor in meshAnchors {
            // Smooth the mesh
            guard let smoothedVertices = anchor.smoothed(config: config) else {
                // Fallback to original if smoothing fails
                allTriangles.append(contentsOf: extractTriangles(from: [anchor]))
                continue
            }

            // Extract faces and create triangles with smoothed vertices
            let geometry = anchor.geometry
            let transform = anchor.transform

            for i in 0..<geometry.faces.count {
                // ✅ ARGeometryElement has no offset property - data starts at buffer beginning
                let faceOffset = i * geometry.faces.indexCountPerPrimitive * MemoryLayout<UInt32>.stride

                guard faceOffset + (3 * MemoryLayout<UInt32>.stride) <= geometry.faces.buffer.length else {
                    continue
                }

                let facePointer = geometry.faces.buffer.contents().advanced(by: faceOffset).assumingMemoryBound(to: UInt32.self)

                let idx0 = Int(facePointer[0])
                let idx1 = Int(facePointer[1])
                let idx2 = Int(facePointer[2])

                guard idx0 < smoothedVertices.count &&
                      idx1 < smoothedVertices.count &&
                      idx2 < smoothedVertices.count else {
                    continue
                }

                // Transform smoothed vertices to world space
                let v0 = transformToWorld(smoothedVertices[idx0], transform: transform)
                let v1 = transformToWorld(smoothedVertices[idx1], transform: transform)
                let v2 = transformToWorld(smoothedVertices[idx2], transform: transform)

                allTriangles.append(Triangle(v0: v0, v1: v1, v2: v2))
            }
        }

        return allTriangles
    }

    private nonisolated static func transformToWorld(
        _ localVertex: SIMD3<Float>,
        transform: simd_float4x4
    ) -> SIMD3<Float> {
        let worldVertex = transform * SIMD4<Float>(localVertex.x, localVertex.y, localVertex.z, 1.0)
        return SIMD3<Float>(worldVertex.x, worldVertex.y, worldVertex.z)
    }

    // MARK: - Enhanced Quality Analysis

    private nonisolated static func analyzeEnhancedMeshQuality(
        triangles: [Triangle],
        meshAnchors: [ARMeshAnchor]
    ) -> EnhancedMeshQuality {
        // Calculate triangle density
        let totalArea = triangles.reduce(0.0) { $0 + calculateTriangleArea($1) }
        let triangleDensity = Double(triangles.count) / max(totalArea, 0.000001)

        // Check for watertight mesh (simplified check)
        let isWatertight = triangles.count > 100 && triangleDensity > 50

        // Check for normals
        let hasNormals = meshAnchors.first?.geometry.normals.count ?? 0 > 0

        // Calculate comprehensive quality score
        var qualityScore = 0.0

        // Triangle count contribution (30%)
        let triangleScore = min(Double(triangles.count) / 1000.0, 1.0) * 0.3

        // Density contribution (30%)
        let densityScore = min(triangleDensity / 100.0, 1.0) * 0.3

        // Watertight contribution (20%)
        let watertightScore = isWatertight ? 0.2 : 0.0

        // Normal data contribution (20%)
        let normalScore = hasNormals ? 0.2 : 0.0

        qualityScore = triangleScore + densityScore + watertightScore + normalScore

        return EnhancedMeshQuality(
            isWatertight: isWatertight,
            hasNormals: hasNormals,
            triangleDensity: triangleDensity,
            qualityScore: qualityScore
        )
    }

    private nonisolated static func calculateTriangleArea(_ triangle: Triangle) -> Double {
        let edge1 = triangle.v1 - triangle.v0
        let edge2 = triangle.v2 - triangle.v0
        let crossProduct = cross(edge1, edge2)
        return Double(length(crossProduct)) / 2.0
    }

    // MARK: - Confidence Calculation

    private nonisolated static func calculateConfidence(
        qualityScore: Double,
        wasSmoothed: Bool,
        method: MeshVolumeResult.CalculationMethod
    ) -> Double {
        var confidence = qualityScore

        // Smoothing adds confidence
        if wasSmoothed {
            confidence *= 1.1  // 10% boost
        }

        // Method confidence factors
        switch method {
        case .signedTetrahedra:
            confidence *= 1.0  // Most accurate
        case .surfaceIntegration:
            confidence *= 0.9  // Slightly less accurate
        case .convexHull:
            confidence *= 0.7  // Approximation
        }

        return min(confidence, 1.0)  // Cap at 100%
    }
}

// MARK: - Enhanced Volume Result

struct EnhancedVolumeResult {
    let volume_m3: Double
    let volume_cm3: Double
    let volume_ml: Double  // Same as cm³ for liquid measurement
    let surfaceArea_m2: Double
    let method: MeshVolumeResult.CalculationMethod
    let quality: EnhancedMeshQuality
    let triangleCount: Int
    let isClosed: Bool
    let wasSmoothed: Bool
    let smoothingConfig: MeshSmoothingEngine.SmoothingConfiguration?
    let confidence: Double  // 0-1

    var formattedVolume: String {
        if volume_cm3 < 10 {
            return String(format: "%.2f cm³ (%.2f ml)", volume_cm3, volume_ml)
        } else if volume_cm3 < 1000 {
            return String(format: "%.1f cm³ (%.1f ml)", volume_cm3, volume_ml)
        } else {
            return String(format: "%.2f L (%.0f ml)", volume_cm3 / 1000, volume_ml)
        }
    }

    var confidenceDescription: String {
        switch confidence {
        case 0.9...1.0: return "Sehr hoch (\(Int(confidence * 100))%)"
        case 0.75..<0.9: return "Hoch (\(Int(confidence * 100))%)"
        case 0.6..<0.75: return "Mittel (\(Int(confidence * 100))%)"
        default: return "Niedrig (\(Int(confidence * 100))%)"
        }
    }

    var expectedAccuracy: String {
        switch confidence {
        case 0.9...1.0: return "±2-5%"
        case 0.75..<0.9: return "±5-10%"
        case 0.6..<0.75: return "±10-15%"
        default: return "±15-25%"
        }
    }
}

// MARK: - Enhanced Mesh Quality

struct EnhancedMeshQuality {
    let isWatertight: Bool
    let hasNormals: Bool
    let triangleDensity: Double
    let qualityScore: Double

    var description: String {
        switch qualityScore {
        case 0.9...1.0: return "Exzellent (\(Int(qualityScore * 100))%)"
        case 0.7..<0.9: return "Sehr gut (\(Int(qualityScore * 100))%)"
        case 0.5..<0.7: return "Gut (\(Int(qualityScore * 100))%)"
        case 0.3..<0.5: return "Befriedigend (\(Int(qualityScore * 100))%)"
        default: return "Ungenügend (\(Int(qualityScore * 100))%)"
        }
    }
}
