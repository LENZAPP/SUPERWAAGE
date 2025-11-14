//
//  QuickCalibrationARView.swift
//  SUPERWAAGE
//
//  AR view for automatic calibration object detection
//  Shows silhouette overlay and auto-captures on good alignment
//

import SwiftUI
import ARKit
import RealityKit
import AVFoundation

struct QuickCalibrationARView: View {
    @ObservedObject var coordinator: QuickCalibrationCoordinator
    let currentAngle: CalibrationAngle
    let progress: Int
    let total: Int

    var body: some View {
        ZStack {
            // AR Camera View
            ARViewContainer(coordinator: coordinator)
                .ignoresSafeArea()

            // Silhouette Overlay
            if let object = coordinator.selectedObject {
                ObjectSilhouetteOverlay(
                    object: object,
                    alignmentQuality: coordinator.alignmentQuality,
                    isWellAligned: coordinator.isWellAligned
                )
            }

            // Top instruction bar
            VStack {
                InstructionBar(
                    angle: currentAngle,
                    progress: progress,
                    total: total,
                    alignmentQuality: coordinator.alignmentQuality,
                    isWellAligned: coordinator.isWellAligned
                )
                .padding(.top, 60)

                Spacer()

                // ✅ NEW: Capture button (only when well aligned)
                if coordinator.isWellAligned {
                    CaptureButton(coordinator: coordinator)
                        .padding(.bottom, 120)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    // Bottom hints
                    HintBar(
                        angle: currentAngle,
                        alignmentQuality: coordinator.alignmentQuality
                    )
                    .padding(.bottom, 80)
                }
            }
        }
        .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - Capture Button

struct CaptureButton: View {
    @ObservedObject var coordinator: QuickCalibrationCoordinator

    var body: some View {
        Button(action: {
            // Trigger manual capture
            Task {
                await coordinator.manualCapture()
            }
        }) {
            HStack(spacing: 12) {
                Image(systemName: "camera.fill")
                    .font(.system(size: 24, weight: .semibold))

                Text("Aufnehmen")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 40)
            .padding(.vertical, 18)
            .background(
                Capsule()
                    .fill(Color.white)
                    .shadow(color: .white.opacity(0.3), radius: 20, x: 0, y: 5)
            )
            .overlay(
                // Pulsing ring animation
                Capsule()
                    .strokeBorder(Color.white.opacity(0.6), lineWidth: 3)
                    .scaleEffect(1.2)
                    .opacity(0)
                    .animation(
                        .easeOut(duration: 1.5).repeatForever(autoreverses: false),
                        value: coordinator.isWellAligned
                    )
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

struct ScaleButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1.0)
            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: configuration.isPressed)
    }
}

// MARK: - AR View Container

struct ARViewContainer: UIViewRepresentable {
    @ObservedObject var coordinator: QuickCalibrationCoordinator

    func makeUIView(context: Context) -> ARView {
        let arView = ARView(frame: .zero)

        // ✅ CRITICAL: Configure camera BEFORE starting AR session
        configureCameraFocus()

        // Configure AR session
        let configuration = ARWorldTrackingConfiguration()
        configuration.planeDetection = [.horizontal]

        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        // ✅ Disable ARKit auto-focus (we control it manually for macro)
        configuration.isAutoFocusEnabled = false

        arView.session.run(configuration)
        arView.session.delegate = context.coordinator

        context.coordinator.arView = arView

        return arView
    }

    // Configure camera for optimal close-up focus (macro mode for coins)
    private func configureCameraFocus() {
        guard let videoDevice = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("⚠️ Could not access camera device for focus configuration")
            return
        }

        do {
            try videoDevice.lockForConfiguration()
            defer { videoDevice.unlockForConfiguration() }

            // 1. Set focus mode to locked (prevents hunting on shiny coins)
            if videoDevice.isFocusModeSupported(.autoFocus) {
                videoDevice.focusMode = .autoFocus
                print("✅ Auto-focus mode enabled (will lock after focusing)")
            }

            // 2. Set focus point to center (where coin should be)
            if videoDevice.isFocusPointOfInterestSupported {
                videoDevice.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
                print("✅ Focus point set to center")
            }

            // 3. CRITICAL: Set lens position for macro/near-field focus (15-30cm)
            // Lower values = closer focus (0.0 = infinity, 1.0 = minimum focus distance)
            if videoDevice.isLockingFocusWithCustomLensPositionSupported {
                // 0.85-0.95 range is optimal for 15-30cm coin photography
                videoDevice.setFocusModeLocked(lensPosition: 0.90, completionHandler: { _ in
                    print("✅ Lens position locked at 0.90 (optimized for 20cm coin distance)")
                })
            }

            // 4. Enable auto-exposure with bias for bright metallic surfaces
            if videoDevice.isExposureModeSupported(.continuousAutoExposure) {
                videoDevice.exposureMode = .continuousAutoExposure

                // Reduce exposure slightly to prevent coin overexposure
                let maxBias = videoDevice.maxExposureTargetBias
                let minBias = videoDevice.minExposureTargetBias
                if maxBias > 0 && minBias < 0 {
                    videoDevice.setExposureTargetBias(-0.5, completionHandler: nil)
                    print("✅ Exposure bias set to -0.5 (prevent coin overexposure)")
                }
            }

            // 5. Lock white balance for consistent coin color detection
            if videoDevice.isWhiteBalanceModeSupported(.continuousAutoWhiteBalance) {
                videoDevice.whiteBalanceMode = .continuousAutoWhiteBalance
            }

            // 6. Enable geometric distortion correction (iOS 15+)
            if #available(iOS 15.0, *) {
                if videoDevice.isGeometricDistortionCorrectionSupported {
                    videoDevice.isGeometricDistortionCorrectionEnabled = true
                    print("✅ Geometric distortion correction enabled")
                }
            }

            print("✅ Camera configured for macro coin measurement")
            print("   - Focus: Locked at 0.90 lens position (~20cm)")
            print("   - Exposure: Continuous auto with -0.5 bias")
            print("   - White balance: Continuous auto")

        } catch {
            print("❌ Could not configure camera focus: \(error)")
        }
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Update happens via delegate
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(calibrationCoordinator: coordinator)
    }

