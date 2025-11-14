//
//  ARCoinOverlay.swift
//  SUPERWAAGE
//
//  Virtual 1 Euro coin overlay for AR calibration
//  Accurate dimensions: Ø 23.25mm, thickness 2.20mm
//

import Foundation
import RealityKit
import ARKit
import simd

/// Creates a virtual 1 Euro coin overlay in AR
class ARCoinOverlay {

    // 1 Euro coin specifications (in meters)
    private static let coinDiameter: Float = 0.02325  // 23.25mm
    private static let coinThickness: Float = 0.0022   // 2.20mm
    private static let coinRadius: Float = coinDiameter / 2.0

    private var coinAnchor: AnchorEntity?
    private var coinEntity: ModelEntity?

    /// Create a virtual coin overlay with realistic appearance
    /// - Returns: Entity that can be added to AR scene
    func createCoinEntity() -> ModelEntity {
        // Create cylinder mesh for coin
        let mesh = MeshResource.generateCylinder(
            height: Self.coinThickness,
            radius: Self.coinRadius
        )

        // Create realistic coin material (gold color with metallic finish)
        var material = PhysicallyBasedMaterial()
        material.baseColor = PhysicallyBasedMaterial.BaseColor(
            tint: UIColor(red: 0.85, green: 0.65, blue: 0.13, alpha: 1.0)  // Gold
        )
        material.metallic = PhysicallyBasedMaterial.Metallic(floatLiteral: 0.9)
        material.roughness = PhysicallyBasedMaterial.Roughness(floatLiteral: 0.3)

        // Create entity
        let entity = ModelEntity(mesh: mesh, materials: [material])

        // Add semi-transparent outline for better visibility
        let outlineMesh = MeshResource.generateCylinder(
            height: Self.coinThickness + 0.001,  // Slightly taller
            radius: Self.coinRadius + 0.001       // Slightly wider
        )

        var outlineMaterial = SimpleMaterial()
        outlineMaterial.color = .init(tint: .yellow.withAlphaComponent(0.5), texture: nil)

        let outlineEntity = ModelEntity(mesh: outlineMesh, materials: [outlineMaterial])
        entity.addChild(outlineEntity)

        self.coinEntity = entity
        return entity
    }

    /// Place coin in AR scene at given position
    /// - Parameters:
    ///   - arView: AR view to add coin to
    ///   - position: World position (meters)
    ///   - rotation: Optional rotation quaternion
    func placeCoin(in arView: ARView, at position: SIMD3<Float>, rotation: simd_quatf? = nil) {
        // Remove existing anchor if any
        if let existingAnchor = coinAnchor {
            arView.scene.removeAnchor(existingAnchor)
        }

        // Create anchor at position
        let anchor = AnchorEntity(world: position)

        // Create or reuse coin entity
        let coin = coinEntity ?? createCoinEntity()

        // Apply rotation if provided (default: flat on surface)
        if let rot = rotation {
            coin.orientation = rot
        } else {
            // Flat orientation (lying on table)
            coin.orientation = simd_quatf(angle: .pi / 2, axis: SIMD3(1, 0, 0))
        }

        anchor.addChild(coin)
        arView.scene.addAnchor(anchor)

        self.coinAnchor = anchor
    }

    /// Update coin position (for drag & drop)
    /// - Parameter newPosition: New world position
    func updatePosition(_ newPosition: SIMD3<Float>) {
        coinAnchor?.position = newPosition
    }

    /// Update coin to show alignment status
    /// - Parameter isAligned: True if coin is correctly aligned with real coin
    func updateAlignmentFeedback(isAligned: Bool) {
        guard let entity = coinEntity else { return }

        // Change outline color based on alignment
        if let outline = entity.children.first as? ModelEntity {
            var material = SimpleMaterial()

            if isAligned {
                // Green = good alignment
                material.color = .init(tint: .green.withAlphaComponent(0.6), texture: nil)
            } else {
                // Yellow = needs adjustment
                material.color = .init(tint: .yellow.withAlphaComponent(0.5), texture: nil)
            }

            outline.model?.materials = [material]
        }
    }

    /// Remove coin from AR scene
    /// - Parameter arView: AR view to remove from
    func removeCoin(from arView: ARView) {
        if let anchor = coinAnchor {
            arView.scene.removeAnchor(anchor)
            coinAnchor = nil
        }
    }

    /// Check if a 3D point is within the coin's volume (for alignment detection)
    /// - Parameters:
    ///   - point: World space point to check
    ///   - coinPosition: Position of virtual coin
    /// - Returns: True if point is inside coin volume
    func isPointInCoin(point: SIMD3<Float>, coinPosition: SIMD3<Float>) -> Bool {
        let offset = point - coinPosition

        // Check if within cylinder
        let horizontalDistance = sqrt(offset.x * offset.x + offset.z * offset.z)
        let isWithinRadius = horizontalDistance <= Self.coinRadius
        let isWithinHeight = abs(offset.y) <= (Self.coinThickness / 2.0)

        return isWithinRadius && isWithinHeight
    }

    /// Get coin dimensions for reference
    static func getCoinDimensions() -> (diameter: Float, thickness: Float, volume: Float) {
        let volume = Float.pi * coinRadius * coinRadius * coinThickness  // V = πr²h
        return (coinDiameter, coinThickness, volume * 1_000_000)  // Convert m³ to ml
    }
}
