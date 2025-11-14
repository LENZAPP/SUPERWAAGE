//
//  MeshVolumeCalculator.swift
//  SUPERWAAGE
//
//  Precise volume calculation from 3D mesh using Tetrahedra method
//  Based on signed volume approach
//

import Foundation
import ARKit
import simd

// MARK: - Volume Calculation Result
struct MeshVolumeResult {
    let volume_m3: Double
    let volume_cm3: Double
    let surfaceArea_m2: Double
    let method: CalculationMethod
    let quality: MeshQuality
    let triangleCount: Int
    let isClosed: Bool

    enum CalculationMethod {
        case signedTetrahedra  // Most accurate for closed meshes
        case surfaceIntegration // Good for open meshes
        case convexHull        // Fallback for incomplete data
    }

    struct MeshQuality {
        let isWatertight: Bool
        let hasNormals: Bool
        let triangleDensity: Double  // Triangles per m²
        let qualityScore: Double     // 0-1

        var description: String {
            switch qualityScore {
            case 0.9...1.0: return "Exzellent"
            case 0.7..<0.9: return "Sehr gut"
            case 0.5..<0.7: return "Gut"
            case 0.3..<0.5: return "Befriedigend"
            default: return "Ungenügend"
            }
        }
    }

    var formattedVolume: String {
        if volume_cm3 < 10 {
            return String(format: "%.2f cm³", volume_cm3)
        } else if volume_cm3 < 1000 {
            return String(format: "%.1f cm³", volume_cm3)
        } else {
            return String(format: "%.2f L (%.0f cm³)", volume_cm3 / 1000, volume_cm3)
        }
    }
}

// MARK: - Mesh Volume Calculator
class MeshVolumeCalculator {

    // MARK: - Main Calculation

    /// Calculate volume from mesh anchors with high precision
    nonisolated static func calculateVolume(from meshAnchors: [ARMeshAnchor]) -> MeshVolumeResult? {
        guard !meshAnchors.isEmpty else { return nil }

        // Extract all triangles from all mesh anchors
        let allTriangles = extractTriangles(from: meshAnchors)
        guard !allTriangles.isEmpty else { return nil }

        // Analyze mesh quality
        let quality = analyzeMeshQuality(triangles: allTriangles, meshAnchors: meshAnchors)

        // Choose best calculation method based on quality
        let method: MeshVolumeResult.CalculationMethod
        let volume_m3: Double

        if quality.isWatertight {
            // Best method: Signed Tetrahedra
            method = .signedTetrahedra
            volume_m3 = calculateSignedTetrahedraVolume(triangles: allTriangles)
        } else if quality.qualityScore > 0.5 {
            // Good method: Surface Integration
            method = .surfaceIntegration
            volume_m3 = calculateSurfaceIntegrationVolume(triangles: allTriangles)
        } else {
            // Fallback: Convex Hull
            method = .convexHull
            volume_m3 = calculateConvexHullVolume(triangles: allTriangles)
        }

        // Calculate surface area
        let surfaceArea = calculateSurfaceArea(triangles: allTriangles)

        return MeshVolumeResult(
            volume_m3: volume_m3,
            volume_cm3: volume_m3 * 1_000_000,
            surfaceArea_m2: surfaceArea,
            method: method,
            quality: quality,
            triangleCount: allTriangles.count,
            isClosed: quality.isWatertight
        )
    }

    // MARK: - Signed Tetrahedra Method (Most Accurate)

    /// Calculate volume using signed tetrahedra decomposition
    /// For each triangle, form a tetrahedron with the origin
    /// V = (1/6) * Σ dot(a, cross(b, c))
    nonisolated private static func calculateSignedTetrahedraVolume(triangles: [Triangle]) -> Double {
        var totalVolume: Double = 0.0

        for triangle in triangles {
            let a = triangle.v0
            let b = triangle.v1
            let c = triangle.v2

            // Signed volume of tetrahedron (origin, a, b, c)
            let signedVolume = dot(a, cross(b, c)) / 6.0
            totalVolume += Double(signedVolume)
        }

        // Return absolute value (orientation determines sign)
        return abs(totalVolume)
    }