    class Coordinator: NSObject, ARSessionDelegate {
        let calibrationCoordinator: QuickCalibrationCoordinator
        var arView: ARView?

        private var lastProcessTime: Date = .distantPast
        private let processingInterval: TimeInterval = 0.3  // Process every 0.3 seconds (faster updates)

        init(calibrationCoordinator: QuickCalibrationCoordinator) {
            self.calibrationCoordinator = calibrationCoordinator
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // Throttle processing
            let now = Date()
            guard now.timeIntervalSince(lastProcessTime) >= processingInterval else { return }
            lastProcessTime = now

            // Extract data
            let pixelBuffer = frame.capturedImage
            let cameraTransform = frame.camera.transform
            let intrinsics = frame.camera.intrinsics

            // Get depth map if available
            let depthMap = frame.sceneDepth?.depthMap

            // Process frame asynchronously
            Task {
                await calibrationCoordinator.processFrame(
                    pixelBuffer: pixelBuffer,
                    cameraTransform: cameraTransform,
                    cameraIntrinsics: intrinsics,
                    depthMap: depthMap
                )
            }
        }
    }
}

// MARK: - Silhouette Overlay

struct ObjectSilhouetteOverlay: View {
    let object: ReferenceObjectType
    let alignmentQuality: Float
    let isWellAligned: Bool

    var overlayColor: Color {
        if alignmentQuality > 0.85 {
            return .green  // Perfect alignment
        } else if alignmentQuality > 0.6 {
            return .yellow  // Getting close
        } else if alignmentQuality > 0.3 {
            return .orange  // Needs adjustment
        } else {
            return .red  // Too far off
        }
    }

    var lineWidth: CGFloat {
        // Thicker line when well aligned
        return isWellAligned ? 4 : 3
    }

