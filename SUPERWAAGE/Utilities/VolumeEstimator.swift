//
//  VolumeEstimator.swift
//  SUPERWAAGE
//
//  Advanced volume estimation optimized for kitchen materials
//  Supports both solid objects and irregular shapes (powders, heaps)
//

import Foundation
import simd
import ARKit

// MARK: - Volume Result
struct VolumeResult {
    let width_m: Float
    let height_m: Float
    let depth_m: Float
    let volume_m3: Float
    let volume_cm3: Float
    let method: VolumeMethod
    let confidence: Float
    let boundingBox: BoundingBox

    enum VolumeMethod: String {
        case boundingBox = "Bounding Box"
        case convexHull = "Convex Hull"
        case heightMap = "Height Map (Pulver)"
        case meshBased = "Mesh-basiert"
    }

    // Convenience getters in cm
    var width_cm: Float { width_m * 100.0 }
    var height_cm: Float { height_m * 100.0 }
    var depth_cm: Float { depth_m * 100.0 }
}

// MARK: - Volume Estimator
class VolumeEstimator {

    // MARK: - Configuration
    private let minPointsForMesh: Int = 500
    private let minPointsForHeightMap: Int = 200

    // MARK: - Main Estimation

    /// Estimate volume using the best method for the material type
    nonisolated func estimateVolume(
        from points: [simd_float3],
        normals: [simd_float3]? = nil,
        materialCategory: MaterialCategory,
        planeHeight: Float? = nil
    ) -> VolumeResult? {

        guard !points.isEmpty else { return nil }

        // Choose method based on material and data quality
        let method = selectBestMethod(
            pointCount: points.count,
            materialCategory: materialCategory,
            hasPlane: planeHeight != nil
        )

        switch method {
        case .heightMap:
            // Best for powders, granular materials on a flat surface
            return estimateVolumeHeightMap(points: points, planeHeight: planeHeight)

        case .convexHull:
            // Good for irregular but solid objects
            return estimateVolumeConvexHull(points: points)

        case .meshBased:
            // Best for well-defined solid objects with normals
            if let normals = normals {
                return estimateVolumeMeshBased(points: points, normals: normals)
            }
            fallthrough

        case .boundingBox:
            // Fallback: simple but reliable
            return estimateVolumeBoundingBox(points: points)
        }
    }

    // MARK: - Method Selection

    nonisolated private func selectBestMethod(
        pointCount: Int,
        materialCategory: MaterialCategory,
        hasPlane: Bool
    ) -> VolumeResult.VolumeMethod {

        // For powders and granular materials
        if (materialCategory == .flour || materialCategory == .powder ||
            materialCategory == .sugar || materialCategory == .grains ||
            materialCategory == .spices) && hasPlane {
            return pointCount >= minPointsForHeightMap ? .heightMap : .boundingBox
        }

        // For solid objects
        if materialCategory == .dairy || materialCategory == .nuts {
            if pointCount >= minPointsForMesh {
                return .meshBased
            } else if pointCount >= 300 {
                return .convexHull
            }
        }

        // Default fallback
        return .boundingBox
    }

    // MARK: - Bounding Box Method

    /// Simple bounding box volume (rectangular approximation)
    nonisolated func estimateVolumeBoundingBox(points: [simd_float3]) -> VolumeResult? {
        guard let bbox = BoundingBox.from(points: points) else { return nil }

        let size = bbox.size
        let volume_m3 = size.x * size.y * size.z
        let volume_cm3 = volume_m3 * 1_000_000.0

        return VolumeResult(
            width_m: size.x,
            height_m: size.y,
            depth_m: size.z,
            volume_m3: volume_m3,
            volume_cm3: volume_cm3,
            method: .boundingBox,
            confidence: 0.7, // Moderate confidence
            boundingBox: bbox
        )
    }

    // MARK: - Height Map Method (Optimized for Powders)

