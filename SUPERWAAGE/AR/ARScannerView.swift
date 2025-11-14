//
//  ARScannerView.swift
//  SUPERWAAGE
//
//  AR View with LiDAR scanning capabilities
//  Adapted from ARKit-Scanner and LiDAR-Depth-Map-Capture repos
//  Metal optimization for GPU-accelerated depth texture processing
//

import SwiftUI
import ARKit
import RealityKit
import Metal
import CoreVideo
import AVFoundation

struct ARScannerView: UIViewRepresentable {
    @EnvironmentObject var scanViewModel: ScanViewModel
    @StateObject private var permissionManager = PermissionManager.shared

    func makeUIView(context: Context) -> ARView {
        // ✅ FIX: Check camera permission before initializing AR
        Task { @MainActor in
            _ = await permissionManager.requestCameraPermission()
        }

        let arView = ARView(frame: .zero)

        // Configure AR session
        let configuration = ARWorldTrackingConfiguration()

        // ✅ FIX: Start WITHOUT scene reconstruction (helps SLAM init)
        // Enable LiDAR scene reconstruction (delayed)
        // Scene reconstruction will be enabled after 5 seconds (see below)
        // Was: configuration.sceneReconstruction = .meshWithClassification

        // Enable scene depth
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            configuration.frameSemantics.insert(.sceneDepth)
        }

