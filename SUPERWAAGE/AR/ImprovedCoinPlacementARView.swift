//
//  ImprovedCoinPlacementARView.swift
//  SUPERWAAGE
//
//  Robuste AR Münz-Platzierung mit korrektem Drag & Drop
//  - Vogelperspektive empfohlen
//  - Smooth dragging ohne Springen
//  - Korrekte Touch → World Transformation
//

import SwiftUI
import RealityKit
import ARKit
import Combine

/// Verbesserte AR View für präzise Münz-Platzierung
struct ImprovedCoinPlacementARView: UIViewRepresentable {
    @Binding var coinPosition: SIMD3<Float>?
    @Binding var isPlaced: Bool
    @Binding var isAligned: Bool
    @Binding var cameraAngle: Float  // 0-90°, 0=von oben, 90=von Seite

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Configure AR session
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        arView.session.run(configuration)
        arView.session.delegate = context.coordinator

        // Add tap gesture for initial placement
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)

        // Add pan gesture for dragging
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        arView.addGestureRecognizer(panGesture)

        // Add pinch gesture for scaling (optional)
        let pinchGesture = UIPinchGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePinch(_:)))
        arView.addGestureRecognizer(pinchGesture)

        context.coordinator.arView = arView

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Update coin appearance based on alignment
        if isPlaced {
            context.coordinator.coinOverlay.updateAlignmentFeedback(isAligned: isAligned)
        }

        // Update camera angle for UI feedback
        if let frame = uiView.session.currentFrame {
            let cameraTransform = frame.camera.transform
            let cameraDirection = SIMD3<Float>(cameraTransform.columns.2.x, cameraTransform.columns.2.y, cameraTransform.columns.2.z)

            // Calculate angle from vertical (0° = straight down, 90° = horizontal)
            let angleFromVertical = acos(-cameraDirection.y) * 180.0 / .pi
            DispatchQueue.main.async {
                cameraAngle = angleFromVertical
            }
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            coinPosition: $coinPosition,
            isPlaced: $isPlaced,
            isAligned: $isAligned
        )
    }

    class Coordinator: NSObject, ARSessionDelegate {
        @Binding var coinPosition: SIMD3<Float>?
        @Binding var isPlaced: Bool
        @Binding var isAligned: Bool

        var arView: ARView?
        var coinOverlay = ARCoinOverlay()

        // Drag state
        private var isDragging = false
        private var dragStartTouchPosition: CGPoint = .zero
        private var dragStartCoinPosition: SIMD3<Float> = .zero
        private var lastValidPlanePosition: SIMD3<Float>?

        // Scale state
        private var initialScale: Float = 1.0
        private var currentScale: Float = 1.0

        init(coinPosition: Binding<SIMD3<Float>?>, isPlaced: Binding<Bool>, isAligned: Binding<Bool>) {
            _coinPosition = coinPosition
            _isPlaced = isPlaced
            _isAligned = isAligned
        }

        // MARK: - Tap Gesture (Initial Placement)

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView = arView else { return }

            // Don't place if already dragging
            guard !isDragging else { return }

            let tapLocation = sender.location(in: arView)

            // Raycast to find horizontal plane
            let raycastQuery = arView.makeRaycastQuery(
                from: tapLocation,
                allowing: .estimatedPlane,
                alignment: .horizontal
            )

            guard let query = raycastQuery else {
                print("❌ Could not create raycast query")
                return
            }

            let results = arView.session.raycast(query)

            if let firstResult = results.first {
                // Get position from raycast
                let worldTransform = firstResult.worldTransform
                let position = SIMD3<Float>(
                    worldTransform.columns.3.x,
                    worldTransform.columns.3.y,
                    worldTransform.columns.3.z
                )

                // Place coin at hit location (flat on table)
                coinOverlay.placeCoin(in: arView, at: position)
                coinPosition = position
                lastValidPlanePosition = position
                isPlaced = true

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                print("💰 Coin placed at: \(position)")
                print("   Height: \(position.y)m")
            } else {
                print("⚠️ No horizontal plane detected at tap location")
            }
        }

        // MARK: - Pan Gesture (Smooth Drag & Drop)

        @objc func handlePan(_ sender: UIPanGestureRecognizer) {
            guard let arView = arView, isPlaced else { return }

            let panLocation = sender.location(in: arView)

            switch sender.state {
            case .began:
                isDragging = true
                dragStartTouchPosition = panLocation
                dragStartCoinPosition = coinPosition ?? .zero

                print("🖐️ Started dragging coin from: \(dragStartCoinPosition)")

            case .changed:
                // ✅ FIX: Proper screen-to-world transformation
                guard let startPosition = lastValidPlanePosition else { return }

                // Create raycast from current touch position
                let raycastQuery = arView.makeRaycastQuery(
                    from: panLocation,
                    allowing: .estimatedPlane,
                    alignment: .horizontal
                )

                guard let query = raycastQuery else { return }
                let results = arView.session.raycast(query)

                if let result = results.first {
                    // Get new position from raycast
                    let worldTransform = result.worldTransform
                    let newPosition = SIMD3<Float>(
                        worldTransform.columns.3.x,
                        worldTransform.columns.3.y,
                        worldTransform.columns.3.z
                    )

                    // ✅ FIX: Keep Y-axis stable (don't jump up/down)
                    let stabilizedPosition = SIMD3<Float>(
                        newPosition.x,
                        startPosition.y,  // Keep original height
                        newPosition.z
                    )

                    // Update coin position smoothly
                    coinOverlay.updatePosition(stabilizedPosition)
                    coinPosition = stabilizedPosition
                    lastValidPlanePosition = stabilizedPosition

                    // Check alignment
                    checkAlignment(at: stabilizedPosition, in: arView)
                }

            case .ended, .cancelled:
                isDragging = false

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()

                print("🎯 Coin dropped at: \(coinPosition ?? .zero)")

                // Final alignment check
                if let position = coinPosition {
                    checkAlignment(at: position, in: arView)
                }

            default:
                break
            }
        }

        // MARK: - Pinch Gesture (Optional Scaling)

        @objc func handlePinch(_ sender: UIPinchGestureRecognizer) {
            guard let arView = arView, isPlaced else { return }

            switch sender.state {
            case .began:
                initialScale = currentScale
                print("🔍 Started scaling, initial: \(initialScale)")

            case .changed:
                // Calculate new scale
                let newScale = initialScale * Float(sender.scale)

                // Clamp scale (0.5x to 2.0x)
                currentScale = min(2.0, max(0.5, newScale))

                // Apply scale to coin (note: would need to modify ARCoinOverlay to support scaling)
                // For now, just log it
                // print("📏 Scale: \(currentScale)")

            case .ended:
                print("✅ Final scale: \(currentScale)")

            default:
                break
            }
        }

        // MARK: - Alignment Check

        /// Verbesserte Alignment-Prüfung
        private func checkAlignment(at position: SIMD3<Float>, in arView: ARView) {
            guard let frame = arView.session.currentFrame else {
                isAligned = false
                return
            }

            var alignmentScore: Float = 0.0

            // 1. Check plane proximity (wichtig!)
            let hasNearbyPlane = frame.anchors.contains { anchor in
                guard let planeAnchor = anchor as? ARPlaneAnchor else { return false }

                let planeY = planeAnchor.transform.columns.3.y
                let distanceToPlane = abs(position.y - planeY)

                // Coin should be within 1cm of plane
                return distanceToPlane < 0.01
            }

            if hasNearbyPlane {
                alignmentScore += 50.0
            }

            // 2. Check feature points density
            if let pointCloud = frame.rawFeaturePoints {
                let nearbyPoints = pointCloud.points.filter { point in
                    let distance = simd_distance(
                        SIMD3<Float>(point.x, point.y, point.z),
                        position
                    )
                    return distance < 0.05  // Within 5cm
                }

                // Good alignment needs at least 15 points nearby
                if nearbyPoints.count >= 15 {
                    alignmentScore += 30.0
                } else if nearbyPoints.count >= 5 {
                    alignmentScore += 15.0
                }
            }

            // 3. Check camera angle (should be looking down)
            let cameraTransform = frame.camera.transform
            let cameraDirection = SIMD3<Float>(
                cameraTransform.columns.2.x,
                cameraTransform.columns.2.y,
                cameraTransform.columns.2.z
            )

            // Camera should be pointing down (-Y direction)
            let dotProduct = dot(cameraDirection, SIMD3<Float>(0, -1, 0))
            if dotProduct > 0.7 {  // Within ~45° from vertical
                alignmentScore += 20.0
            }

            // Alignment is good if score >= 70
            isAligned = alignmentScore >= 70.0

            if alignmentScore >= 70 {
                print("✅ Alignment: \(Int(alignmentScore))% - GOOD")
            } else {
                print("⚠️ Alignment: \(Int(alignmentScore))% - Needs adjustment")
            }
        }

        // MARK: - ARSessionDelegate

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Continuous alignment check while dragging
            if isDragging, let position = coinPosition {
                checkAlignment(at: position, in: arView!)
            }
        }
    }
}

