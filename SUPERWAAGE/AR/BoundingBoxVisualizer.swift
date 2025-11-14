//
//  BoundingBoxVisualizer.swift
//  SUPERWAAGE
//
//  Live AR Bounding Box visualization for selected objects
//  Shows 3D frame with measurements in real-time
//

import Foundation
import RealityKit
import ARKit
import SwiftUI

// MARK: - Bounding Box Visualizer

class BoundingBoxVisualizer {

    // MARK: - Properties

    private var boxEntity: ModelEntity?
    private var textEntities: [ModelEntity] = []
    private var anchorEntity: AnchorEntity?

    // MARK: - Configuration

    private let boxColor: UIColor = .systemBlue
    private let boxOpacity: Float = 0.3
    private let edgeThickness: Float = 0.005  // 5mm thick edges

    // MARK: - Public Methods

    /// Show bounding box in AR scene
    func showBoundingBox(
        _ boundingBox: BoundingBox,
        in arView: ARView,
        withMeasurements measurements: BoundingBoxMeasurements
    ) {
        // Remove existing visualization
        removeBoundingBox(from: arView)

        // Create box entity
        let boxEntity = createBoxEntity(for: boundingBox)
        self.boxEntity = boxEntity

        // Create anchor at bounding box center
        let center = boundingBox.center
        let anchor = AnchorEntity(world: center)
        self.anchorEntity = anchor

        // Add box to anchor
        anchor.addChild(boxEntity)

        // Add measurement labels
        let labelEntities = createMeasurementLabels(
            for: boundingBox,
            measurements: measurements
        )
        self.textEntities = labelEntities

        for label in labelEntities {
            anchor.addChild(label)
        }

        // Add to scene
        arView.scene.anchors.append(anchor)

        print("📦 BoundingBox visualized: \(measurements.volume_cm3) cm³")
    }

    /// Update bounding box with new data
    func updateBoundingBox(
        _ boundingBox: BoundingBox,
        measurements: BoundingBoxMeasurements,
        in arView: ARView
    ) {
        showBoundingBox(boundingBox, in: arView, withMeasurements: measurements)
    }

    /// Remove bounding box from scene
    func removeBoundingBox(from arView: ARView) {
        if let anchor = anchorEntity {
            arView.scene.anchors.remove(anchor)
        }

        boxEntity = nil
        textEntities.removeAll()
        anchorEntity = nil
    }

    // MARK: - Box Creation

    private func createBoxEntity(for boundingBox: BoundingBox) -> ModelEntity {
        let size = boundingBox.size

        // Create box mesh
        let mesh = MeshResource.generateBox(size: size, cornerRadius: 0.01)

        // Create material (transparent blue)
        var material = SimpleMaterial()
        material.color = .init(
            tint: boxColor.withAlphaComponent(0.3),
            texture: nil
        )
        material.roughness = .float(0.5)
        material.metallic = .float(0.0)

        // Create entity
        let boxEntity = ModelEntity(mesh: mesh, materials: [material])

        // Add wireframe edges
        let edges = createWireframeEdges(size: size)
        for edge in edges {
            boxEntity.addChild(edge)
        }

        return boxEntity
    }

    private func createWireframeEdges(size: SIMD3<Float>) -> [ModelEntity] {
        var edges: [ModelEntity] = []

        let halfSize = size / 2

        // Edge material (opaque lines)
        var edgeMaterial = SimpleMaterial()
        edgeMaterial.color = .init(tint: boxColor, texture: nil)
        edgeMaterial.metallic = .float(0.8)

        // 12 edges of the box
        let edgeDefinitions: [(start: SIMD3<Float>, end: SIMD3<Float>)] = [
            // Bottom edges
            ([-halfSize.x, -halfSize.y, -halfSize.z], [halfSize.x, -halfSize.y, -halfSize.z]),
            ([halfSize.x, -halfSize.y, -halfSize.z], [halfSize.x, -halfSize.y, halfSize.z]),
            ([halfSize.x, -halfSize.y, halfSize.z], [-halfSize.x, -halfSize.y, halfSize.z]),
            ([-halfSize.x, -halfSize.y, halfSize.z], [-halfSize.x, -halfSize.y, -halfSize.z]),
            // Top edges
            ([-halfSize.x, halfSize.y, -halfSize.z], [halfSize.x, halfSize.y, -halfSize.z]),
            ([halfSize.x, halfSize.y, -halfSize.z], [halfSize.x, halfSize.y, halfSize.z]),
            ([halfSize.x, halfSize.y, halfSize.z], [-halfSize.x, halfSize.y, halfSize.z]),
            ([-halfSize.x, halfSize.y, halfSize.z], [-halfSize.x, halfSize.y, -halfSize.z]),
            // Vertical edges
            ([-halfSize.x, -halfSize.y, -halfSize.z], [-halfSize.x, halfSize.y, -halfSize.z]),
            ([halfSize.x, -halfSize.y, -halfSize.z], [halfSize.x, halfSize.y, -halfSize.z]),
            ([halfSize.x, -halfSize.y, halfSize.z], [halfSize.x, halfSize.y, halfSize.z]),
            ([-halfSize.x, -halfSize.y, halfSize.z], [-halfSize.x, halfSize.y, halfSize.z]),
        ]

        for (start, end) in edgeDefinitions {
            let edge = createEdge(from: start, to: end, material: edgeMaterial)
            edges.append(edge)
        }

        return edges
    }

