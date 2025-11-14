//
//  ARSessionManager.swift
//  SUPERWAAGE
//
//  Centralized ARSession manager with optimal configuration for high-precision measurements
//  Target: <5% measurement error
//

import Foundation
import ARKit
import RealityKit
import Combine

@MainActor
class ARSessionManager: NSObject, ObservableObject {

    // MARK: - Published Properties

    @Published private(set) var isRunning = false
    @Published private(set) var trackingQuality: ARCamera.TrackingState = .notAvailable
    @Published private(set) var meshAnchors: [ARMeshAnchor] = []
    @Published private(set) var detectedPlanes: [ARPlaneAnchor] = []
    @Published private(set) var currentFrame: ARFrame?
    @Published private(set) var sceneDepth: ARDepthData?

    // Quality metrics
    @Published private(set) var meshQuality: MeshQualityMetrics = .initial
    @Published private(set) var warnings: [ScanWarning] = []

    // MARK: - Properties

    let session: ARSession
    private var configuration: ARWorldTrackingConfiguration?
    private var cancellables = Set<AnyCancellable>()

    // Callbacks
    var onFrameUpdate: ((ARFrame) -> Void)?
    var onMeshUpdate: (([ARMeshAnchor]) -> Void)?
    var onPlaneDetected: ((ARPlaneAnchor) -> Void)?

    // MARK: - Initialization

    override init() {
        self.session = ARSession()
        super.init()
        session.delegate = self
    }

    // MARK: - Session Control

    /// Start AR session with optimal configuration for precision measurement
    func startSession(enableSceneReconstruction: Bool = true) {
        guard ARWorldTrackingConfiguration.isSupported else {
            print("❌ ARWorldTracking not supported on this device")
            return
        }

        // ✅ CRITICAL: Configure camera BEFORE starting AR session
        configureCameraForScanning()

        let config = ARWorldTrackingConfiguration()

        // ✅ OPTIMAL CONFIGURATION FOR PRECISION

        // 1. Enable plane detection (horizontal + vertical)
        config.planeDetection = [.horizontal, .vertical]

        // 2. Enable scene depth (LiDAR)
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics.insert(.sceneDepth)
            print("✅ Scene depth enabled (LiDAR)")
        }

