//
//  MeshSmoothing.swift
//  SUPERWAAGE
//
//  Advanced mesh smoothing algorithms for realistic 3D models
//  Based on Laplacian smoothing and bilateral filtering
//

import Foundation
import ARKit
import simd
import Accelerate

// MARK: - Mesh Smoothing Engine

class MeshSmoothingEngine {

    // MARK: - Configuration

    struct SmoothingConfiguration {
        /// Number of smoothing iterations (more = smoother, but may lose detail)
        var iterations: Int = 3

        /// Smoothing strength (0.0 - 1.0)
        /// 0.1 = subtle smoothing, 0.5 = moderate, 0.9 = aggressive
        var lambda: Float = 0.5

        /// Preserve sharp features (true = preserve edges)
        var preserveFeatures: Bool = true

        /// Feature detection threshold (angle in degrees)
        var featureAngleThreshold: Float = 30.0

        static let gentle = SmoothingConfiguration(iterations: 2, lambda: 0.3, preserveFeatures: true)
        static let moderate = SmoothingConfiguration(iterations: 3, lambda: 0.5, preserveFeatures: true)
        static let aggressive = SmoothingConfiguration(iterations: 5, lambda: 0.7, preserveFeatures: false)
    }

    // MARK: - Laplacian Smoothing

    /// Apply Laplacian smoothing to mesh vertices
    /// ✅ OPTIMIZED: Preserves mesh topology while smoothing surfaces
    /// - Parameters:
    ///   - vertices: Array of vertex positions
    ///   - faces: Array of triangle face indices
    ///   - config: Smoothing configuration
    /// - Returns: Smoothed vertices
    static func laplacianSmoothing(
        vertices: [SIMD3<Float>],
        faces: [(UInt32, UInt32, UInt32)],
        config: SmoothingConfiguration = .moderate
    ) -> [SIMD3<Float>] {

        guard vertices.count > 0 && faces.count > 0 else { return vertices }

        var smoothedVertices = vertices

        // Build adjacency graph (which vertices are connected)
        let adjacency = buildAdjacencyGraph(vertexCount: vertices.count, faces: faces)

        // Detect sharp features if preservation is enabled
        var featureEdges: Set<Edge> = []
        if config.preserveFeatures {
            featureEdges = detectFeatureEdges(
                vertices: vertices,
                faces: faces,
                adjacency: adjacency,
                angleThreshold: config.featureAngleThreshold
            )
        }

        // Iterative smoothing
        for _ in 0..<config.iterations {
            var newVertices = smoothedVertices

            for i in 0..<smoothedVertices.count {
                let neighbors = adjacency[i]
                guard !neighbors.isEmpty else { continue }

                // Calculate Laplacian (average of neighbor positions)
                var laplacian = SIMD3<Float>.zero
                var validNeighborCount: Float = 0

                for neighborIdx in neighbors {
                    // Skip smoothing across feature edges
                    if config.preserveFeatures {
                        let edge = Edge(min(i, neighborIdx), max(i, neighborIdx))
                        if featureEdges.contains(edge) {
                            continue
                        }
                    }

                    laplacian += smoothedVertices[neighborIdx]
                    validNeighborCount += 1
                }

                if validNeighborCount > 0 {
                    laplacian /= validNeighborCount

                    // Apply weighted update
                    newVertices[i] = smoothedVertices[i] + config.lambda * (laplacian - smoothedVertices[i])
                }
            }

            smoothedVertices = newVertices
        }

        return smoothedVertices
    }

    // MARK: - Bilateral Smoothing (Feature-Preserving)

    /// Apply bilateral smoothing to preserve edges while smoothing surfaces
    /// ✅ ADVANCED: Better than simple Laplacian for preserving object details
    static func bilateralSmoothing(
        vertices: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        faces: [(UInt32, UInt32, UInt32)],
        iterations: Int = 2,
        spatialSigma: Float = 0.05,
        normalSigma: Float = 0.3
    ) -> [SIMD3<Float>] {

        var smoothedVertices = vertices
        let adjacency = buildAdjacencyGraph(vertexCount: vertices.count, faces: faces)

        for _ in 0..<iterations {
            var newVertices = smoothedVertices

            for i in 0..<smoothedVertices.count {
                let neighbors = adjacency[i]
                guard !neighbors.isEmpty else { continue }

                let currentVertex = smoothedVertices[i]
                let currentNormal = normals[i]

                var weightedSum = SIMD3<Float>.zero
                var totalWeight: Float = 0

                for neighborIdx in neighbors {
                    let neighborVertex = smoothedVertices[neighborIdx]
                    let neighborNormal = normals[neighborIdx]

                    // Spatial distance weight
                    let spatialDist = simd_distance(currentVertex, neighborVertex)
                    let spatialWeight = exp(-(spatialDist * spatialDist) / (2 * spatialSigma * spatialSigma))

                    // Normal similarity weight (preserve features)
                    let normalDot = simd_dot(currentNormal, neighborNormal)
                    let normalWeight = exp(-(1 - normalDot) / (2 * normalSigma * normalSigma))

                    let weight = spatialWeight * normalWeight
                    weightedSum += neighborVertex * weight
                    totalWeight += weight
                }

                if totalWeight > 0 {
                    newVertices[i] = weightedSum / totalWeight
                }
            }

            smoothedVertices = newVertices
        }

        return smoothedVertices
    }