    private func createEdge(
        from start: SIMD3<Float>,
        to end: SIMD3<Float>,
        material: SimpleMaterial
    ) -> ModelEntity {
        let length = simd_distance(start, end)
        let center = (start + end) / 2

        // Create cylinder as edge
        let mesh = MeshResource.generateCylinder(
            height: length,
            radius: edgeThickness
        )

        let edge = ModelEntity(mesh: mesh, materials: [material])

        // Position at center
        edge.position = center

        // Rotate to align with edge direction
        let direction = simd_normalize(end - start)
        let up = SIMD3<Float>(0, 1, 0)

        if abs(dot(direction, up)) < 0.99 {
            let axis = cross(up, direction)
            let angle = acos(dot(up, direction))
            edge.orientation = simd_quatf(angle: angle, axis: axis)
        } else if dot(direction, up) < 0 {
            edge.orientation = simd_quatf(angle: .pi, axis: SIMD3<Float>(1, 0, 0))
        }

        return edge
    }

    // MARK: - Label Creation

    private func createMeasurementLabels(
        for boundingBox: BoundingBox,
        measurements: BoundingBoxMeasurements
    ) -> [ModelEntity] {
        var labels: [ModelEntity] = []

        let size = boundingBox.size
        let halfSize = size / 2

        // Length label (X-axis, red)
        let lengthLabel = createTextLabel(
            text: String(format: "%.1f cm", measurements.length_cm),
            position: SIMD3<Float>(0, -halfSize.y - 0.05, -halfSize.z),
            color: .systemRed
        )
        labels.append(lengthLabel)

        // Width label (Z-axis, blue)
        let widthLabel = createTextLabel(
            text: String(format: "%.1f cm", measurements.width_cm),
            position: SIMD3<Float>(halfSize.x + 0.05, -halfSize.y, 0),
            color: .systemBlue
        )
        labels.append(widthLabel)

        // Height label (Y-axis, green)
        let heightLabel = createTextLabel(
            text: String(format: "%.1f cm", measurements.height_cm),
            position: SIMD3<Float>(-halfSize.x - 0.05, 0, -halfSize.z),
            color: .systemGreen
        )
        labels.append(heightLabel)

        // Volume label (center, above)
        let volumeLabel = createTextLabel(
            text: String(format: "%.0f cm³", measurements.volume_cm3),
            position: SIMD3<Float>(0, halfSize.y + 0.1, 0),
            color: .systemPurple
        )
        labels.append(volumeLabel)

        return labels
    }

    private func createTextLabel(
        text: String,
        position: SIMD3<Float>,
        color: UIColor
    ) -> ModelEntity {
        // Create text mesh
        let mesh = MeshResource.generateText(
            text,
            extrusionDepth: 0.005,
            font: .systemFont(ofSize: 0.02, weight: .bold),
            containerFrame: .zero,
            alignment: .center,
            lineBreakMode: .byWordWrapping
        )

        // Create material
        var material = SimpleMaterial()
        material.color = .init(tint: color, texture: nil)
        material.metallic = .float(1.0)

        // Create entity
        let textEntity = ModelEntity(mesh: mesh, materials: [material])
        textEntity.position = position

        // Add billboard component (always face camera)
        textEntity.components.set(BillboardComponent())

        return textEntity
    }
}

// MARK: - Bounding Box Measurements

struct BoundingBoxMeasurements {
    let length_cm: Float
    let width_cm: Float
    let height_cm: Float
    let volume_cm3: Float

    init(boundingBox: BoundingBox) {
        let size = boundingBox.size
        self.length_cm = size.x * 100
        self.width_cm = size.z * 100
        self.height_cm = size.y * 100
        self.volume_cm3 = length_cm * width_cm * height_cm
    }
}