        // 3. Enable smoothed scene depth
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            config.frameSemantics.insert(.smoothedSceneDepth)
            print("✅ Smoothed scene depth enabled")
        }

        // 4. Enable mesh reconstruction
        if enableSceneReconstruction &&
           ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh) {
            config.sceneReconstruction = .mesh
            print("✅ Scene reconstruction enabled")
        }

        // 5. Disable auto-focus (we control it manually)
        config.isAutoFocusEnabled = false

        // 6. High-quality video format
        if let highResFormat = ARWorldTrackingConfiguration.supportedVideoFormats.first(where: {
            $0.imageResolution.width >= 1920
        }) {
            config.videoFormat = highResFormat
            print("✅ High-res video format: \(highResFormat.imageResolution)")
        }

        // 7. World alignment
        config.worldAlignment = .gravity

        // 8. Collaboration data (for future multi-device support)
        // config.isCollaborationEnabled = true

        self.configuration = config

        // Run session
        let options: ARSession.RunOptions = [.resetTracking, .removeExistingAnchors]
        session.run(config, options: options)

        isRunning = true
        print("✅ AR Session started with optimal configuration")
    }

    // MARK: - Camera Configuration for Scanning

    /// Configure camera for optimal scanning (20-50cm range)
    private func configureCameraForScanning() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("⚠️ Could not access camera device")
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            // 1. Use continuous autofocus for dynamic scanning
            if device.isFocusModeSupported(.continuousAutoFocus) {
                device.focusMode = .continuousAutoFocus
                print("✅ Continuous auto-focus enabled")
            }

            // 2. Set focus point to center
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }

            // 3. Enable auto-exposure
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure
            }

            // 4. Optimize for scanning range (20-50cm)
            if device.isLockingFocusWithCustomLensPositionSupported {
                // Start with mid-range focus for scanning
                device.setFocusModeLocked(lensPosition: 0.75, completionHandler: { _ in
                    // Then release to continuous after initial lock
                    try? device.lockForConfiguration()
                    if device.isFocusModeSupported(.continuousAutoFocus) {
                        device.focusMode = .continuousAutoFocus
                    }
                    device.unlockForConfiguration()
                })
            }

            print("✅ Camera configured for 3D scanning (20-50cm range)")

        } catch {
            print("❌ Failed to configure camera: \(error)")
        }
    }

    /// Pause AR session
    func pauseSession() {
        session.pause()
        isRunning = false
        print("⏸ AR Session paused")
    }

    /// Reset AR session
    func resetSession() {
        guard let config = configuration else { return }
        session.run(config, options: [.resetTracking, .removeExistingAnchors])
        meshAnchors.removeAll()
        detectedPlanes.removeAll()
        warnings.removeAll()
        print("🔄 AR Session reset")
    }

    // MARK: - Mesh Management

    /// Get all mesh anchors with minimum quality threshold
    func getQualityMeshAnchors(minTriangles: Int = 100) -> [ARMeshAnchor] {
        return meshAnchors.filter { anchor in
            anchor.geometry.faces.count >= minTriangles
        }
    }

    /// Get mesh anchors within a specific region
    func getMeshAnchors(in boundingBox: BoundingBox) -> [ARMeshAnchor] {
        return meshAnchors.filter { anchor in
            let position = SIMD3<Float>(
                anchor.transform.columns.3.x,
                anchor.transform.columns.3.y,
                anchor.transform.columns.3.z
            )
            return boundingBox.contains(position)
        }
    }

    // MARK: - Quality Analysis

    /// Analyze current mesh quality
    private func analyzeMeshQuality() {
        let totalTriangles = meshAnchors.reduce(0) { $0 + $1.geometry.faces.count }
        let totalVertices = meshAnchors.reduce(0) { $0 + $1.geometry.vertices.count }

        let coverage: Float = calculateCoverage()
        let density: Float = Float(totalTriangles) / max(Float(meshAnchors.count), 1)

        meshQuality = MeshQualityMetrics(
            totalMeshAnchors: meshAnchors.count,
            totalTriangles: totalTriangles,
            totalVertices: totalVertices,
            coverage: coverage,
            triangleDensity: density,
            qualityScore: calculateQualityScore(coverage: coverage, density: density)
        )

        updateWarnings()
    }

    private func calculateCoverage() -> Float {
        // Simplified coverage calculation
        guard !meshAnchors.isEmpty else { return 0 }

        // Check if we have mesh data from multiple angles
        let positions = meshAnchors.map { anchor in
            SIMD3<Float>(
                anchor.transform.columns.3.x,
                anchor.transform.columns.3.y,
                anchor.transform.columns.3.z
            )
        }

        guard let bbox = BoundingBox.from(points: positions) else { return 0 }

        let volume = bbox.size.x * bbox.size.y * bbox.size.z
        let meshCount = Float(meshAnchors.count)

        // Coverage increases with mesh count and decreases with volume
        return min(meshCount / (volume * 100), 1.0)
    }

    private func calculateQualityScore(coverage: Float, density: Float) -> Float {
        let coverageWeight: Float = 0.4
        let densityWeight: Float = 0.3
        let trackingWeight: Float = 0.3

        let coverageScore = coverage
        let densityScore = min(density / 50.0, 1.0) // 50 triangles/anchor is good

        let trackingScore: Float = {
            switch trackingQuality {
            case .normal: return 1.0
            case .limited: return 0.6
            case .notAvailable: return 0.0
            @unknown default: return 0.5
            }
        }()

        return coverageScore * coverageWeight +
               densityScore * densityWeight +
               trackingScore * trackingWeight
    }

    // MARK: - Warnings

    private func updateWarnings() {
        warnings.removeAll()

        // Check tracking quality
        if case .limited(let reason) = trackingQuality {
            switch reason {
            case .excessiveMotion:
                warnings.append(.excessiveMotion)
            case .insufficientFeatures:
                warnings.append(.poorLighting)
            case .initializing:
                warnings.append(.initializing)
            case .relocalizing:
                break
            @unknown default:
                break
            }
        }

        // Check mesh quality
        if meshQuality.totalTriangles < 500 {
            warnings.append(.insufficientData)
        }

        if meshQuality.coverage < 0.3 {
            warnings.append(.incompleteCoverage)
        }

        // Check if too far from object
        if let frame = currentFrame {
            let cameraPosition = frame.camera.transform.columns.3
            let averageMeshDistance = calculateAverageMeshDistance(from: cameraPosition)

            if averageMeshDistance > 1.0 {
                warnings.append(.tooFarFromObject)
            } else if averageMeshDistance < 0.15 {
                warnings.append(.tooCloseToObject)
            }
        }
    }

    private func calculateAverageMeshDistance(from cameraPosition: SIMD4<Float>) -> Float {
        guard !meshAnchors.isEmpty else { return 0 }

        let cameraPos = SIMD3<Float>(cameraPosition.x, cameraPosition.y, cameraPosition.z)

        let totalDistance = meshAnchors.reduce(Float(0)) { sum, anchor in
            let meshPos = SIMD3<Float>(
                anchor.transform.columns.3.x,
                anchor.transform.columns.3.y,
                anchor.transform.columns.3.z
            )
            return sum + simd_distance(cameraPos, meshPos)
        }

        return totalDistance / Float(meshAnchors.count)
    }

    // MARK: - Camera Configuration

    /// Configure camera for close-up focus (macro mode for coins/small objects)
    func enableMacroMode() {
        guard let device = AVCaptureDevice.default(.builtInWideAngleCamera, for: .video, position: .back) else {
            print("⚠️ Could not access camera device for macro mode")
            return
        }

        do {
            try device.lockForConfiguration()
            defer { device.unlockForConfiguration() }

            // 1. Lock focus at near distance for macro photography
            if device.isLockingFocusWithCustomLensPositionSupported {
                device.setFocusModeLocked(lensPosition: 0.90, completionHandler: { _ in
                    print("✅ Macro mode: Lens locked at 0.90 (~20cm)")
                })
            } else if device.isFocusModeSupported(.autoFocus) {
                device.focusMode = .autoFocus
                print("✅ Macro mode: Auto-focus enabled")
            }

            // 2. Focus point at center
            if device.isFocusPointOfInterestSupported {
                device.focusPointOfInterest = CGPoint(x: 0.5, y: 0.5)
            }

            // 3. Auto exposure with reduced bias for shiny surfaces
            if device.isExposureModeSupported(.continuousAutoExposure) {
                device.exposureMode = .continuousAutoExposure

                let maxBias = device.maxExposureTargetBias
                let minBias = device.minExposureTargetBias
                if maxBias > 0 && minBias < 0 {
                    device.setExposureTargetBias(-0.5, completionHandler: nil)
                    print("✅ Macro mode: Exposure bias -0.5")
                }
            }

            // 4. Enable geometric distortion correction
            if #available(iOS 15.0, *) {
                if device.isGeometricDistortionCorrectionSupported {
                    device.isGeometricDistortionCorrectionEnabled = true
                }
            }

            print("✅ Macro mode enabled for close-up measurement")

        } catch {
            print("❌ Failed to enable macro mode: \(error)")
        }
    }
}