// MARK: - Preview

#if DEBUG
struct ImprovedCoinPlacementARView_Previews: PreviewProvider {
    static var previews: some View {
        ImprovedCoinPlacementARViewWrapper()
    }

    struct ImprovedCoinPlacementARViewWrapper: View {
        @State private var coinPosition: SIMD3<Float>? = nil
        @State private var isPlaced = false
        @State private var isAligned = false
        @State private var cameraAngle: Float = 45.0

        var body: some View {
            ZStack {
                ImprovedCoinPlacementARView(
                    coinPosition: $coinPosition,
                    isPlaced: $isPlaced,
                    isAligned: $isAligned,
                    cameraAngle: $cameraAngle
                )
                .edgesIgnoringSafeArea(.all)

                VStack {
                    // Camera angle feedback
                    HStack {
                        Image(systemName: cameraAngleIcon)
                            .font(.title)
                            .foregroundColor(cameraAngleColor)

                        VStack(alignment: .leading) {
                            Text(cameraAngleText)
                                .font(.headline)
                            Text("\(Int(cameraAngle))° von vertikal")
                                .font(.caption)
                        }
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding()

                    Spacer()

                    HStack {
                        Text("Platziert: \(isPlaced ? "✅" : "❌")")
                        Text("Ausgerichtet: \(isAligned ? "✅" : "❌")")
                    }
                    .padding()
                    .background(Color.black.opacity(0.7))
                    .foregroundColor(.white)
                    .cornerRadius(12)
                    .padding()
                }
            }
        }

        private var cameraAngleIcon: String {
            if cameraAngle < 30 { return "arrow.down.circle.fill" }
            if cameraAngle < 60 { return "arrow.down.forward.circle.fill" }
            return "arrow.forward.circle.fill"
        }

        private var cameraAngleColor: Color {
            if cameraAngle < 30 { return .green }
            if cameraAngle < 60 { return .orange }
            return .red
        }

        private var cameraAngleText: String {
            if cameraAngle < 30 { return "Perfekte Vogelperspektive!" }
            if cameraAngle < 60 { return "Etwas steiler schauen" }
            return "Von oben schauen"
        }
    }
}
#endif
