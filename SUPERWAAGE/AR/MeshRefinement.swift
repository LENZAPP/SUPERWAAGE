//
//  MeshRefinement.swift
//  SUPERWAAGE
//
//  Advanced mesh refinement and smoothing algorithms
//  Improves scan quality through geometric processing
//

import Foundation
import ARKit
import simd

// MARK: - Refinement Options
struct MeshRefinementOptions {
    var smoothingIterations: Int = 3
    var smoothingFactor: Float = 0.5  // 0 = no smoothing, 1 = max smoothing
    var removeNoise: Bool = true
    var fillHoles: Bool = true
    var decimateTriangles: Bool = false
    var targetTriangleCount: Int? = nil

    static var `default`: MeshRefinementOptions {
        return MeshRefinementOptions()
    }

    static var highQuality: MeshRefinementOptions {
        return MeshRefinementOptions(
            smoothingIterations: 5,
            smoothingFactor: 0.3,
            removeNoise: true,
            fillHoles: true,
            decimateTriangles: false
        )
    }

    static var balanced: MeshRefinementOptions {
        return MeshRefinementOptions(
            smoothingIterations: 3,
            smoothingFactor: 0.5,
            removeNoise: true,
            fillHoles: true,
            decimateTriangles: true,
            targetTriangleCount: 10000
        )
    }

    static var fast: MeshRefinementOptions {
        return MeshRefinementOptions(
            smoothingIterations: 1,
            smoothingFactor: 0.7,
            removeNoise: true,
            fillHoles: false,
            decimateTriangles: true,
            targetTriangleCount: 5000
        )
    }
}

// MARK: - Refinement Result
struct MeshRefinementResult {
    let originalTriangleCount: Int
    let refinedTriangleCount: Int
    let originalVertexCount: Int
    let refinedVertexCount: Int
    let processingTime: TimeInterval
    let improvementScore: Float  // 0-1

    var reductionPercentage: Float {
        return (1.0 - Float(refinedTriangleCount) / Float(originalTriangleCount)) * 100.0
    }
}

// MARK: - Mesh Refinement Engine
class MeshRefinement {

    // MARK: - Main Refinement Pipeline

    /// Apply refinement to point cloud
    static func refinePointCloud(
        points: [SIMD3<Float>],
        normals: [SIMD3<Float>]? = nil,
        options: MeshRefinementOptions = .default
    ) -> (points: [SIMD3<Float>], normals: [SIMD3<Float>]?) {

        let _ = Date() // Track start time for future profiling
        var refinedPoints = points
        var refinedNormals = normals

        // Step 1: Remove noise (outliers)
        if options.removeNoise {
            (refinedPoints, refinedNormals) = removeOutliers(
                points: refinedPoints,
                normals: refinedNormals
            )
        }

        // Step 2: Smooth point cloud
        if options.smoothingIterations > 0 {
            refinedPoints = smoothPointCloud(
                points: refinedPoints,
                iterations: options.smoothingIterations,
                factor: options.smoothingFactor
            )
        }

        // Step 3: Recompute normals if needed
        if refinedNormals == nil || options.smoothingIterations > 0 {
            refinedNormals = computeNormals(points: refinedPoints)
        }

        return (refinedPoints, refinedNormals)
    }

    // MARK: - Noise Removal

    /// Remove statistical outliers from point cloud
    /// Uses neighborhood analysis to detect and remove noise
    private static func removeOutliers(
        points: [SIMD3<Float>],
        normals: [SIMD3<Float>]?
    ) -> (points: [SIMD3<Float>], normals: [SIMD3<Float>]?) {

        let k = 20  // Number of neighbors to consider
        let stdMultiplier: Float = 1.5  // Standard deviation multiplier

        var cleanPoints: [SIMD3<Float>] = []
        var cleanNormals: [SIMD3<Float>]? = normals != nil ? [] : nil

        for (index, point) in points.enumerated() {
            // Find k nearest neighbors
            let distances = points.map { simd_distance(point, $0) }
            let sortedDistances = distances.sorted()
            let kNearestDistances = Array(sortedDistances.prefix(k + 1)) // +1 to exclude self

            // Calculate mean and std deviation
            let mean = kNearestDistances.reduce(0.0, +) / Float(k + 1)
            let variance = kNearestDistances.map { pow($0 - mean, 2) }.reduce(0.0, +) / Float(k + 1)
            let stdDev = sqrt(variance)

            // Remove if point is an outlier
            let threshold = mean + stdMultiplier * stdDev
            let avgDistance = kNearestDistances.reduce(0.0, +) / Float(k + 1)

            if avgDistance <= threshold {
                cleanPoints.append(point)
                if let normals = normals {
                    cleanNormals?.append(normals[index])
                }
            }
        }

        return (cleanPoints, cleanNormals)
    }