// MARK: - ARSessionDelegate

extension ARSessionManager: ARSessionDelegate {

    nonisolated func session(_ session: ARSession, didUpdate frame: ARFrame) {
        Task { @MainActor in
            self.currentFrame = frame
            self.trackingQuality = frame.camera.trackingState
            self.sceneDepth = frame.sceneDepth

            self.onFrameUpdate?(frame)
        }
    }

    nonisolated func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    self.meshAnchors.append(meshAnchor)
                } else if let planeAnchor = anchor as? ARPlaneAnchor {
                    self.detectedPlanes.append(planeAnchor)
                    self.onPlaneDetected?(planeAnchor)
                }
            }

            self.analyzeMeshQuality()
            self.onMeshUpdate?(self.meshAnchors)
        }
    }

    nonisolated func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    if let index = self.meshAnchors.firstIndex(where: { $0.identifier == meshAnchor.identifier }) {
                        self.meshAnchors[index] = meshAnchor
                    }
                } else if let planeAnchor = anchor as? ARPlaneAnchor {
                    if let index = self.detectedPlanes.firstIndex(where: { $0.identifier == planeAnchor.identifier }) {
                        self.detectedPlanes[index] = planeAnchor
                    }
                }
            }

            self.analyzeMeshQuality()
            self.onMeshUpdate?(self.meshAnchors)
        }
    }

    nonisolated func session(_ session: ARSession, didRemove anchors: [ARAnchor]) {
        Task { @MainActor in
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    self.meshAnchors.removeAll { $0.identifier == meshAnchor.identifier }
                } else if let planeAnchor = anchor as? ARPlaneAnchor {
                    self.detectedPlanes.removeAll { $0.identifier == planeAnchor.identifier }
                }
            }

            self.analyzeMeshQuality()
        }
    }
}

// MARK: - Supporting Types

struct MeshQualityMetrics {
    let totalMeshAnchors: Int
    let totalTriangles: Int
    let totalVertices: Int
    let coverage: Float
    let triangleDensity: Float
    let qualityScore: Float

    static let initial = MeshQualityMetrics(
        totalMeshAnchors: 0,
        totalTriangles: 0,
        totalVertices: 0,
        coverage: 0,
        triangleDensity: 0,
        qualityScore: 0
    )

    var qualityDescription: String {
        switch qualityScore {
        case 0.9...1.0: return "Exzellent"
        case 0.7..<0.9: return "Sehr gut"
        case 0.5..<0.7: return "Gut"
        case 0.3..<0.5: return "Befriedigend"
        default: return "Ungenügend"
        }
    }
}

enum ScanWarning: Equatable {
    case excessiveMotion
    case poorLighting
    case insufficientData
    case incompleteCoverage
    case tooFarFromObject
    case tooCloseToObject
    case initializing

    var message: String {
        switch self {
        case .excessiveMotion:
            return "Bewege die Kamera langsamer"
        case .poorLighting:
            return "Bessere Beleuchtung erforderlich"
        case .insufficientData:
            return "Scanne das Objekt von mehr Seiten"
        case .incompleteCoverage:
            return "Bewege dich um das Objekt herum"
        case .tooFarFromObject:
            return "Gehe näher an das Objekt heran (20-50cm)"
        case .tooCloseToObject:
            return "Zu nah! Halte 20-50cm Abstand"
        case .initializing:
            return "AR wird initialisiert..."
        }
    }

    var icon: String {
        switch self {
        case .excessiveMotion: return "arrow.trianglehead.2.clockwise.rotate.90"
        case .poorLighting: return "lightbulb.fill"
        case .insufficientData: return "cube.transparent"
        case .incompleteCoverage: return "arrow.3.trianglepath"
        case .tooFarFromObject: return "arrow.down.right.and.arrow.up.left"
        case .tooCloseToObject: return "arrow.up.left.and.arrow.down.right"
        case .initializing: return "hourglass"
        }
    }
}