    // MARK: - Surface Integration Method

    /// Calculate volume using surface integration
    /// Integrates z-component over projected area
    nonisolated private static func calculateSurfaceIntegrationVolume(triangles: [Triangle]) -> Double {
        var volume: Double = 0.0

        for triangle in triangles {
            // Project triangle onto XY plane
            let a = triangle.v0
            let b = triangle.v1
            let c = triangle.v2

            // Average height
            let avgZ = (a.z + b.z + c.z) / 3.0

            // Area of projected triangle on XY plane
            let projectedArea = abs(
                (b.x - a.x) * (c.y - a.y) - (c.x - a.x) * (b.y - a.y)
            ) / 2.0

            volume += Double(projectedArea * avgZ)
        }

        return abs(volume)
    }

    // MARK: - Convex Hull Method (Fallback)

    /// Approximate volume using convex hull
    nonisolated private static func calculateConvexHullVolume(triangles: [Triangle]) -> Double {
        // Extract all unique vertices
        var vertices = Set<SIMD3<Float>>()
        for triangle in triangles {
            vertices.insert(triangle.v0)
            vertices.insert(triangle.v1)
            vertices.insert(triangle.v2)
        }

        let points = Array(vertices)
        guard points.count >= 4 else { return 0 }

        // Simple convex hull approximation
        // Find bounding box and apply reduction factor
        let boundingBox = calculateBoundingBox(points: points)
        let boxVolume = boundingBox.width * boundingBox.height * boundingBox.depth

        // Convex hull is typically 60-80% of bounding box for irregular objects
        let convexHullFactor: Double = 0.7

        return Double(boxVolume) * convexHullFactor
    }

    // MARK: - Surface Area Calculation

    /// Calculate total surface area of mesh
    nonisolated private static func calculateSurfaceArea(triangles: [Triangle]) -> Double {
        var totalArea: Double = 0.0

        for triangle in triangles {
            // Calculate area inline to avoid actor isolation
            let edge1 = triangle.v1 - triangle.v0
            let edge2 = triangle.v2 - triangle.v0
            let crossProduct = cross(edge1, edge2)
            let area = length(crossProduct) / 2.0
            totalArea += Double(area)
        }

        return totalArea
    }

    // MARK: - Mesh Quality Analysis

    /// Analyze mesh quality to determine best calculation method
    nonisolated private static func analyzeMeshQuality(triangles: [Triangle], meshAnchors: [ARMeshAnchor]) -> MeshVolumeResult.MeshQuality {

        // Check if mesh is watertight (closed)
        let isWatertight = checkIfWatertight(triangles: triangles)

        // Check if mesh has normals
        let hasNormals = meshAnchors.first?.geometry.normals.count ?? 0 > 0

        // Calculate triangle density
        let surfaceArea = calculateSurfaceArea(triangles: triangles)
        let triangleDensity = Double(triangles.count) / max(surfaceArea, 0.0001)

        // Calculate overall quality score
        var qualityScore: Double = 0.0

        // Factor 1: Watertightness (40%)
        qualityScore += isWatertight ? 0.4 : 0.0

        // Factor 2: Has normals (20%)
        qualityScore += hasNormals ? 0.2 : 0.0

        // Factor 3: Triangle density (20%)
        let densityScore = min(triangleDensity / 1000.0, 1.0)
        qualityScore += densityScore * 0.2

        // Factor 4: Triangle count (20%)
        let triangleScore = min(Double(triangles.count) / 5000.0, 1.0)
        qualityScore += triangleScore * 0.2

        return MeshVolumeResult.MeshQuality(
            isWatertight: isWatertight,
            hasNormals: hasNormals,
            triangleDensity: triangleDensity,
            qualityScore: qualityScore
        )
    }