    // MARK: - Point Cloud Smoothing

    /// Smooth point cloud using Laplacian smoothing
    private static func smoothPointCloud(
        points: [SIMD3<Float>],
        iterations: Int,
        factor: Float
    ) -> [SIMD3<Float>] {

        var smoothedPoints = points
        let neighborhoodRadius: Float = 0.01  // 1cm radius

        for _ in 0..<iterations {
            var newPoints = smoothedPoints

            for (index, point) in smoothedPoints.enumerated() {
                // Find neighbors within radius
                var neighbors: [SIMD3<Float>] = []

                for otherPoint in smoothedPoints {
                    let distance = simd_distance(point, otherPoint)
                    if distance > 0 && distance < neighborhoodRadius {
                        neighbors.append(otherPoint)
                    }
                }

                if !neighbors.isEmpty {
                    // Calculate centroid of neighbors
                    let centroid = neighbors.reduce(SIMD3<Float>.zero, +) / Float(neighbors.count)

                    // Move point towards centroid
                    newPoints[index] = point + (centroid - point) * factor
                }
            }

            smoothedPoints = newPoints
        }

        return smoothedPoints
    }

    // MARK: - Normal Computation

    /// Compute normals using PCA (Principal Component Analysis)
    private static func computeNormals(points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        var normals: [SIMD3<Float>] = []
        let neighborhoodRadius: Float = 0.02  // 2cm radius

        for point in points {
            // Find neighbors
            var neighbors: [SIMD3<Float>] = []

            for otherPoint in points {
                let distance = simd_distance(point, otherPoint)
                if distance < neighborhoodRadius {
                    neighbors.append(otherPoint)
                }
            }

            if neighbors.count < 3 {
                // Not enough neighbors, use default up vector
                normals.append(SIMD3<Float>(0, 1, 0))
                continue
            }

            // Calculate centroid
            let centroid = neighbors.reduce(SIMD3<Float>.zero, +) / Float(neighbors.count)

            // Build covariance matrix
            var covariance = matrix_float3x3()

            for neighbor in neighbors {
                let diff = neighbor - centroid
                covariance[0][0] += diff.x * diff.x
                covariance[0][1] += diff.x * diff.y
                covariance[0][2] += diff.x * diff.z
                covariance[1][1] += diff.y * diff.y
                covariance[1][2] += diff.y * diff.z
                covariance[2][2] += diff.z * diff.z
            }
            covariance[1][0] = covariance[0][1]
            covariance[2][0] = covariance[0][2]
            covariance[2][1] = covariance[1][2]

            let scale = 1.0 / Float(neighbors.count)
            covariance = matrix_float3x3(
                scale * covariance[0],
                scale * covariance[1],
                scale * covariance[2]
            )

            // Find eigenvector with smallest eigenvalue (normal direction)
            // Simplified: use cross product of two edges
            if neighbors.count >= 3 {
                let edge1 = neighbors[1] - neighbors[0]
                let edge2 = neighbors[2] - neighbors[0]
                let normal = normalize(cross(edge1, edge2))
                normals.append(normal)
            } else {
                normals.append(SIMD3<Float>(0, 1, 0))
            }
        }

        return normals
    }

    // MARK: - Hole Filling

