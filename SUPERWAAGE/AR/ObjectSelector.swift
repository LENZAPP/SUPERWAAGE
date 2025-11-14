//
//  ObjectSelector.swift
//  SUPERWAAGE
//
//  Tap-to-Select Object Selection with automatic segmentation
//  Based on target architecture specification
//

import Foundation
import ARKit
import RealityKit
import simd

// MARK: - Object Selection Result

struct SelectedObject {
    let meshAnchor: ARMeshAnchor
    let points: [SIMD3<Float>]
    let normals: [SIMD3<Float>]
    let boundingBox: BoundingBox
    let center: SIMD3<Float>
    let confidence: Float
}

// MARK: - Object Selector

class ObjectSelector {

    // MARK: - Configuration

    private let clusterRadius: Float = 0.3  // 30cm clustering radius
    private let minPointsForObject: Int = 100
    private let maxSegmentationDistance: Float = 0.05  // 5cm

    // MARK: - Public Methods

    /// Select object at tap location using raycast + segmentation
    func selectObject(
        at screenPoint: CGPoint,
        in arView: ARView,
        meshAnchors: [ARMeshAnchor]
    ) -> SelectedObject? {

        print("🎯 ObjectSelector: Selecting object at tap location...")

        // 1. Raycast to find 3D hit point
        guard let hitPoint = performRaycast(at: screenPoint, in: arView) else {
            print("   ❌ No raycast hit found")
            return nil
        }

        print("   ✓ Raycast hit at: \(hitPoint)")

        // 2. Find closest mesh anchor
        guard let closestAnchor = findClosestMeshAnchor(
            to: hitPoint,
            anchors: meshAnchors
        ) else {
            print("   ❌ No mesh anchor found near hit point")
            return nil
        }

        print("   ✓ Found mesh anchor")

        // 3. Segment object from anchor
        guard let segmentedObject = segmentObject(
            from: closestAnchor,
            around: hitPoint
        ) else {
            print("   ❌ Object segmentation failed")
            return nil
        }

        print("   ✅ Object selected: \(segmentedObject.points.count) points")

        return segmentedObject
    }

    // MARK: - Raycast

    private func performRaycast(
        at screenPoint: CGPoint,
        in arView: ARView
    ) -> SIMD3<Float>? {

        // Perform raycast to find world position
        let results = arView.raycast(
            from: screenPoint,
            allowing: .estimatedPlane,
            alignment: .any
        )

        if let firstResult = results.first {
            let position = firstResult.worldTransform.columns.3
            return SIMD3<Float>(position.x, position.y, position.z)
        }

        // Fallback: try raycast with existing plane
        let planeResults = arView.raycast(
            from: screenPoint,
            allowing: .existingPlaneGeometry,
            alignment: .any
        )

        if let firstResult = planeResults.first {
            let position = firstResult.worldTransform.columns.3
            return SIMD3<Float>(position.x, position.y, position.z)
        }

        return nil
    }

    // MARK: - Mesh Anchor Selection

    private func findClosestMeshAnchor(
        to point: SIMD3<Float>,
        anchors: [ARMeshAnchor]
    ) -> ARMeshAnchor? {

        var closestAnchor: ARMeshAnchor?
        var minDistance: Float = .infinity

        for anchor in anchors {
            let anchorPosition = SIMD3<Float>(
                anchor.transform.columns.3.x,
                anchor.transform.columns.3.y,
                anchor.transform.columns.3.z
            )

            let distance = simd_distance(point, anchorPosition)

            if distance < minDistance {
                minDistance = distance
                closestAnchor = anchor
            }
        }

        // Only return if within reasonable distance (2 meters)
        return minDistance < 2.0 ? closestAnchor : nil
    }

    // MARK: - Object Segmentation