    /// Height map based volume - excellent for powders, flour heaps, etc.
    nonisolated func estimateVolumeHeightMap(points: [simd_float3], planeHeight: Float?) -> VolumeResult? {
        guard !points.isEmpty else { return nil }

        // Determine ground plane
        let groundY = planeHeight ?? (points.map { $0.y }.min() ?? 0)

        // Create 2D grid (top-down view)
        let gridResolution = 50 // 50x50 grid
        guard let bbox = BoundingBox.from(points: points) else { return nil }

        let size = bbox.size

        // ✅ CRASH FIX: Guard against zero or near-zero size
        guard size.x > 0.001 && size.z > 0.001 else {
            print("⚠️ Height map: Object too small (size: \(size))")
            return nil
        }

        let cellSizeX = size.x / Float(gridResolution)
        let cellSizeZ = size.z / Float(gridResolution)

        // ✅ CRASH FIX: Validate cell sizes
        guard cellSizeX.isFinite && cellSizeZ.isFinite && cellSizeX > 0 && cellSizeZ > 0 else {
            print("⚠️ Height map: Invalid cell size")
            return nil
        }

        // Build height map
        var heightMap = Array(repeating: Array(repeating: groundY, count: gridResolution), count: gridResolution)
        var cellHasData = Array(repeating: Array(repeating: false, count: gridResolution), count: gridResolution)

        for point in points {
            let normalizedX = (point.x - bbox.min.x) / size.x
            let normalizedZ = (point.z - bbox.min.z) / size.z

            let gridX = Int(normalizedX * Float(gridResolution - 1))
            let gridZ = Int(normalizedZ * Float(gridResolution - 1))

            if gridX >= 0 && gridX < gridResolution && gridZ >= 0 && gridZ < gridResolution {
                // Take maximum height in this cell
                if !cellHasData[gridX][gridZ] || point.y > heightMap[gridX][gridZ] {
                    heightMap[gridX][gridZ] = point.y
                    cellHasData[gridX][gridZ] = true
                }
            }
        }

        // Calculate volume by summing all cells
        var totalVolume: Float = 0.0
        var filledCells = 0

        for x in 0..<gridResolution {
            for z in 0..<gridResolution {
                if cellHasData[x][z] {
                    let height = heightMap[x][z] - groundY
                    if height > 0 {
                        // Volume of this column
                        let cellVolume = cellSizeX * height * cellSizeZ
                        totalVolume += cellVolume
                        filledCells += 1
                    }
                }
            }
        }

        // Interpolate for empty cells (smoothing)
        if filledCells > 10 {
            totalVolume = interpolateHeightMap(
                heightMap: &heightMap,
                cellHasData: &cellHasData,
                groundY: groundY,
                cellSizeX: cellSizeX,
                cellSizeZ: cellSizeZ,
                gridResolution: gridResolution
            )
        }

        let volume_cm3 = totalVolume * 1_000_000.0

        // Calculate dimensions
        let maxHeight = points.map { $0.y }.max() ?? groundY
        let height = maxHeight - groundY

        let confidence = min(Float(filledCells) / Float(gridResolution * gridResolution / 4), 1.0)

        return VolumeResult(
            width_m: size.x,
            height_m: height,
            depth_m: size.z,
            volume_m3: totalVolume,
            volume_cm3: volume_cm3,
            method: .heightMap,
            confidence: max(0.8, confidence), // Height map is quite accurate for powders
            boundingBox: bbox
        )
    }