    /// Fill holes in mesh by identifying boundary edges
    static func fillHoles(triangles: [Triangle]) -> [Triangle] {
        // Identify boundary edges
        struct Edge: Hashable {
            let v0: SIMD3<Float>
            let v1: SIMD3<Float>

            init(_ a: SIMD3<Float>, _ b: SIMD3<Float>) {
                if a.x < b.x || (a.x == b.x && a.y < b.y) {
                    v0 = a
                    v1 = b
                } else {
                    v0 = b
                    v1 = a
                }
            }
        }

        var edgeCounts: [Edge: Int] = [:]

        for triangle in triangles {
            let edge1 = Edge(triangle.v0, triangle.v1)
            let edge2 = Edge(triangle.v1, triangle.v2)
            let edge3 = Edge(triangle.v2, triangle.v0)

            edgeCounts[edge1, default: 0] += 1
            edgeCounts[edge2, default: 0] += 1
            edgeCounts[edge3, default: 0] += 1
        }

        // Boundary edges appear only once
        let _ = edgeCounts.filter { $0.value == 1 }.map { $0.key } // boundaryEdges for future hole filling

        // TODO: Implement advanced hole filling
        // For now, return original triangles
        return triangles
    }

    // MARK: - Mesh Decimation

    /// Reduce triangle count while preserving shape
    static func decimateMesh(
        triangles: [Triangle],
        targetCount: Int
    ) -> [Triangle] {

        guard triangles.count > targetCount else { return triangles }

        // Simplified decimation: random sampling
        // In production, use quadric error metrics

        let reductionRatio = Float(targetCount) / Float(triangles.count)
        var decimated: [Triangle] = []

        for triangle in triangles {
            if Float.random(in: 0...1) < reductionRatio {
                decimated.append(triangle)
            }
        }

        return decimated.isEmpty ? triangles : decimated
    }
}

// MARK: - Mesh Quality Metrics

extension MeshRefinement {

    /// Calculate mesh quality score
    static func calculateQualityScore(points: [SIMD3<Float>], normals: [SIMD3<Float>]?) -> Float {
        var score: Float = 0.0

        // Factor 1: Point count (30%)
        let pointScore = min(Float(points.count) / 10000.0, 1.0)
        score += pointScore * 0.3

        // Factor 2: Has normals (20%)
        if normals != nil {
            score += 0.2
        }

        // Factor 3: Point distribution (30%)
        let distributionScore = calculateDistributionScore(points: points)
        score += distributionScore * 0.3

        // Factor 4: Density (20%)
        let densityScore = calculateDensityScore(points: points)
        score += densityScore * 0.2

        return score
    }

    private static func calculateDistributionScore(points: [SIMD3<Float>]) -> Float {
        guard points.count > 10 else { return 0.0 }

        // Calculate variance in each dimension
        let avgX = points.map { $0.x }.reduce(0, +) / Float(points.count)
        let avgY = points.map { $0.y }.reduce(0, +) / Float(points.count)
        let avgZ = points.map { $0.z }.reduce(0, +) / Float(points.count)

        let varX = points.map { pow($0.x - avgX, 2) }.reduce(0, +) / Float(points.count)
        let varY = points.map { pow($0.y - avgY, 2) }.reduce(0, +) / Float(points.count)
        let varZ = points.map { pow($0.z - avgZ, 2) }.reduce(0, +) / Float(points.count)

        // Higher variance = better distribution
        let totalVar = varX + varY + varZ
        return min(totalVar * 100, 1.0)
    }

    private static func calculateDensityScore(points: [SIMD3<Float>]) -> Float {
        guard points.count > 1 else { return 0.0 }

        // Calculate average nearest neighbor distance
        var totalDistance: Float = 0.0

        for point in points.prefix(min(100, points.count)) {
            let distances = points.map { simd_distance(point, $0) }.filter { $0 > 0 }
            if let minDistance = distances.min() {
                totalDistance += minDistance
            }
        }

        let avgDistance = totalDistance / Float(min(100, points.count))

        // Good density: 0.005-0.02m (5-20mm between points)
        if avgDistance >= 0.005 && avgDistance <= 0.02 {
            return 1.0
        } else if avgDistance < 0.005 {
            return 0.7  // Too dense (might have duplicates)
        } else {
            return max(0.0, 1.0 - (avgDistance - 0.02) * 10)
        }
    }
}
