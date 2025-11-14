//
//  MeshVolume.swift
//  SUPERWAAGE
//
//  Accurate mesh volume computation via tetrahedralization
//  Computes signed volume by subdividing mesh into tetrahedra from an origin point
//  More accurate than voxel-based volume estimates for closed meshes
//
//  Usage:
//    let (signedVol, absVol) = MeshVolume.computeVolume(vertices: verts, triangles: tris)
//    let volumeML = absVol * 1_000_000.0  // Convert m³ to mL
//

import Foundation
import simd

/// Mesh volume computation utilities
public struct MeshVolume {

    /// Compute mesh volume via tetrahedralization (origin-based method)
    ///
    /// This method subdivides the mesh into tetrahedra formed by the origin and each triangle face.
    /// The signed volume is computed using the scalar triple product formula.
    /// For closed, consistently-oriented meshes, this gives exact volume.
    ///
    /// - Parameters:
    ///   - vertices: Array of vertex positions in world space (meters)
    ///   - triangles: Array of triangle indices (triplets, counter-clockwise winding)
    ///   - origin: Origin point for tetrahedralization (typically mesh centroid or world origin)
    /// - Returns: Tuple of (signedVolume, absoluteVolume) in cubic meters
    ///
    /// **Note:** For consistent results, ensure mesh has consistent triangle winding order
    public static func computeVolume(vertices: [SIMD3<Float>],
                                    triangles: [UInt32],
                                    origin: SIMD3<Float> = SIMD3<Float>(0,0,0)) -> (signedVolume: Float, absoluteVolume: Float) {

        guard triangles.count % 3 == 0 else {
            print("⚠️ MeshVolume: Triangle count must be multiple of 3")
            return (0, 0)
        }

        guard !vertices.isEmpty && !triangles.isEmpty else {
            return (0, 0)
        }

        var signedVolume: Float = 0.0
        let triCount = triangles.count / 3

        // Process each triangle
        for i in 0..<triCount {
            let aIdx = Int(triangles[i * 3 + 0])
            let bIdx = Int(triangles[i * 3 + 1])
            let cIdx = Int(triangles[i * 3 + 2])

            // Bounds checking
            guard aIdx < vertices.count && bIdx < vertices.count && cIdx < vertices.count else {
                print("⚠️ MeshVolume: Invalid triangle index at triangle \(i)")
                continue
            }

            // Get triangle vertices relative to origin
            let a = vertices[aIdx] - origin
            let b = vertices[bIdx] - origin
            let c = vertices[cIdx] - origin

            // Compute signed volume of tetrahedron (origin, a, b, c)
            // Volume = (1/6) * dot(a, cross(b, c))
            // This is the scalar triple product divided by 6
            let crossBC = cross(b, c)
            let scalarTriple = dot(a, crossBC)
            let tetraVolume = scalarTriple / 6.0

            signedVolume += tetraVolume
        }

        let absoluteVolume = abs(signedVolume)

        return (signedVolume, absoluteVolume)
    }

    /// Compute volume with automatic centroid as origin
    /// Recommended for most use cases as it reduces numerical precision issues
    ///
    /// - Parameters:
    ///   - vertices: Array of vertex positions
    ///   - triangles: Array of triangle indices
    /// - Returns: Tuple of (signedVolume, absoluteVolume) in cubic meters
    public static func computeVolumeWithCentroid(vertices: [SIMD3<Float>],
                                                 triangles: [UInt32]) -> (signedVolume: Float, absoluteVolume: Float) {

        guard !vertices.isEmpty else { return (0, 0) }

        // Calculate centroid
        var centroid = SIMD3<Float>(0, 0, 0)
        for vertex in vertices {
            centroid += vertex
        }
        centroid /= Float(vertices.count)

        // Compute volume using centroid as origin
        return computeVolume(vertices: vertices, triangles: triangles, origin: centroid)
    }

    /// Convert volume from cubic meters to milliliters
    /// - Parameter volumeM3: Volume in cubic meters
    /// - Returns: Volume in milliliters (1 m³ = 1,000,000 mL)
    public static func cubicMetersToMilliliters(_ volumeM3: Float) -> Float {
        return volumeM3 * 1_000_000.0
    }

    /// Convert volume from cubic meters to liters
    /// - Parameter volumeM3: Volume in cubic meters
    /// - Returns: Volume in liters (1 m³ = 1,000 L)
    public static func cubicMetersToLiters(_ volumeM3: Float) -> Float {
        return volumeM3 * 1_000.0
    }