        // Enable smooth surfaces
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
            configuration.frameSemantics.insert(.smoothedSceneDepth)
        }

        // Set video format (prefer 4:3 for better depth capture)
        if let format = find4by3VideoFormat() {
            configuration.videoFormat = format
        }

        // Configure lighting
        arView.environment.lighting.intensityExponent = 1.5

        // Set session delegate
        arView.session.delegate = context.coordinator
        scanViewModel.setARSession(arView.session)

        // Add tap gesture for object selection
        let tapGesture = UITapGestureRecognizer(
            target: context.coordinator,
            action: #selector(context.coordinator.handleTap(_:))
        )
        arView.addGestureRecognizer(tapGesture)
        context.coordinator.arView = arView

        // ✅ FIX: Only start session once (SwiftUI may call makeUIView multiple times)
        if !context.coordinator.sessionStarted {
            context.coordinator.sessionStarted = true
            print("▶️ Starting AR session (first time)")

            // Run session
            arView.session.run(configuration)

            // ✅ FIX: Enable scene reconstruction after SLAM initializes (8 seconds)
            // Store timer reference in coordinator to prevent multiple executions
            let videoFormat = find4by3VideoFormat()
            context.coordinator.scheduleSLAMInit(arView: arView, videoFormat: videoFormat)
        } else {
            print("⚠️ AR session already started, skipping duplicate initialization")
        }

        return arView
    }

    func updateUIView(_ uiView: ARView, context: Context) {
        // Update visualization based on scan state
        context.coordinator.updateVisualization(arView: uiView)
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(scanViewModel: scanViewModel)
    }

    // MARK: - Helper Methods
    private func find4by3VideoFormat() -> ARConfiguration.VideoFormat? {
        let availableFormats = ARWorldTrackingConfiguration.supportedVideoFormats
        for format in availableFormats {
            let resolution = format.imageResolution
            if resolution.width / 4 == resolution.height / 3 {
                return format
            }
        }
        return nil
    }

    // MARK: - Coordinator
    class Coordinator: NSObject, ARSessionDelegate {
        var scanViewModel: ScanViewModel
        var meshEntities: [UUID: ModelEntity] = [:]
        var boundingBoxEntity: Entity?
        weak var arView: ARView?

        // Segmentation filter for removing background points
        private lazy var segmentationFilter: SegmentationPointFilter = {
            SegmentationPointFilter(mode: .object)
        }()

        private var lastSegmentationMask: CVPixelBuffer?
        private var frameCounter: Int = 0

        // ✅ FIX: Mesh anchor throttling
        private var lastMeshAnchorUpdate: Date = Date()
        private var meshAnchorUpdateCounter: Int = 0

        // ✅ METAL OPTIMIZATION: GPU-accelerated depth texture conversion
        private let metalDevice: MTLDevice? = MTLCreateSystemDefaultDevice()
        private var cvTextureCache: CVMetalTextureCache?
        private var lastDepthIntegrationTime: CFTimeInterval = 0
        private let depthIntegrationInterval: TimeInterval = 0.05 // 20 Hz max

        // ✅ FIX: Prevent multiple SLAM init attempts
        fileprivate var slamInitScheduled = false

        // ✅ FIX: Prevent multiple session starts (SwiftUI can call makeUIView multiple times)
        fileprivate var sessionStarted = false

        // ✅ FIX: Prevent segmentation task stacking
        private var isProcessingSegmentation = false

        init(scanViewModel: ScanViewModel) {
            self.scanViewModel = scanViewModel
            super.init()

            // ✅ Create CVMetalTextureCache for efficient depth texture conversion
            if let device = metalDevice {
                var cache: CVMetalTextureCache?
                let status = CVMetalTextureCacheCreate(kCFAllocatorDefault, nil, device, nil, &cache)
                if status == kCVReturnSuccess {
                    cvTextureCache = cache
                    print("✅ CVMetalTextureCache initialized successfully")
                } else {
                    print("⚠️ CVMetalTextureCacheCreate failed with status: \(status)")
                }
            } else {
                print("⚠️ Metal device not available - depth texture optimization disabled")
            }
        }

        // MARK: - SLAM Initialization
        /// Schedule SLAM init once, prevents multiple timer executions
        func scheduleSLAMInit(arView: ARView, videoFormat: ARConfiguration.VideoFormat?) {
            guard !slamInitScheduled else {
                print("⚠️ SLAM init already scheduled, skipping duplicate")
                return
            }
            slamInitScheduled = true

            print("⏳ SLAM initialization: Waiting for stable tracking...")

            // ✅ IMPROVED: Check SLAM readiness instead of fixed delay
            var slamReadyChecks = 0
            var checkCount = 0
            let maxChecks = 30 // 15 seconds max (check every 0.5s)

            let timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self, weak arView] timer in
                guard let self = self, let arView = arView else {
                    timer.invalidate()
                    return
                }

                checkCount += 1
                let trackingState = arView.session.currentFrame?.camera.trackingState

                // Check for normal tracking
                if case .normal = trackingState {
                    slamReadyChecks += 1
                    print("✅ SLAM check \(slamReadyChecks)/3: Tracking normal")

                    // Require 3 consecutive "normal" tracking states (1.5 seconds stable)
                    if slamReadyChecks >= 3 {
                        timer.invalidate()
                        self.enableSceneReconstruction(arView: arView, videoFormat: videoFormat)
                        return
                    }
                } else {
                    // Reset counter if tracking degrades
                    if slamReadyChecks > 0 {
                        let stateDesc = self.trackingStateDescription(trackingState)
                        print("⚠️ SLAM check reset: \(stateDesc)")
                    }
                    slamReadyChecks = 0
                }

                // Timeout after 15 seconds (fallback)
                if checkCount >= maxChecks {
                    timer.invalidate()
                    print("⚠️ SLAM initialization timeout (\(Double(maxChecks) * 0.5)s), enabling scene reconstruction anyway")
                    self.enableSceneReconstruction(arView: arView, videoFormat: videoFormat)
                }
            }

            // Ensure timer runs
            RunLoop.main.add(timer, forMode: .common)
        }

        /// Enable scene reconstruction after SLAM is ready
        private func enableSceneReconstruction(arView: ARView, videoFormat: ARConfiguration.VideoFormat?) {
            guard ARWorldTrackingConfiguration.supportsSceneReconstruction(.meshWithClassification) else {
                print("❌ Device does not support mesh reconstruction")
                return
            }

            // ✅ FIX: Configure on background thread to prevent main thread blocking
            DispatchQueue.global(qos: .userInitiated).async {
                let newConfig = ARWorldTrackingConfiguration()
                newConfig.sceneReconstruction = .meshWithClassification

                // Copy other settings
                if let format = videoFormat {
                    newConfig.videoFormat = format
                }
                if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
                    newConfig.frameSemantics.insert(.sceneDepth)
                }
                if ARWorldTrackingConfiguration.supportsFrameSemantics(.smoothedSceneDepth) {
                    newConfig.frameSemantics.insert(.smoothedSceneDepth)
                }

                // ✅ Run session on main thread (ARKit requirement)
                DispatchQueue.main.async {
                    arView.session.run(newConfig, options: [.removeExistingAnchors])
                    print("✅ Scene reconstruction enabled - SLAM ready for scanning")
                }
            }
        }

        /// Helper to describe tracking state
        private func trackingStateDescription(_ state: ARCamera.TrackingState?) -> String {
            guard let state = state else { return "unknown" }

            switch state {
            case .normal:
                return "normal"
            case .notAvailable:
                return "not available"
            case .limited(.initializing):
                return "initializing"
            case .limited(.excessiveMotion):
                return "excessive motion"
            case .limited(.insufficientFeatures):
                return "insufficient features"
            case .limited(.relocalizing):
                return "relocalizing"
            case .limited:
                return "limited (unknown)"
            @unknown default:
                return "unknown state"
            }
        }

        // MARK: - Tap Gesture Handler
        @objc func handleTap(_ gesture: UITapGestureRecognizer) {
            guard let arView = arView else { return }

            // Only allow tap selection when scanning (not during idle or processing)
            guard scanViewModel.scanState == .scanning else {
                print("🎯 Tap ignored - scan state: \(scanViewModel.scanState)")
                return
            }

            let tapLocation = gesture.location(in: arView)

            Task { @MainActor in
                scanViewModel.handleObjectSelection(at: tapLocation, in: arView)
            }
        }

        // MARK: - ARSessionDelegate

        /// ✅ FIXED: Mesh anchor throttling to prevent backboardd hang
        func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
            // ✅ THROTTLE: Only process every 100ms
            let now = Date()
            guard now.timeIntervalSince(lastMeshAnchorUpdate) > 0.1 else { return }
            lastMeshAnchorUpdate = now

            // ✅ LIMIT: Process max 20 anchors at a time
            var processed = 0
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    scanViewModel.addMeshAnchor(meshAnchor)
                    processed += 1
                    if processed >= 20 { break }
                }
            }

            meshAnchorUpdateCounter += processed
            if meshAnchorUpdateCounter > 50 {
                print("⚠️ Throttled \(meshAnchorUpdateCounter) mesh anchors")
                meshAnchorUpdateCounter = 0
            }
        }

        /// ✅ FIXED: Same throttling for updates
        func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
            let now = Date()
            guard now.timeIntervalSince(lastMeshAnchorUpdate) > 0.1 else { return }
            lastMeshAnchorUpdate = now

            var processed = 0
            for anchor in anchors {
                if let meshAnchor = anchor as? ARMeshAnchor {
                    scanViewModel.updateMeshAnchor(meshAnchor)
                    processed += 1
                    if processed >= 20 { break }
                }
            }
        }

        func session(_ session: ARSession, didUpdate frame: ARFrame) {
            // ✅ FIXED: Extract data immediately, don't retain frame

            // Update tracking quality (fast, no retention)
            updateTrackingQuality(frame: frame)

            // ✅ METAL OPTIMIZATION: GPU-accelerated depth integration (throttled to 20 Hz)
            let now = CACurrentMediaTime()
            if scanViewModel.scanState == .scanning,
               now - lastDepthIntegrationTime >= depthIntegrationInterval,
               let cache = cvTextureCache,
               let sceneDepth = frame.sceneDepth {

                lastDepthIntegrationTime = now

                // Extract depth data immediately (don't capture frame)
                let depthPixelBuffer = sceneDepth.depthMap
                let _ = frame.camera.intrinsics  // TODO: Use for Metal TSDF integration
                let _ = frame.camera.transform   // TODO: Use for Metal TSDF integration

                // Convert depth pixel buffer to MTLTexture on background queue
                DispatchQueue.global(qos: .userInitiated).async { [weak self] in
                    guard let self = self else { return }

                    let width = CVPixelBufferGetWidth(depthPixelBuffer)
                    let height = CVPixelBufferGetHeight(depthPixelBuffer)
                    var cvMetalTex: CVMetalTexture?

                    // Create MTLTexture from CVPixelBuffer using the cached converter
                    let status = CVMetalTextureCacheCreateTextureFromImage(
                        kCFAllocatorDefault,
                        cache,
                        depthPixelBuffer,
                        nil,
                        .r32Float, // Float32 depth format
                        width,
                        height,
                        0,
                        &cvMetalTex
                    )

                    if status == kCVReturnSuccess,
                       let cvTex = cvMetalTex,
                       let _ = CVMetalTextureGetTexture(cvTex) {

                        // ✅ SUCCESS: We have an MTLTexture backed by the depth buffer
                        // TODO: Integrate with TSDFMetalVolume when available
                        // let depthTexture = CVMetalTextureGetTexture(cvTex)
                        // Example: tsdfMetal?.integrateDepth(depthTexture: depthTexture,
                        //                                    intrinsics: intrinsics,
                        //                                    cameraTransform: cameraTransform,
                        //                                    weightScale: 1.0)

                        // For now, just log success (remove when Metal TSDF is integrated)
                        // print("✅ Depth texture created: \(width)×\(height)")
                    } else {
                        // Texture creation failed - continue with CPU path below
                        if frameCounter % 30 == 0 { // Log occasionally to avoid spam
                            print("⚠️ CVMetalTextureCacheCreateTextureFromImage failed: \(status)")
                        }
                    }
                }
            }

            // Early exit if not scanning
            guard scanViewModel.scanState == .scanning else { return }

            // Throttle to every 5th frame (was 3rd - reducing load for SLAM)
            frameCounter += 1
            guard frameCounter % 5 == 0 else { return }

            // Run segmentation when an object is selected
            guard scanViewModel.isObjectSelected else { return }

            // ✅ CRITICAL FIX: Prevent task stacking - only one segmentation at a time
            guard !isProcessingSegmentation else {
                // Segmentation already running, skip this frame to prevent memory buildup
                return
            }

            // ✅ CRITICAL FIX: Extract pixel buffer NOW, don't pass frame to closures
            let pixelBuffer = frame.capturedImage

            // Mark as processing
            isProcessingSegmentation = true

            // ✅ CRITICAL: Use weak self, don't capture frame
            Task { [weak self] in
                guard let self = self else {
                    self?.isProcessingSegmentation = false
                    return
                }

                self.segmentationFilter.segment(pixelBuffer: pixelBuffer, orientation: .right) { [weak self] mask in
                    guard let self = self, let mask = mask else {
                        self?.isProcessingSegmentation = false
                        return
                    }

                    self.lastSegmentationMask = mask

                    let coverage = self.segmentationFilter.calculateCoverage(mask: mask)

                    Task { @MainActor in
                        self.scanViewModel.segmentationCoverage = coverage
                    }

                    // Mark as done
                    self.isProcessingSegmentation = false
                }
            }

            // ✅ Frame released here - no retention!
        }

        private func updateTrackingQuality(frame: ARFrame) {
            let camera = frame.camera
            let trackingState = camera.trackingState

            switch trackingState {
            case .normal:
                scanViewModel.trackingQuality = .good
            case .limited(.initializing), .limited(.relocalizing):
                scanViewModel.trackingQuality = .normal
            case .limited(.excessiveMotion), .limited(.insufficientFeatures):
                scanViewModel.trackingQuality = .limited
            case .notAvailable:
                scanViewModel.trackingQuality = .limited
            @unknown default:
                scanViewModel.trackingQuality = .limited
            }
        }

        func session(_ session: ARSession, didFailWithError error: Error) {
            print("AR Session failed: \(error.localizedDescription)")
        }

        // MARK: - Visualization
        func updateVisualization(arView: ARView) {
            switch scanViewModel.scanState {
            case .idle:
                clearVisualization(arView: arView)

            case .scanning:
                visualizeMesh(arView: arView)

            case .processing:
                break

            case .completed:
                visualizeBoundingBox(arView: arView)

            case .error:
                clearVisualization(arView: arView)
            }
        }

        private func visualizeMesh(arView: ARView) {
            // Visualize mesh anchors during scanning
            for anchor in scanViewModel.meshAnchors {
                if meshEntities[anchor.identifier] == nil {
                    let meshEntity = createMeshEntity(from: anchor)
                    let anchorEntity = AnchorEntity(anchor: anchor)
                    anchorEntity.addChild(meshEntity)
                    arView.scene.addAnchor(anchorEntity)
                    meshEntities[anchor.identifier] = meshEntity
                }
            }
        }

        private func visualizeBoundingBox(arView: ARView) {
            // Clear mesh visualization
            clearMeshVisualization(arView: arView)

            // Show bounding box
            if boundingBoxEntity == nil {
                let dimensions = scanViewModel.dimensions

                // ✅ CRITICAL: Validate dimensions before conversion
                guard dimensions.x.isFinite && dimensions.y.isFinite && dimensions.z.isFinite,
                      dimensions.x > 0 && dimensions.y > 0 && dimensions.z > 0 else {
                    print("⚠️ Invalid dimensions for bounding box: \(dimensions)")
                    return
                }

                let bounds = SIMD3<Float>(
                    dimensions.x / 100.0,  // Convert cm to meters
                    dimensions.y / 100.0,
                    dimensions.z / 100.0
                )

                // ✅ CRITICAL: Validate bounds after conversion
                guard bounds.x.isFinite && bounds.y.isFinite && bounds.z.isFinite else {
                    print("⚠️ Invalid bounds after conversion: \(bounds)")
                    return
                }

                // Create bounds visualizer
                let boundsViz = createBoundsVisualizer(bounds: bounds)
                arView.scene.addAnchor(boundsViz)
                boundingBoxEntity = boundsViz
            }
        }

        private func clearVisualization(arView: ARView) {
            clearMeshVisualization(arView: arView)
            clearBoundingBoxVisualization(arView: arView)
        }

        private func clearMeshVisualization(arView: ARView) {
            for (_, entity) in meshEntities {
                entity.removeFromParent()
            }
            meshEntities.removeAll()
        }

        private func clearBoundingBoxVisualization(arView: ARView) {
            boundingBoxEntity?.removeFromParent()
            boundingBoxEntity = nil
        }

        // MARK: - Entity Creation
        private func createMeshEntity(from anchor: ARMeshAnchor) -> ModelEntity {
            let geometry = anchor.geometry

            // Create mesh descriptor
            var meshDescriptor = MeshDescriptor()
            let vertexSource = geometry.vertices
            let faces = geometry.faces

            // Convert vertices to SIMD3<Float> - direct buffer access
            var positions: [SIMD3<Float>] = []
            let vertexCount = vertexSource.count
            let vertexStride = vertexSource.stride
            let vertexBuffer = vertexSource.buffer

            // ✅ CRITICAL: Guard against excessive vertex count
            guard vertexCount > 0 && vertexCount < 100000 else {
                print("⚠️ Invalid vertex count: \(vertexCount)")
                return ModelEntity()
            }

            for i in 0..<vertexCount {
                // ✅ CRITICAL: Must include initial offset from vertexSource
                let offset = vertexSource.offset + (i * vertexStride)

                // ✅ CRITICAL: Bounds check
                guard offset + MemoryLayout<SIMD3<Float>>.stride <= vertexBuffer.length else {
                    print("⚠️ Vertex buffer overflow at index \(i)")
                    break
                }

                let vertex = vertexBuffer.contents().advanced(by: offset).assumingMemoryBound(to: SIMD3<Float>.self).pointee

                // ✅ CRITICAL: Validate vertex data
                guard vertex.x.isFinite && vertex.y.isFinite && vertex.z.isFinite else {
                    continue  // Skip invalid vertices
                }

                positions.append(vertex)
            }

            // Convert faces to triangles - direct buffer access
            var indices: [UInt32] = []
            let faceCount = faces.count
            let faceBuffer = faces.buffer

            // ✅ CRITICAL: Guard against excessive face count
            guard faceCount > 0 && faceCount < 200000 else {
                print("⚠️ Invalid face count: \(faceCount)")
                return ModelEntity()
            }

            for i in 0..<faceCount {
                // ✅ CRITICAL: Must include initial offset from faces
                let faceIndex = faces.offset + (i * faces.indexCountPerPrimitive * MemoryLayout<UInt32>.stride)

                // ✅ CRITICAL: Bounds check for face buffer
                guard faceIndex + (faces.indexCountPerPrimitive * MemoryLayout<UInt32>.stride) <= faceBuffer.length else {
                    print("⚠️ Face buffer overflow at index \(i)")
                    break
                }

                let face = faceBuffer.contents().advanced(by: faceIndex).assumingMemoryBound(to: UInt32.self)

                // ✅ CRITICAL: Validate indices are within vertex array bounds
                let idx0 = face[0]
                let idx1 = face[1]
                let idx2 = face[2]

                guard idx0 < positions.count && idx1 < positions.count && idx2 < positions.count else {
                    continue  // Skip invalid faces
                }

                indices.append(idx0)
                indices.append(idx1)
                indices.append(idx2)
            }

            meshDescriptor.positions = MeshBuffer(positions)
            meshDescriptor.primitives = .triangles(indices)

            // Create mesh resource
            let meshResource: MeshResource
            do {
                meshResource = try MeshResource.generate(from: [meshDescriptor])
            } catch {
                print("Failed to create mesh resource: \(error)")
                return ModelEntity()
            }

            // Create material (semi-transparent green during scanning)
            var material = SimpleMaterial()
            material.color = .init(tint: .green.withAlphaComponent(0.3))
            material.roughness = .float(0.8)

            // Create entity
            let entity = ModelEntity(mesh: meshResource, materials: [material])
            return entity
        }

        private func createBoundsVisualizer(bounds: SIMD3<Float>) -> AnchorEntity {
            let anchor = AnchorEntity(world: .zero)

            // Create corner markers
            let dimensions: [Float] = [-1, 1]
            let size: Float = 0.02
            let length: Float = 0.08

            for x in dimensions {
                for y in dimensions {
                    for z in dimensions {
                        let position = SIMD3<Float>(x, y, z)
                        addCornerMarker(to: anchor, at: position, bounds: bounds, size: size, length: length)
                    }
                }
            }

            return anchor
        }

        private func addCornerMarker(to parent: Entity, at position: SIMD3<Float>, bounds: SIMD3<Float>, size: Float, length: Float) {
            // Create three bars for each corner (X, Y, Z axes)
            let axes: [SIMD3<Float>] = [
                SIMD3<Float>(1, 0, 0),  // X-axis
                SIMD3<Float>(0, 1, 0),  // Y-axis
                SIMD3<Float>(0, 0, 1)   // Z-axis
            ]

            for axis in axes {
                let barSize = SIMD3<Float>(size, size, size) * (SIMD3<Float>(1, 1, 1) - axis) +
                              SIMD3<Float>(length, length, length) * axis

                let mesh = MeshResource.generateBox(
                    width: barSize.x,
                    height: barSize.y,
                    depth: barSize.z
                )

                var material = SimpleMaterial()
                material.color = .init(tint: .blue)
                material.metallic = .float(0.8)

                let entity = ModelEntity(mesh: mesh, materials: [material])
                entity.position = position * bounds / 2 - barSize / 2 * position
                parent.addChild(entity)
            }
        }

        // MARK: - Metal Helper Methods

        /// ✅ METAL OPTIMIZATION: Convert camera image CVPixelBuffer to MTLTexture (BGRA format)
        /// Useful for GPU-based image processing or texture mapping on mesh
        func makeColorTextureFromPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> MTLTexture? {
            guard let cache = cvTextureCache, let _ = metalDevice else {
                return nil
            }
            // TODO: Use metalDevice for GPU-based color texture processing

            let width = CVPixelBufferGetWidth(pixelBuffer)
            let height = CVPixelBufferGetHeight(pixelBuffer)
            var cvTexOut: CVMetalTexture?

            let status = CVMetalTextureCacheCreateTextureFromImage(
                kCFAllocatorDefault,
                cache,
                pixelBuffer,
                nil,
                .bgra8Unorm, // Camera image format
                width,
                height,
                0,
                &cvTexOut
            )

            if status != kCVReturnSuccess {
                return nil
            }

            guard let cvTex = cvTexOut,
                  let texture = CVMetalTextureGetTexture(cvTex) else {
                return nil
            }

            return texture
        }
    }
}