    private func segmentObject(
        from anchor: ARMeshAnchor,
        around tapPoint: SIMD3<Float>
    ) -> SelectedObject? {

        let geometry = anchor.geometry
        let transform = anchor.transform

        // Extract all points from mesh
        var allPoints: [SIMD3<Float>] = []
        var allNormals: [SIMD3<Float>] = []

        let vertexBuffer = geometry.vertices.buffer.contents()
        let vertexStride = geometry.vertices.stride
        let vertexOffset = geometry.vertices.offset
        let normalBuffer = geometry.normals.buffer.contents()
        let normalStride = geometry.normals.stride
        let normalOffset = geometry.normals.offset

        for i in 0..<geometry.vertices.count {
            // ✅ CRITICAL: Include initial offset
            let vertexPointer = vertexBuffer.advanced(by: vertexOffset + (i * vertexStride))
            let localVertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee

            // Validate vertex data
            guard localVertex.x.isFinite && localVertex.y.isFinite && localVertex.z.isFinite else {
                continue
            }

            // Transform to world space
            let worldVertex = transform * SIMD4<Float>(localVertex.x, localVertex.y, localVertex.z, 1.0)
            let worldPoint = SIMD3<Float>(worldVertex.x, worldVertex.y, worldVertex.z)

            // ✅ CRITICAL: Include initial offset
            let normalPointer = normalBuffer.advanced(by: normalOffset + (i * normalStride))
            let localNormal = normalPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
            let worldNormal = transform * SIMD4<Float>(localNormal.x, localNormal.y, localNormal.z, 0.0)
            let normalizedNormal = simd_normalize(SIMD3<Float>(worldNormal.x, worldNormal.y, worldNormal.z))

            allPoints.append(worldPoint)
            allNormals.append(normalizedNormal)
        }

        // Cluster points around tap point
        let clusteredPoints = clusterPointsAroundTap(
            points: allPoints,
            normals: allNormals,
            tapPoint: tapPoint,
            radius: clusterRadius
        )

        guard clusteredPoints.points.count >= minPointsForObject else {
            return nil
        }

        // Calculate bounding box
        guard let bbox = BoundingBox.from(points: clusteredPoints.points) else {
            return nil
        }

        // Calculate center
        let center = clusteredPoints.points.reduce(SIMD3<Float>.zero, +) / Float(clusteredPoints.points.count)

        // Calculate confidence based on point density
        let volume = bbox.size.x * bbox.size.y * bbox.size.z
        let density = Float(clusteredPoints.points.count) / volume
        let confidence = min(density / 1000.0, 1.0)  // Normalize

        return SelectedObject(
            meshAnchor: anchor,
            points: clusteredPoints.points,
            normals: clusteredPoints.normals,
            boundingBox: bbox,
            center: center,
            confidence: confidence
        )
    }

    // MARK: - Point Clustering

    private func clusterPointsAroundTap(
        points: [SIMD3<Float>],
        normals: [SIMD3<Float>],
        tapPoint: SIMD3<Float>,
        radius: Float
    ) -> (points: [SIMD3<Float>], normals: [SIMD3<Float>]) {

        var clusteredPoints: [SIMD3<Float>] = []
        var clusteredNormals: [SIMD3<Float>] = []
        var visited = Set<Int>()
        var queue: [Int] = []

        // Find seed point (closest to tap)
        var seedIndex = 0
        var minDist: Float = .infinity

        for (index, point) in points.enumerated() {
            let dist = simd_distance(point, tapPoint)
            if dist < minDist {
                minDist = dist
                seedIndex = index
            }
        }

        // Breadth-first search clustering
        queue.append(seedIndex)
        visited.insert(seedIndex)

        while !queue.isEmpty && clusteredPoints.count < 10_000 {
            let currentIndex = queue.removeFirst()
            let currentPoint = points[currentIndex]

            clusteredPoints.append(currentPoint)
            clusteredNormals.append(normals[currentIndex])

            // Find neighbors within segmentation distance
            for (index, point) in points.enumerated() {
                if !visited.contains(index) {
                    let distance = simd_distance(currentPoint, point)

                    if distance < maxSegmentationDistance {
                        queue.append(index)
                        visited.insert(index)
                    }
                }
            }
        }

        return (clusteredPoints, clusteredNormals)
    }
}