    /// Check if mesh is watertight (all edges shared by exactly 2 triangles)
    nonisolated private static func checkIfWatertight(triangles: [Triangle]) -> Bool {
        // Edge representation
        struct Edge: Hashable {
            let v0: SIMD3<Float>
            let v1: SIMD3<Float>

            init(_ a: SIMD3<Float>, _ b: SIMD3<Float>) {
                // Normalize edge direction
                if a.x < b.x || (a.x == b.x && a.y < b.y) || (a.x == b.x && a.y == b.y && a.z < b.z) {
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

        // Mesh is watertight if all edges are shared by exactly 2 triangles
        let openEdges = edgeCounts.values.filter { $0 != 2 }.count
        return openEdges < triangles.count / 10 // Allow small imperfections
    }

    // MARK: - Helper Methods

    /// Extract all triangles from mesh anchors
    nonisolated private static func extractTriangles(from meshAnchors: [ARMeshAnchor]) -> [Triangle] {
        var triangles: [Triangle] = []

        for anchor in meshAnchors {
            let geometry = anchor.geometry
            let transform = anchor.transform

            // Get vertices
            let vertexCount = geometry.vertices.count
            var vertices: [SIMD3<Float>] = []

            // Extract vertices directly from buffer (avoid actor-isolated method)
            let verticesBuffer = geometry.vertices.buffer.contents()
            let verticesStride = geometry.vertices.stride

            for i in 0..<vertexCount {
                let vertexPointer = verticesBuffer.advanced(by: i * verticesStride)
                let localVertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee

                // Transform to world space
                let worldVertex = transform * SIMD4<Float>(localVertex.x, localVertex.y, localVertex.z, 1.0)
                vertices.append(SIMD3<Float>(worldVertex.x, worldVertex.y, worldVertex.z))
            }

            // Get faces (triangles)
            let faceCount = geometry.faces.count
            let facesPointer = geometry.faces.buffer.contents()

            for faceIndex in 0..<faceCount {
                let offset = faceIndex * geometry.faces.indexCountPerPrimitive * geometry.faces.bytesPerIndex

                let i0 = facesPointer.advanced(by: offset).assumingMemoryBound(to: UInt32.self).pointee
                let i1 = facesPointer.advanced(by: offset + 4).assumingMemoryBound(to: UInt32.self).pointee
                let i2 = facesPointer.advanced(by: offset + 8).assumingMemoryBound(to: UInt32.self).pointee

                guard i0 < vertices.count && i1 < vertices.count && i2 < vertices.count else { continue }

                let triangle = Triangle(
                    v0: vertices[Int(i0)],
                    v1: vertices[Int(i1)],
                    v2: vertices[Int(i2)]
                )

                triangles.append(triangle)
            }
        }

        return triangles
    }

    nonisolated private static func calculateBoundingBox(points: [SIMD3<Float>]) -> (width: Float, height: Float, depth: Float) {
        guard !points.isEmpty else { return (0, 0, 0) }

        let minX = points.map { $0.x }.min()!
        let maxX = points.map { $0.x }.max()!
        let minY = points.map { $0.y }.min()!
        let maxY = points.map { $0.y }.max()!
        let minZ = points.map { $0.z }.min()!
        let maxZ = points.map { $0.z }.max()!

        return (maxX - minX, maxY - minY, maxZ - minZ)
    }
}

// MARK: - Triangle Structure
struct Triangle {
    let v0: SIMD3<Float>
    let v1: SIMD3<Float>
    let v2: SIMD3<Float>

    /// Calculate triangle area using cross product
    var area: Float {
        let edge1 = v1 - v0
        let edge2 = v2 - v0
        let crossProduct = cross(edge1, edge2)
        return length(crossProduct) / 2.0
    }

    /// Calculate triangle normal
    var normal: SIMD3<Float> {
        let edge1 = v1 - v0
        let edge2 = v2 - v0
        return normalize(cross(edge1, edge2))
    }

    /// Triangle center
    var center: SIMD3<Float> {
        return (v0 + v1 + v2) / 3.0
    }
}

// MARK: - SIMD3 Hashable Extension
// Note: SIMD3 is already Hashable in Swift, no need for custom implementation
extension SIMD3 where Scalar == Float {
    // Custom helper methods can be added here if needed
}