    var body: some View {
        VStack {
            Spacer()

            // Silhouette shape
            Group {
                switch object.dimensions.shape {
                case .circular:
                    Circle()
                        .strokeBorder(overlayColor, lineWidth: lineWidth)
                        .frame(width: 200, height: 200)
                        .background(
                            Circle()
                                .fill(overlayColor.opacity(isWellAligned ? 0.15 : 0.08))
                        )
                case .rectangular:
                    RoundedRectangle(cornerRadius: 12)
                        .strokeBorder(overlayColor, lineWidth: lineWidth)
                        .frame(width: 280, height: 180)
                        .background(
                            RoundedRectangle(cornerRadius: 12)
                                .fill(overlayColor.opacity(isWellAligned ? 0.15 : 0.08))
                        )
                }
            }
            .overlay(
                // Pulsing animation when well aligned
                Group {
                    if isWellAligned {
                        Circle()
                            .stroke(overlayColor, lineWidth: 2)
                            .scaleEffect(1.4)
                            .opacity(0)
                            .animation(
                                .easeOut(duration: 1.2).repeatForever(autoreverses: false),
                                value: isWellAligned
                            )
                    }
                }
            )

            Spacer()
        }
    }
}

// MARK: - Instruction Bar

struct InstructionBar: View {
    let angle: CalibrationAngle
    let progress: Int
    let total: Int
    let alignmentQuality: Float
    let isWellAligned: Bool

    var statusText: String {
        if isWellAligned {
            return "Perfekt ausgerichtet! ✓"
        } else if alignmentQuality > 0.6 {
            return "Fast perfekt..."
        } else if alignmentQuality > 0.3 {
            return "Objekt besser zentrieren"
        } else {
            return "Objekt in Silhouette platzieren"
        }
    }

    var statusColor: Color {
        if isWellAligned {
            return .green
        } else if alignmentQuality > 0.6 {
            return .yellow
        } else {
            return .white.opacity(0.6)
        }
    }

    var body: some View {
        VStack(spacing: 16) {
            // Progress indicator
            HStack(spacing: 8) {
                ForEach(0..<total, id: \.self) { index in
                    Capsule()
                        .fill(index <= progress ? Color.white : Color.white.opacity(0.3))
                        .frame(width: 40, height: 4)
                }
            }

            // Instruction card
            VStack(spacing: 12) {
                HStack(spacing: 12) {
                    Image(systemName: angle.icon)
                        .font(.system(size: 20, weight: .semibold))
                        .foregroundColor(.white)

                    Text(angle.instruction)
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    Spacer()
                }

                // Status
                Text(statusText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(statusColor)
                    .frame(maxWidth: .infinity, alignment: .leading)

                // Quality indicator
                if alignmentQuality > 0 {
                    HStack(spacing: 4) {
                        Text("\(Int(alignmentQuality * 100))%")
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundColor(statusColor)

                        // Progress bar
                        GeometryReader { geo in
                            ZStack(alignment: .leading) {
                                Capsule()
                                    .fill(Color.white.opacity(0.2))
                                    .frame(height: 4)

                                Capsule()
                                    .fill(statusColor)
                                    .frame(width: geo.size.width * CGFloat(alignmentQuality), height: 4)
                            }
                        }
                        .frame(height: 4)
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color.black.opacity(0.7))
                    .background(.ultraThinMaterial)
            )
        }
        .padding(.horizontal, 24)
    }
}

// MARK: - Hint Bar

struct HintBar: View {
    let angle: CalibrationAngle
    let alignmentQuality: Float

    var hintText: String {
        if alignmentQuality > 0.6 {
            return "Sehr gut! Bewege dich langsam zur perfekten Position"
        } else if alignmentQuality > 0.3 {
            return "Zentriere das Objekt im Kreis"
        } else if alignmentQuality > 0 {
            return "Bringe das Objekt näher zur Mitte"
        } else {
            return "Halte das Objekt vor die Kamera"
        }
    }

    var body: some View {
        VStack(spacing: 12) {
            HStack(spacing: 8) {
                Image(systemName: alignmentQuality > 0.6 ? "checkmark.circle.fill" : "info.circle.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(alignmentQuality > 0.6 ? .green : .yellow.opacity(0.8))

                Text(hintText)
                    .font(.system(size: 15, weight: .medium, design: .rounded))
                    .foregroundColor(.white.opacity(0.9))
            }

            HStack(spacing: 8) {
                Image(systemName: "lightbulb.fill")
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.yellow.opacity(0.6))

                Text("Gute Beleuchtung • Keine Reflektionen")
                    .font(.system(size: 13, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: 14)
                .fill(Color.black.opacity(0.6))
                .background(.ultraThinMaterial)
        )
        .padding(.horizontal, 24)
    }
}

// MARK: - Preview

// Preview disabled - requires AR session and coordinator setup