    // MARK: - Helpers

    private static func buildAdjacencyGraph(
        vertexCount: Int,
        faces: [(UInt32, UInt32, UInt32)]
    ) -> [[Int]] {
        var adjacency = Array(repeating: Set<Int>(), count: vertexCount)

        for face in faces {
            let (i0, i1, i2) = (Int(face.0), Int(face.1), Int(face.2))

            // Add bidirectional edges
            adjacency[i0].insert(i1)
            adjacency[i0].insert(i2)
            adjacency[i1].insert(i0)
            adjacency[i1].insert(i2)
            adjacency[i2].insert(i0)
            adjacency[i2].insert(i1)
        }

        return adjacency.map { Array($0) }
    }

    private static func detectFeatureEdges(
        vertices: [SIMD3<Float>],
        faces: [(UInt32, UInt32, UInt32)],
        adjacency: [[Int]],
        angleThreshold: Float
    ) -> Set<Edge> {
        var featureEdges: Set<Edge> = []
        let thresholdCos = cos(angleThreshold * .pi / 180)

        // Calculate face normals
        var faceNormals: [SIMD3<Float>] = []
        for face in faces {
            let v0 = vertices[Int(face.0)]
            let v1 = vertices[Int(face.1)]
            let v2 = vertices[Int(face.2)]

            let edge1 = v1 - v0
            let edge2 = v2 - v0
            let normal = simd_normalize(simd_cross(edge1, edge2))
            faceNormals.append(normal)
        }

        // Detect sharp edges based on dihedral angle
        for (faceIdx, face) in faces.enumerated() {
            let edges = [
                (Int(face.0), Int(face.1)),
                (Int(face.1), Int(face.2)),
                (Int(face.2), Int(face.0))
            ]

            for (v0, v1) in edges {
                // Find adjacent faces that share this edge
                for (otherFaceIdx, otherFace) in faces.enumerated() {
                    guard faceIdx != otherFaceIdx else { continue }

                    let otherIndices = [Int(otherFace.0), Int(otherFace.1), Int(otherFace.2)]
                    if otherIndices.contains(v0) && otherIndices.contains(v1) {
                        // Calculate dihedral angle
                        let normalDot = simd_dot(faceNormals[faceIdx], faceNormals[otherFaceIdx])

                        // If angle is sharp, mark as feature edge
                        if normalDot < thresholdCos {
                            featureEdges.insert(Edge(min(v0, v1), max(v0, v1)))
                        }
                    }
                }
            }
        }

        return featureEdges
    }

    // MARK: - Edge Helper

    private struct Edge: Hashable {
        let v0: Int
        let v1: Int

        init(_ v0: Int, _ v1: Int) {
            self.v0 = v0
            self.v1 = v1
        }
    }
}

// MARK: - ARMeshAnchor Extension

extension ARMeshAnchor {

    /// Apply smoothing to this mesh anchor
    /// ✅ OPTIMIZED: Smooths the mesh while preserving topology
    func smoothed(config: MeshSmoothingEngine.SmoothingConfiguration = .moderate) -> [SIMD3<Float>]? {
        let geometry = self.geometry

        // Extract vertices
        var vertices: [SIMD3<Float>] = []
        for i in 0..<geometry.vertices.count {
            let offset = geometry.vertices.offset + (geometry.vertices.stride * i)
            guard offset + MemoryLayout<SIMD3<Float>>.stride <= geometry.vertices.buffer.length else {
                continue
            }

            let vertexPointer = geometry.vertices.buffer.contents().advanced(by: offset)
            let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee

            guard vertex.x.isFinite && vertex.y.isFinite && vertex.z.isFinite else {
                continue
            }

            vertices.append(vertex)
        }

        // Extract faces
        var faces: [(UInt32, UInt32, UInt32)] = []
        for i in 0..<geometry.faces.count {
            let faceOffset = geometry.faces.offset + (i * geometry.faces.indexCountPerPrimitive * MemoryLayout<UInt32>.stride)

            guard faceOffset + (3 * MemoryLayout<UInt32>.stride) <= geometry.faces.buffer.length else {
                continue
            }

            let facePointer = geometry.faces.buffer.contents().advanced(by: faceOffset).assumingMemoryBound(to: UInt32.self)

            let idx0 = facePointer[0]
            let idx1 = facePointer[1]
            let idx2 = facePointer[2]

            guard idx0 < vertices.count && idx1 < vertices.count && idx2 < vertices.count else {
                continue
            }

            faces.append((idx0, idx1, idx2))
        }

        // Apply smoothing
        return MeshSmoothingEngine.laplacianSmoothing(
            vertices: vertices,
            faces: faces,
            config: config
        )
    }
}