    /// Convert volume from cubic meters to cubic centimeters
    /// - Parameter volumeM3: Volume in cubic meters
    /// - Returns: Volume in cubic centimeters (1 m³ = 1,000,000 cm³)
    public static func cubicMetersToCubicCentimeters(_ volumeM3: Float) -> Float {
        return volumeM3 * 1_000_000.0
    }

    /// Validate mesh topology for volume computation
    /// Checks for common issues that might affect volume accuracy
    ///
    /// - Parameters:
    ///   - vertices: Vertex array
    ///   - triangles: Triangle index array
    /// - Returns: Array of validation warnings (empty if valid)
    public static func validateMeshTopology(vertices: [SIMD3<Float>],
                                           triangles: [UInt32]) -> [String] {
        var warnings: [String] = []

        // Check triangle count
        if triangles.count % 3 != 0 {
            warnings.append("Triangle array length is not a multiple of 3")
        }

        // Check for empty data
        if vertices.isEmpty {
            warnings.append("Vertex array is empty")
        }

        if triangles.isEmpty {
            warnings.append("Triangle array is empty")
        }

        // Check for out-of-bounds indices
        let maxIndex = UInt32(vertices.count)
        for (i, idx) in triangles.enumerated() {
            if idx >= maxIndex {
                warnings.append("Triangle index \(idx) at position \(i) exceeds vertex count \(vertices.count)")
                break // Only report first occurrence
            }
        }

        // Check for degenerate triangles (all three vertices at same position)
        let triCount = triangles.count / 3
        var degenerateCount = 0

        for i in 0..<min(triCount, 100) { // Sample first 100 triangles
            let aIdx = Int(triangles[i * 3 + 0])
            let bIdx = Int(triangles[i * 3 + 1])
            let cIdx = Int(triangles[i * 3 + 2])

            if aIdx < vertices.count && bIdx < vertices.count && cIdx < vertices.count {
                let a = vertices[aIdx]
                let b = vertices[bIdx]
                let c = vertices[cIdx]

                let ab = length(b - a)
                let bc = length(c - b)
                let ca = length(a - c)

                // Check if all edges are essentially zero-length
                if ab < 1e-6 && bc < 1e-6 && ca < 1e-6 {
                    degenerateCount += 1
                }
            }
        }

        if degenerateCount > 0 {
            warnings.append("Found \(degenerateCount) degenerate triangles in first 100 sampled")
        }

        // Check for NaN or Inf vertices
        var invalidVertexCount = 0
        for vertex in vertices.prefix(1000) { // Sample first 1000 vertices
            if vertex.x.isNaN || vertex.x.isInfinite ||
               vertex.y.isNaN || vertex.y.isInfinite ||
               vertex.z.isNaN || vertex.z.isInfinite {
                invalidVertexCount += 1
            }
        }

        if invalidVertexCount > 0 {
            warnings.append("Found \(invalidVertexCount) vertices with NaN/Inf values in first 1000 sampled")
        }

        return warnings
    }

    /// Compute surface area of mesh (useful for validation and density estimation)
    /// - Parameters:
    ///   - vertices: Vertex positions
    ///   - triangles: Triangle indices
    /// - Returns: Total surface area in square meters
    public static func computeSurfaceArea(vertices: [SIMD3<Float>],
                                         triangles: [UInt32]) -> Float {

        guard triangles.count % 3 == 0 else { return 0 }

        var totalArea: Float = 0.0
        let triCount = triangles.count / 3

        for i in 0..<triCount {
            let aIdx = Int(triangles[i * 3 + 0])
            let bIdx = Int(triangles[i * 3 + 1])
            let cIdx = Int(triangles[i * 3 + 2])

            guard aIdx < vertices.count && bIdx < vertices.count && cIdx < vertices.count else {
                continue
            }

            let a = vertices[aIdx]
            let b = vertices[bIdx]
            let c = vertices[cIdx]

            // Triangle area = 0.5 * ||cross(b-a, c-a)||
            let ab = b - a
            let ac = c - a
            let crossProduct = cross(ab, ac)
            let area = 0.5 * length(crossProduct)

            totalArea += area
        }

        return totalArea
    }

    /// Calculate bounding box volume (useful for quick sanity checks)
    /// The mesh volume should be less than or equal to the bounding box volume
    ///
    /// - Parameter vertices: Vertex positions
    /// - Returns: Bounding box volume in cubic meters
    public static func computeBoundingBoxVolume(vertices: [SIMD3<Float>]) -> Float {
        guard !vertices.isEmpty else { return 0 }

        var minP = vertices[0]
        var maxP = vertices[0]

        for vertex in vertices {
            minP = min(minP, vertex)
            maxP = max(maxP, vertex)
        }

        let dimensions = maxP - minP
        return dimensions.x * dimensions.y * dimensions.z
    }
}
