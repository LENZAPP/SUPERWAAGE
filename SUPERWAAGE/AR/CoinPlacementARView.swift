//
//  CoinPlacementARView.swift
//  SUPERWAAGE
//
//  AR view with draggable virtual coin overlay for calibration
//

import SwiftUI
import RealityKit
import ARKit
import Combine

/// AR view for placing virtual coin with drag & drop
struct CoinPlacementARView: UIViewRepresentable {
    @Binding var coinPosition: SIMD3<Float>?
    @Binding var isPlaced: Bool
    @Binding var isAligned: Bool

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // Configure AR session
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        arView.session.run(configuration)

        // Add tap gesture for initial placement
        let tapGesture = UITapGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handleTap(_:)))
        arView.addGestureRecognizer(tapGesture)

        // Add pan gesture for dragging
        let panGesture = UIPanGestureRecognizer(target: context.coordinator, action: #selector(Coordinator.handlePan(_:)))
        arView.addGestureRecognizer(panGesture)

        context.coordinator.arView = arView

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Update coin appearance based on alignment status
        if isPlaced {
            context.coordinator.coinOverlay.updateAlignmentFeedback(isAligned: isAligned)
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(
            coinPosition: $coinPosition,
            isPlaced: $isPlaced,
            isAligned: $isAligned
        )
    }

    class Coordinator: NSObject {
        @Binding var coinPosition: SIMD3<Float>?
        @Binding var isPlaced: Bool
        @Binding var isAligned: Bool

        var arView: ARView?
        var coinOverlay = ARCoinOverlay()
        private var isDragging = false

        init(coinPosition: Binding<SIMD3<Float>?>, isPlaced: Binding<Bool>, isAligned: Binding<Bool>) {
            _coinPosition = coinPosition
            _isPlaced = isPlaced
            _isAligned = isAligned
        }

        // MARK: - Tap Gesture (Initial Placement)

        @objc func handleTap(_ sender: UITapGestureRecognizer) {
            guard let arView = arView else { return }

            let tapLocation = sender.location(in: arView)

            // Perform raycast to find horizontal plane
            if let raycastResult = arView.raycast(from: tapLocation, allowing: .estimatedPlane, alignment: .horizontal).first {
                // Place coin at hit location
                let worldPosition = raycastResult.worldTransform.columns.3
                let position = SIMD3<Float>(worldPosition.x, worldPosition.y, worldPosition.z)

                coinOverlay.placeCoin(in: arView, at: position)
                coinPosition = position
                isPlaced = true

                // Provide haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                print("💰 Coin placed at: \(position)")
            }
        }

        // MARK: - Pan Gesture (Drag & Drop)

        @objc func handlePan(_ sender: UIPanGestureRecognizer) {
            guard let arView = arView, isPlaced else { return }

            let panLocation = sender.location(in: arView)

            switch sender.state {
            case .began:
                isDragging = true
                print("🖐️ Started dragging coin")

            case .changed:
                // Raycast to find new position
                if let raycastResult = arView.raycast(from: panLocation, allowing: .estimatedPlane, alignment: .horizontal).first {
                    let worldPosition = raycastResult.worldTransform.columns.3
                    let newPosition = SIMD3<Float>(worldPosition.x, worldPosition.y, worldPosition.z)

                    // Update coin position
                    coinOverlay.updatePosition(newPosition)
                    coinPosition = newPosition

                    // Check alignment (simplified - in real implementation, compare with scanned points)
                    checkAlignment(at: newPosition, in: arView)
                }

            case .ended, .cancelled:
                isDragging = false

                // Provide haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .light)
                generator.impactOccurred()

                print("🎯 Coin dropped at: \(coinPosition ?? .zero)")

            default:
                break
            }
        }

        // MARK: - Alignment Check

        /// Check if virtual coin aligns well with detected surfaces
        private func checkAlignment(at position: SIMD3<Float>, in arView: ARView) {
            // Simplified alignment check based on surface detection
            // In real implementation, you'd compare with scanned point cloud

            guard let frame = arView.session.currentFrame else {
                isAligned = false
                return
            }

            // Check if there's a detected plane nearby
            let hasNearbyPlane = frame.anchors.contains { anchor in
                guard let planeAnchor = anchor as? ARPlaneAnchor else { return false }

                // Check if coin position is near this plane
                let planeTransform = planeAnchor.transform
                let planeY = planeTransform.columns.3.y

                // Coin should be within 2cm of plane
                return abs(position.y - planeY) < 0.02
            }

            isAligned = hasNearbyPlane

            // Could also check for feature points density
            if let pointCloud = frame.rawFeaturePoints {
                let nearbyPoints = pointCloud.points.filter { point in
                    let distance = simd_distance(SIMD3<Float>(point.x, point.y, point.z), position)
                    return distance < 0.05  // Within 5cm
                }

                // Good alignment if many points nearby
                if nearbyPoints.count > 10 {
                    isAligned = true
                }
            }
        }
    }
}

// MARK: - Preview Helper

#if DEBUG
struct CoinPlacementARView_Previews: PreviewProvider {
    static var previews: some View {
        CoinPlacementARViewWrapper()
    }

    struct CoinPlacementARViewWrapper: View {
        @State private var coinPosition: SIMD3<Float>? = nil
        @State private var isPlaced = false
        @State private var isAligned = false

        var body: some View {
            ZStack {
                CoinPlacementARView(
                    coinPosition: $coinPosition,
                    isPlaced: $isPlaced,
                    isAligned: $isAligned
                )
                .edgesIgnoringSafeArea(.all)

                VStack {
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
    }
}
#endif