    nonisolated private func interpolateHeightMap(
        heightMap: inout [[Float]],
        cellHasData: inout [[Bool]],
        groundY: Float,
        cellSizeX: Float,
        cellSizeZ: Float,
        gridResolution: Int
    ) -> Float {

        // Simple averaging for empty cells from neighbors
        for x in 0..<gridResolution {
            for z in 0..<gridResolution {
                if !cellHasData[x][z] {
                    // Get neighbor heights
                    var neighborHeights: [Float] = []
                    for dx in -1...1 {
                        for dz in -1...1 {
                            let nx = x + dx
                            let nz = z + dz
                            if nx >= 0 && nx < gridResolution && nz >= 0 && nz < gridResolution {
                                if cellHasData[nx][nz] {
                                    neighborHeights.append(heightMap[nx][nz])
                                }
                            }
                        }
                    }

                    if !neighborHeights.isEmpty {
                        heightMap[x][z] = neighborHeights.reduce(0, +) / Float(neighborHeights.count)
                        cellHasData[x][z] = true
                    }
                }
            }
        }

        // Recalculate volume
        var volume: Float = 0.0
        for x in 0..<gridResolution {
            for z in 0..<gridResolution {
                if cellHasData[x][z] {
                    let height = heightMap[x][z] - groundY
                    if height > 0 {
                        volume += cellSizeX * height * cellSizeZ
                    }
                }
            }
        }

        return volume
    }

    // MARK: - Convex Hull Method

    /// Convex hull approximation (better for irregular shapes)
    nonisolated func estimateVolumeConvexHull(points: [simd_float3]) -> VolumeResult? {
        // Simplified convex hull using QuickHull algorithm
        // For now, use enhanced bounding box with shrink factor

        // ✅ CRASH FIX: Guard against empty points
        guard !points.isEmpty else { return nil }

        guard let bbox = BoundingBox.from(points: points) else { return nil }

        // Analyze point distribution
        let centerOfMass = points.reduce(simd_float3.zero, +) / Float(points.count)

        // ✅ CRASH FIX: Validate centerOfMass
        guard centerOfMass.x.isFinite && centerOfMass.y.isFinite && centerOfMass.z.isFinite else {
            print("⚠️ Center of mass calculation produced NaN/Infinite in convex hull")
            return nil
        }

        // Calculate average distance from center (for future density analysis)
        let _ = points.map { simd_distance($0, centerOfMass) }.reduce(0, +) / Float(points.count)

        // Shrink factor based on distribution (convex hull is smaller than bounding box)
        let shrinkFactor: Float = 0.6 // Empirical value for typical objects

        let size = bbox.size
        let volume_m3 = size.x * size.y * size.z * shrinkFactor
        let volume_cm3 = volume_m3 * 1_000_000.0

        return VolumeResult(
            width_m: size.x,
            height_m: size.y,
            depth_m: size.z,
            volume_m3: volume_m3,
            volume_cm3: volume_cm3,
            method: .convexHull,
            confidence: 0.75,
            boundingBox: bbox
        )
    }

    // MARK: - Mesh-Based Method

    /// Mesh-based volume using ARKit mesh anchors
    nonisolated func estimateVolumeMeshBased(points: [simd_float3], normals: [simd_float3]) -> VolumeResult? {
        // Reconstruct triangles from points and normals
        // This is simplified - in production you'd use proper mesh reconstruction

        guard points.count == normals.count else {
            return estimateVolumeBoundingBox(points: points)
        }

        // For now, use enhanced convex hull
        return estimateVolumeConvexHull(points: points)
    }
}

// MARK: - Helper Extensions

extension VolumeResult {
    /// Formatted dimensions string
    var formattedDimensions: String {
        return String(format: "%.1f × %.1f × %.1f cm", width_cm, height_cm, depth_cm)
    }

    /// Formatted volume string
    var formattedVolume: String {
        if volume_cm3 < 10 {
            return String(format: "%.2f cm³", volume_cm3)
        } else if volume_cm3 < 1000 {
            return String(format: "%.1f cm³", volume_cm3)
        } else {
            let liters = volume_cm3 / 1000.0
            return String(format: "%.2f L (%.0f cm³)", liters, volume_cm3)
        }
    }

    /// Confidence description
    var confidenceText: String {
        switch confidence {
        case 0.9...1.0: return "Sehr hoch"
        case 0.8..<0.9: return "Hoch"
        case 0.7..<0.8: return "Mittel"
        case 0.6..<0.7: return "Moderat"
        default: return "Niedrig"
        }
    }
}
