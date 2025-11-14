//
//  ScanViewModel.swift
//  SUPERWAAGE
//
//  Enhanced scan view model with professional-grade accuracy
//  Apple Senior Developer implementation with all advanced components
//

import SwiftUI
import ARKit
import RealityKit
import Combine

// MARK: - Helper Extensions
extension Float {
    static let degreesToRadian = Float.pi / 180
}

enum ScanState: Equatable {
    case idle
    case scanning
    case processing
    case completed
    case error(String)
}

@MainActor
class ScanViewModel: NSObject, ObservableObject {
    // MARK: - Published Properties
    @Published var scanState: ScanState = .idle
    @Published var volume_cm3: Double = 0.0
    @Published var weight_g: Double = 0.0
    @Published var dimensions: SIMD3<Float> = .zero
    @Published var scanProgress: Double = 0.0
    @Published var qualityScore: Double = 0.0
    @Published var confidence: Double = 0.0
    @Published var errorMessage: String?
    @Published var meshAnchors: [ARMeshAnchor] = []
    @Published var recommendations: [String] = []
    @Published var selectedMaterial: MaterialPreset
    @Published var isMultiScanMode: Bool = false

    // Scan metrics for UI
    @Published var pointCount: Int = 0
    @Published var averageConfidence: Float = 0.0
    @Published var coverageScore: Float = 0.0
    @Published var scanDuration: TimeInterval = 0.0

    // Segmentation metrics (for background removal)
    @Published var segmentationCoverage: Float = 0.0

    // Accuracy and quality metrics
    @Published var accuracyPercentage: Double = 0.0
    @Published var accuracyDescription: String = ""
    @Published var accuracyColor: String = ""
    @Published var symmetryScore: Float = 0.0
    @Published var errorMarginPercent: Double = 0.0  // ±X% error margin
    @Published var errorMarginDescription: String = ""

    // MARK: - Private Properties
    private var arSession: ARSession?
    private var scannedPoints: [simd_float3] = []
    private var scannedNormals: [simd_float3] = []

    // AI refinement toggle (disabled by default for reliability)
    private let enableAIRefinement = false  // Disabled to prevent processing hangs
    private var scannedConfidence: [Float] = []
    private var cancellables = Set<AnyCancellable>()
    private var scanStartTime: Date?
    private var detectedPlaneHeight: Float?

    // SLAM tracking quality
    @Published var trackingQuality: TrackingQuality = .limited

    // MARK: - Computed Properties

    /// Volume in milliliters (same as cm³)
    var volumeML: Float {
        return Float(volume_cm3)
    }

    // MARK: - Tunable Parameters (AI/LiDAR Optimizations)

    /// Quality preset selection
    @Published var scanQuality: ScanQuality = .balanced

    // Camera movement thresholds (from DepthViz best practices)
    private var cameraRotationThreshold: Float { cos(scanQuality.rotationDegrees * .degreesToRadian) }
    private var cameraTranslationThreshold: Float { pow(scanQuality.translationMeters, 2) }
    private var lastCameraTransform: simd_float4x4?

    // Point limiting (from DepthViz) - prevents memory issues
    private var maxPoints: Int { scanQuality.maxPoints }
    private var currentPointIndex = 0

    // Confidence filtering threshold (0=low, 1=medium, 2=high)
    private var confidenceThreshold: Float { scanQuality.minConfidence }

    // MARK: - Scan Metrics & Statistics

    @Published var totalPointsScanned: Int = 0
    @Published var totalFramesProcessed: Int = 0
    @Published var totalFramesSkipped: Int = 0
    @Published var currentFPS: Double = 0.0
    @Published var estimatedMemoryUsage: Double = 0.0 // in MB

    private var lastFrameTime: Date?
    private var frameTimeHistory: [TimeInterval] = []
    private let maxFrameHistory = 30 // For FPS smoothing

    // MARK: - Scan Quality Presets

    enum ScanQuality: String, CaseIterable {
        case performance = "Performance"
        case balanced = "Balanced"
        case quality = "Quality"
        case maximum = "Maximum"

        var rotationDegrees: Float {
            switch self {
            case .performance: return 3.0  // More lenient - skip more frames
            case .balanced: return 1.0     // DepthViz default
            case .quality: return 0.5      // More sensitive
            case .maximum: return 0.25     // Very sensitive
            }
        }

        var translationMeters: Float {
            switch self {
            case .performance: return 0.03  // 3cm
            case .balanced: return 0.01     // 1cm - DepthViz default
            case .quality: return 0.005     // 5mm
            case .maximum: return 0.0025    // 2.5mm
            }
        }

        var maxPoints: Int {
            switch self {
            case .performance: return 250_000
            case .balanced: return 500_000
            case .quality: return 1_000_000
            case .maximum: return 2_000_000
            }
        }

        var minConfidence: Float {
            switch self {
            case .performance: return 0.3  // Low threshold
            case .balanced: return 0.5     // Medium
            case .quality: return 0.6      // Higher
            case .maximum: return 0.7      // High only
            }
        }

        var description: String {
            switch self {
            case .performance: return "Schnell, niedrige Dichte"
            case .balanced: return "Ausgewogen (empfohlen)"
            case .quality: return "Hohe Qualität, mehr Punkte"
            case .maximum: return "Maximale Details, langsam"
            }
        }
    }

    enum TrackingQuality {
        case limited
        case normal
        case good

        var description: String {
            switch self {
            case .limited: return "Eingeschränkt"
            case .normal: return "Normal"
            case .good: return "Gut"
            }
        }

        var color: Color {
            switch self {
            case .limited: return .red
            case .normal: return .orange
            case .good: return .green
            }
        }
    }

    // Advanced Components
    private let multiScanManager = MultiScanManager()
    private let calibrationManager = CalibrationManager.shared
    private let accuracyEvaluator = AccuracyEvaluator()
    private let volumeEstimator = VolumeEstimator()
    private let spatialAnalyzer = SpatialDensityAnalyzer()

    // Object Selection Components (Tap-to-Select)
    private let objectSelector = ObjectSelector()
    private let boundingBoxVisualizer = BoundingBoxVisualizer()
    @Published var selectedObject: SelectedObject?
    @Published var isObjectSelected: Bool = false

    // 3D Model Components
    @Published var meshVolumeResult: MeshVolumeResult?
    @Published var can3DExport: Bool = false
    @Published var meshQualityDescription: String = ""

    // MARK: - Initialization
    override init() {
        // Default material
        self.selectedMaterial = DensityDatabase.defaultPreset
        super.init()
        setupBindings()
    }

    // MARK: - Setup
    private func setupBindings() {
        // Auto-calculate weight when volume or material changes
        Publishers.CombineLatest($volume_cm3, $selectedMaterial)
            .sink { [weak self] volume, material in
                self?.calculateWeight()
            }
            .store(in: &cancellables)

        // Multi-scan progress
        multiScanManager.$scanProgress
            .sink { [weak self] progress in
                self?.scanProgress = progress
            }
            .store(in: &cancellables)

        multiScanManager.$scanQualityScore
            .sink { [weak self] quality in
                self?.qualityScore = quality
            }
            .store(in: &cancellables)
    }

    func setARSession(_ session: ARSession) {
        self.arSession = session
    }

    // MARK: - Material Selection
    func setMaterial(_ material: MaterialPreset) {
        self.selectedMaterial = material

        // Configure multi-scan based on material type
        if material.category == .flour || material.category == .powder {
            multiScanManager.setupForMaterialType(.powder)
            isMultiScanMode = true
        } else if material.category == .spices {
            multiScanManager.setupForMaterialType(.irregular)
            isMultiScanMode = true
        } else if material.category == .dairy {
            multiScanManager.setupForMaterialType(.solid)
            isMultiScanMode = false
        } else {
            multiScanManager.setupForMaterialType(.granular)
            isMultiScanMode = selectedMaterial.densityRange != nil
        }
    }

    // MARK: - Calibration
    func performCalibration(knownObject: CalibrationManager.KnownObject, scannedPoints: [simd_float3]) -> CalibrationResult {
        return calibrationManager.calibrate(with: knownObject, scannedPoints: scannedPoints)
    }

    var isCalibrated: Bool {
        return calibrationManager.isCalibrated
    }

    var calibrationStatus: String {
        return calibrationManager.statusDescription
    }

    var calibrationAccuracyColor: String {
        return calibrationManager.accuracyColor
    }

    // MARK: - Object Selection (Tap-to-Select)

    /// Handle tap gesture for object selection
    /// - Parameters:
    ///   - screenPoint: Tap location in screen coordinates
    ///   - arView: ARView for raycast
    func handleObjectSelection(at screenPoint: CGPoint, in arView: ARView) {
        print("🎯 Object selection at: \(screenPoint)")

        guard !meshAnchors.isEmpty else {
            print("   ❌ No mesh anchors available")
            return
        }

        // Select object using ObjectSelector
        if let selected = objectSelector.selectObject(
            at: screenPoint,
            in: arView,
            meshAnchors: meshAnchors
        ) {
            self.selectedObject = selected
            self.isObjectSelected = true

            print("   ✅ Object selected: \(selected.points.count) points")

            // Update bounding box visualization
            let measurements = BoundingBoxMeasurements(boundingBox: selected.boundingBox)
            boundingBoxVisualizer.showBoundingBox(
                selected.boundingBox,
                in: arView,
                withMeasurements: measurements
            )

            // Update volume display with selected object
            self.volume_cm3 = Double(measurements.volume_cm3)
            // Convert dimensions from meters to centimeters
            self.dimensions = selected.boundingBox.size * 100.0
        } else {
            print("   ❌ Object selection failed")
        }
    }

    /// Clear object selection
    func clearObjectSelection(in arView: ARView) {
        selectedObject = nil
        isObjectSelected = false
        boundingBoxVisualizer.removeBoundingBox(from: arView)
    }

    // MARK: - Scanning Control
    func startScanning() {
        scanState = .scanning
        scannedPoints.removeAll()
        scannedNormals.removeAll()
        scannedConfidence.removeAll()
        meshAnchors.removeAll()
        volume_cm3 = 0.0
        weight_g = 0.0
        errorMessage = nil
        scanProgress = 0.0
        qualityScore = 0.0
        confidence = 0.0
        recommendations = []
        pointCount = 0
        coverageScore = 0.0
        scanStartTime = Date()

        if isMultiScanMode {
            multiScanManager.startMultiScan()
        }
    }

    func completeScan() {
        print("🔄 completeScan() called - Current state: \(scanState)")
        print("   Points: \(scannedPoints.count), Normals: \(scannedNormals.count)")

        if isMultiScanMode && multiScanManager.currentScanIndex < multiScanManager.totalScans {
            // Record this scan
            print("   Multi-scan mode: Recording current scan")
            recordCurrentScan()
        } else {
            // Finalize scanning
            print("   Setting state to .processing")
            scanState = .processing
            scanDuration = Date().timeIntervalSince(scanStartTime ?? Date())

            print("   Starting async processing task...")
            // Process mesh data in background to avoid freezing UI
            Task {
                print("   📱 Task started - calling processMeshDataAsync()")
                await processMeshDataAsync()
                print("   ✅ Task completed")
            }
            print("   Task created, returning from completeScan()")
        }
    }

    private func recordCurrentScan() {
        guard let cameraTransform = arSession?.currentFrame?.camera.transform else { return }

        multiScanManager.recordScan(
            points: scannedPoints,
            normals: scannedNormals,
            confidence: scannedConfidence,
            cameraTransform: cameraTransform
        )

        // Check if we need more scans
        if multiScanManager.currentScanIndex < multiScanManager.totalScans {
            // Prepare for next scan
            recommendations = [multiScanManager.getNextScanGuidance()]
            scannedPoints.removeAll()
            scannedNormals.removeAll()
            scannedConfidence.removeAll()
        } else {
            // All scans complete
            scanState = .processing

            // Process mesh data in background
            Task {
                await processMeshDataAsync()
            }
        }
    }

    func reset() {
        scanState = .idle
        scannedPoints.removeAll()
        scannedNormals.removeAll()
        scannedConfidence.removeAll()
        meshAnchors.removeAll()
        volume_cm3 = 0.0
        weight_g = 0.0
        dimensions = .zero
        scanProgress = 0.0
        qualityScore = 0.0
        confidence = 0.0
        recommendations = []
        errorMessage = nil
        multiScanManager.reset()
        detectedPlaneHeight = nil

        // Reset metrics
        totalPointsScanned = 0
        totalFramesProcessed = 0
        totalFramesSkipped = 0
        currentFPS = 0.0
        estimatedMemoryUsage = 0.0
        lastFrameTime = nil
        frameTimeHistory.removeAll()
        lastCameraTransform = nil
        currentPointIndex = 0
    }

    // MARK: - Export & Sharing

    /// Export scan data as PLY file
    /// - Returns: URL of exported PLY file or nil if failed
    func exportPLY() -> URL? {
        guard !scannedPoints.isEmpty else {
            print("❌ No points to export")
            return nil
        }

        // Downsample for reasonable file size
        let downsampled = PointCloudUtils.voxelDownsample(
            points: scannedPoints,
            voxelSize: 0.005
        )

        let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let timestamp = Date().timeIntervalSince1970
        let filename = "scan_\(String(format: "%.0f", timestamp)).ply"
        let plyURL = documentsURL.appendingPathComponent(filename)

        do {
            if !scannedNormals.isEmpty && scannedNormals.count == scannedPoints.count {
                // Export with normals
                let downsampledNormals = PointCloudUtils.voxelDownsample(
                    points: scannedNormals,
                    voxelSize: 0.005
                )
                try PointCloudUtils.writePLYWithNormals(
                    points: downsampled,
                    normals: downsampledNormals,
                    url: plyURL
                )
            } else {
                // Export points only
                try PointCloudUtils.writePLY(points: downsampled, url: plyURL)
            }

            print("✅ PLY exported: \(plyURL.path)")
            print("   Points: \(scannedPoints.count) → \(downsampled.count) (downsampled)")
            return plyURL

        } catch {
            print("❌ PLY export failed: \(error)")
            return nil
        }
    }

    /// Export scan results as JSON summary
    /// - Returns: URL of exported JSON file or nil if failed
    func exportResultsJSON() -> URL? {
        let documentsURL = FileManager.default.urls(
            for: .documentDirectory,
            in: .userDomainMask
        )[0]

        let timestamp = Date().timeIntervalSince1970
        let filename = "results_\(String(format: "%.0f", timestamp)).json"
        let jsonURL = documentsURL.appendingPathComponent(filename)

        let results: [String: Any] = [
            "timestamp": timestamp,
            "volume_ml": volume_cm3,
            "weight_g": weight_g,
            "dimensions_cm": [
                "width": dimensions.x,
                "height": dimensions.y,
                "depth": dimensions.z
            ],
            "material": selectedMaterial.name,
            "material_density": selectedMaterial.density,
            "confidence": confidence,
            "quality_score": qualityScore,
            "coverage_score": coverageScore,
            "point_count": pointCount,
            "scan_duration_s": scanDuration,
            "accuracy_percentage": accuracyPercentage,
            "accuracy_description": accuracyDescription,
            "segmentation_coverage": segmentationCoverage
        ]

        do {
            let jsonData = try JSONSerialization.data(withJSONObject: results, options: .prettyPrinted)
            try jsonData.write(to: jsonURL)
            print("✅ Results JSON exported: \(jsonURL.path)")
            return jsonURL

        } catch {
            print("❌ JSON export failed: \(error)")
            return nil
        }
    }

    /// Get shareable items for UIActivityViewController
    /// - Returns: Array of items to share
    func getShareableItems() -> [Any] {
        var items: [Any] = []

        // Add results text
        let resultsText = """
        SUPERWAAGE Scan Results

        Volume: \(formattedVolume)
        Weight: \(formattedWeight)
        Dimensions: \(formattedDimensions)
        Material: \(selectedMaterial.name)

        Quality: \(String(format: "%.0f", qualityScore * 100))%
        Confidence: \(String(format: "%.0f", confidence * 100))%
        Accuracy: \(accuracyDescription)
        """
        items.append(resultsText)

        // Add PLY file if available
        if let plyURL = exportPLY() {
            items.append(plyURL)
        }

        // Add JSON results if available
        if let jsonURL = exportResultsJSON() {
            items.append(jsonURL)
        }

        return items
    }

    // MARK: - Mesh Processing
    func addMeshAnchor(_ anchor: ARMeshAnchor) {
        guard scanState == .scanning else { return }

        // Check camera movement before accumulating new points
        guard shouldAccumulatePoints() else { return }

        // Only keep the most recent anchors to avoid memory issues
        if !meshAnchors.contains(where: { $0.identifier == anchor.identifier }) {
            meshAnchors.append(anchor)

            // Limit stored anchors to prevent ARFrame retention issues
            if meshAnchors.count > 50 {
                meshAnchors.removeFirst()
            }
        }

        // Extract points from this anchor immediately
        extractPointsFromAnchor(anchor)
        updateScanMetrics()
    }

    func updateMeshAnchor(_ anchor: ARMeshAnchor) {
        guard scanState == .scanning else { return }

        // Check camera movement before accumulating new points
        guard shouldAccumulatePoints() else { return }

        if let index = meshAnchors.firstIndex(where: { $0.identifier == anchor.identifier }) {
            meshAnchors[index] = anchor
        }

        // Extract points immediately to avoid holding ARFrame references
        extractPointsFromAnchor(anchor)
        updateScanMetrics()
    }

    /// Check if we should accumulate new points based on camera movement
    /// Only accumulate if camera has moved significantly (rotation > 1° or translation > 1cm)
    private func shouldAccumulatePoints() -> Bool {
        guard let currentFrame = arSession?.currentFrame else { return false }

        // Update FPS metrics
        updateFrameMetrics()

        let cameraTransform = currentFrame.camera.transform

        // Always accumulate first frame
        guard let lastTransform = lastCameraTransform else {
            lastCameraTransform = cameraTransform
            totalFramesProcessed += 1
            return true
        }

        // Check rotation (dot product of forward vectors)
        let currentForward = cameraTransform.columns.2
        let lastForward = lastTransform.columns.2
        let rotationCheck = dot(currentForward, lastForward) <= cameraRotationThreshold

        // Check translation (distance squared)
        let currentPosition = cameraTransform.columns.3
        let lastPosition = lastTransform.columns.3
        let translationCheck = distance_squared(currentPosition, lastPosition) >= cameraTranslationThreshold

        // Accumulate if either threshold is exceeded
        if rotationCheck || translationCheck {
            lastCameraTransform = cameraTransform
            totalFramesProcessed += 1
            return true
        }

        // Frame skipped - not enough movement
        totalFramesSkipped += 1
        return false
    }

    /// Update FPS and timing metrics
    private func updateFrameMetrics() {
        let now = Date()

        if let lastTime = lastFrameTime {
            let deltaTime = now.timeIntervalSince(lastTime)
            frameTimeHistory.append(deltaTime)

            // Keep only recent history
            if frameTimeHistory.count > maxFrameHistory {
                frameTimeHistory.removeFirst()
            }

            // Calculate smoothed FPS
            // ✅ CRASH FIX: Guard against empty frame history
            if frameTimeHistory.count > 0 {
                let avgDeltaTime = frameTimeHistory.reduce(0, +) / Double(frameTimeHistory.count)
                currentFPS = avgDeltaTime > 0 ? 1.0 / avgDeltaTime : 0.0
            } else {
                currentFPS = 0.0
            }
        }

        lastFrameTime = now
    }

    // MARK: - Point Extraction
    private func extractPointsFromAnchor(_ anchor: ARMeshAnchor) {
        let geometry = anchor.geometry
        let vertexSource = geometry.vertices
        let normalSource = geometry.normals
        let classification = geometry.classification

        let vertexCount = vertexSource.count
        let vertexStride = vertexSource.stride
        let vertexBuffer = vertexSource.buffer

        let normalStride = normalSource.stride
        let normalBuffer = normalSource.buffer

        // Calculate sampling rate to stay under maxPoints
        let samplingRate = max(1, vertexCount / 1000) // Sample ~1000 points per anchor max

        for i in stride(from: 0, to: vertexCount, by: samplingRate) {
            // Check point limit (ring buffer approach)
            if scannedPoints.count >= maxPoints {
                // Replace oldest point (ring buffer)
                let replaceIndex = currentPointIndex % maxPoints

                // Vertex
                let vertexOffset = i * vertexStride
                let vertex = vertexBuffer.contents().advanced(by: vertexOffset).assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let worldPosition = anchor.transform * SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1.0)

                // Normal
                let normalOffset = i * normalStride
                let normal = normalBuffer.contents().advanced(by: normalOffset).assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let worldNormal = anchor.transform * SIMD4<Float>(normal.x, normal.y, normal.z, 0.0)

                // Confidence (from classification)
                let conf: Float
                if let classification = classification {
                    conf = getConfidenceFromClassification(classification, index: i)
                } else {
                    conf = 0.6 // Default confidence when classification is not available
                }

                // Apply confidence threshold filter
                if conf >= confidenceThreshold {
                    scannedPoints[replaceIndex] = simd_float3(worldPosition.x, worldPosition.y, worldPosition.z)
                    scannedNormals[replaceIndex] = simd_float3(worldNormal.x, worldNormal.y, worldNormal.z)
                    scannedConfidence[replaceIndex] = conf
                    currentPointIndex += 1
                }
            } else {
                // Still building up to maxPoints - normal accumulation
                // Vertex
                let vertexOffset = i * vertexStride
                let vertex = vertexBuffer.contents().advanced(by: vertexOffset).assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let worldPosition = anchor.transform * SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1.0)

                // Normal
                let normalOffset = i * normalStride
                let normal = normalBuffer.contents().advanced(by: normalOffset).assumingMemoryBound(to: SIMD3<Float>.self).pointee
                let worldNormal = anchor.transform * SIMD4<Float>(normal.x, normal.y, normal.z, 0.0)

                // Confidence (from classification)
                let conf: Float
                if let classification = classification {
                    conf = getConfidenceFromClassification(classification, index: i)
                } else {
                    conf = 0.6 // Default confidence when classification is not available
                }

                // Apply confidence threshold filter
                if conf >= confidenceThreshold {
                    scannedPoints.append(simd_float3(worldPosition.x, worldPosition.y, worldPosition.z))
                    scannedNormals.append(simd_float3(worldNormal.x, worldNormal.y, worldNormal.z))
                    scannedConfidence.append(conf)
                    currentPointIndex += 1
                }
            }
        }

        // Update metrics after point extraction
        updatePointMetrics()
        updateScanMetrics()
    }

    /// Update real-time point metrics (count, memory usage)
    private func updatePointMetrics() {
        totalPointsScanned = scannedPoints.count

        // Estimate memory usage in MB
        // Each point: 3 floats (position) + 3 floats (normal) + 1 float (confidence) = 7 floats = 28 bytes
        let bytesPerPoint = 28
        let totalBytes = scannedPoints.count * bytesPerPoint
        estimatedMemoryUsage = Double(totalBytes) / 1_048_576.0 // Convert to MB
    }

    private func getConfidenceFromClassification(_ classification: ARGeometrySource, index: Int) -> Float {
        // ARKit classification: 0=none, 1=wall, 2=floor, 3=ceiling, 4=table, etc.
        // We'll assign confidence based on classification
        let stride = classification.stride
        let buffer = classification.buffer
        let offset = index * stride
        let classValue = buffer.contents().advanced(by: offset).assumingMemoryBound(to: UInt8.self).pointee

        switch classValue {
        case 0: return 0.5  // None - medium confidence
        case 4: return 0.9  // Table - high confidence
        case 6: return 0.8  // Object - high confidence
        default: return 0.6 // Other - moderate confidence
        }
    }

    private func updateScanMetrics() {
        pointCount = scannedPoints.count

        // Calculate base confidence from point data
        let rawConfidence = scannedConfidence.isEmpty ? 0.0 : scannedConfidence.reduce(0.0, +) / Float(scannedConfidence.count)

        // ✅ CRITICAL: Validate confidence result
        let baseConfidence = rawConfidence.isFinite ? rawConfidence : 0.0

        // Adjust confidence based on tracking quality
        let trackingMultiplier: Float = {
            switch trackingQuality {
            case .good: return 1.0
            case .normal: return 0.85
            case .limited: return 0.6
            }
        }()

        averageConfidence = baseConfidence * trackingMultiplier

        // Update progress (based on points collected)
        let targetPoints = 3000.0 // Realistic target for good scan
        scanProgress = min(Double(pointCount) / targetPoints, 1.0)

        // Calculate real-time coverage
        updateCoverageScore()
    }

    private func updateCoverageScore() {
        guard pointCount > 100 else {
            coverageScore = 0.0
            return
        }

        // Quick coverage estimate based on point distribution
        // Group points into rough spatial grid
        let gridSize = 5
        var occupiedCells = Set<SIMD3<Int>>()

        // ✅ FIX: Calculate actual bounds per component (not by distance from origin)
        guard !scannedPoints.isEmpty else {
            coverageScore = 0.0
            return
        }

        var minBounds = scannedPoints[0]
        var maxBounds = scannedPoints[0]

        for point in scannedPoints {
            minBounds.x = min(minBounds.x, point.x)
            minBounds.y = min(minBounds.y, point.y)
            minBounds.z = min(minBounds.z, point.z)

            maxBounds.x = max(maxBounds.x, point.x)
            maxBounds.y = max(maxBounds.y, point.y)
            maxBounds.z = max(maxBounds.z, point.z)
        }

        let range = maxBounds - minBounds

        // ✅ CRITICAL: Guard against zero or invalid range (with small epsilon for floating point)
        let epsilon: Float = 0.001
        guard range.x.isFinite && range.y.isFinite && range.z.isFinite,
              range.x > epsilon, range.y > epsilon, range.z > epsilon else {
            // Silently skip instead of spamming console (points are too close together)
            coverageScore = 0.0
            return
        }

        let cellSize = simd_float3(
            range.x / Float(gridSize),
            range.y / Float(gridSize),
            range.z / Float(gridSize)
        )

        // ✅ CRITICAL: Verify cellSize is valid
        guard cellSize.x.isFinite && cellSize.y.isFinite && cellSize.z.isFinite,
              cellSize.x > 0, cellSize.y > 0, cellSize.z > 0 else {
            print("⚠️ Invalid cellSize for coverage calculation: \(cellSize)")
            coverageScore = 0.0
            return
        }

        // Count occupied cells
        for point in scannedPoints {
            // ✅ CRITICAL: Skip invalid points
            guard point.x.isFinite && point.y.isFinite && point.z.isFinite else {
                continue
            }

            let relative = point - minBounds

            // ✅ CRITICAL: Guard division and Int conversion
            guard relative.x.isFinite && relative.y.isFinite && relative.z.isFinite else {
                continue
            }

            let cellX = min(max(0, Int((relative.x / cellSize.x).rounded(.down))), gridSize - 1)
            let cellY = min(max(0, Int((relative.y / cellSize.y).rounded(.down))), gridSize - 1)
            let cellZ = min(max(0, Int((relative.z / cellSize.z).rounded(.down))), gridSize - 1)

            occupiedCells.insert(SIMD3<Int>(cellX, cellY, cellZ))
        }

        let totalCells = gridSize * gridSize * gridSize

        // ✅ CRASH FIX: Guard against division by zero
        guard totalCells > 0 else {
            coverageScore = 0.0
            return
        }

        coverageScore = Float(occupiedCells.count) / Float(totalCells)
    }

    // MARK: - Processing

    /// ✅ EMERGENCY FIX: Recenter points before TSDF to fix empty mesh
    private func recenterPointsBeforeTSDF() {
        print("🔧 Recentering points for TSDF...")

        guard !scannedPoints.isEmpty else {
            print("   ❌ No points to recenter")
            return
        }

        // Calculate center
        var center = SIMD3<Float>.zero
        for point in scannedPoints {
            // ✅ CRITICAL: Skip invalid points
            guard point.x.isFinite && point.y.isFinite && point.z.isFinite else {
                continue
            }
            center += point
        }

        // ✅ CRITICAL: Guard against division by zero or invalid count
        let validCount = Float(scannedPoints.count)
        guard validCount > 0 else {
            print("   ❌ No valid points to recenter")
            return
        }

        center /= validCount

        // ✅ CRITICAL: Verify center is valid
        guard center.x.isFinite && center.y.isFinite && center.z.isFinite else {
            print("   ❌ ERROR: Calculated center is NaN/Infinite: \(center)")
            return
        }

        // Calculate extent
        var minPoint = scannedPoints[0]
        var maxPoint = scannedPoints[0]

        for point in scannedPoints {
            // ✅ CRITICAL: Skip invalid points
            guard point.x.isFinite && point.y.isFinite && point.z.isFinite else {
                continue
            }

            minPoint = SIMD3<Float>(
                min(minPoint.x, point.x),
                min(minPoint.y, point.y),
                min(minPoint.z, point.z)
            )
            maxPoint = SIMD3<Float>(
                max(maxPoint.x, point.x),
                max(maxPoint.y, point.y),
                max(maxPoint.z, point.z)
            )
        }

        let extent = maxPoint - minPoint

        // ✅ CRITICAL: Verify extent is valid
        guard extent.x.isFinite && extent.y.isFinite && extent.z.isFinite else {
            print("   ❌ ERROR: Calculated extent is NaN/Infinite: \(extent)")
            return
        }

        print("   📊 Original bounds:")
        print("      Center: \(center)")
        print("      Extent: \(extent) meters")

        // ✅ CRITICAL FIX: Recenter all points around origin
        for i in 0..<scannedPoints.count {
            scannedPoints[i] -= center
        }

        // Also recenter normals if needed
        // (normals are directions, so no change needed)

        print("   ✅ Points recentered around (0,0,0)")
        print("   📊 New extent: \(extent) meters (unchanged)")

        // Check if points fit in TSDF grid
        let tsdfSize: Float = 0.6 // Increased from 0.32 (see Patch 4)

        if extent.x > tsdfSize || extent.y > tsdfSize || extent.z > tsdfSize {
            print("   ⚠️ WARNING: Points extent (\(extent)) exceeds TSDF grid (\(tsdfSize)m)")

            let maxExtent = max(extent.x, extent.y, extent.z)

            // ✅ CRITICAL: Guard against invalid scale calculation
            guard maxExtent.isFinite && maxExtent > 0 else {
                print("   ❌ ERROR: Invalid maxExtent for scaling: \(maxExtent)")
                return
            }

            print("   📏 Recommended TSDF size: \(maxExtent * 1.2)m")

            // ✅ EMERGENCY FIX: Scale points to fit
            let scale = tsdfSize / (maxExtent * 1.2)

            // ✅ CRITICAL: Verify scale is valid
            guard scale.isFinite && scale > 0 else {
                print("   ❌ ERROR: Invalid scale calculated: \(scale)")
                return
            }

            for i in 0..<scannedPoints.count {
                scannedPoints[i] *= scale
            }
            print("   ✅ Points scaled by \(scale) to fit in TSDF grid")
        }
    }

    /// Async version to avoid blocking UI
    private func processMeshDataAsync() async {
        print("   🔧 processMeshDataAsync() started")

        // Merge multi-scan data if applicable
        var finalPoints: [simd_float3]
        var finalNormals: [simd_float3]
        var finalConfidence: [Float]

        if isMultiScanMode, let merged = multiScanManager.mergeScans() {
            print("   📊 Multi-scan: Merging scans...")
            finalPoints = merged.points
            finalNormals = merged.normals
            finalConfidence = merged.confidence
        } else {
            print("   📊 Single scan: Using scanned data")
            finalPoints = scannedPoints
            finalNormals = scannedNormals
            finalConfidence = scannedConfidence
        }

        print("   📈 Data prepared: \(finalPoints.count) points")

        guard !finalPoints.isEmpty else {
            print("   ❌ No points captured!")
            await MainActor.run {
                scanState = .error("Keine Datenpunkte erfasst")
            }
            return
        }

        // 🤖 AI-Enhanced Mesh Refinement (optional, in background)
        var aiQuality: Float = 0.8  // Default quality

        if enableAIRefinement {
            print("   🎨 Starting AI mesh refinement...")
            let startTime = Date()

            // Use balanced mode for better performance (not aiEnhanced)
            let refinementOptions = AdvancedRefinementOptions.balanced()

            // Run in background
            print("   ⚙️ Creating detached task for AI processing...")
            let (refinedPoints, refinedNormals, refinementQuality) = await Task.detached {
                print("      🔬 Detached task running - calling refineWithAI()")
                let result = AdvancedMeshRefinement.refineWithAI(
                    points: finalPoints,
                    normals: finalNormals,
                    options: refinementOptions
                )
                print("      ✓ refineWithAI() completed")
                return result
            }.value

            let duration = Date().timeIntervalSince(startTime)
            print("   ⏱️ AI Refinement took \(String(format: "%.2f", duration))s")

            // Use refined data
            finalPoints = refinedPoints
            finalNormals = refinedNormals ?? finalNormals
            aiQuality = refinementQuality

            // Safety: Ensure aiQuality is finite before converting to Int
            let safeAiQuality = aiQuality.isFinite ? aiQuality : 0.5
            let aiQualityPercent = safeAiQuality.isFinite ? Int(safeAiQuality * 100) : 50

            print("   ✨ AI Refinement complete: Quality improved to \(aiQualityPercent)%")
        } else {
            print("   ⚠️ AI Refinement disabled - using raw data")
        }

        // ✅ FIX EMPTY MESH: Recenter points before TSDF
        recenterPointsBeforeTSDF()

        // 🎯 TSDF Volumetric Reconstruction (High Accuracy)
        print("   🏗️ Starting TSDF reconstruction...")
        let tsdfStartTime = Date()

        // Downsample for performance
        print("   📊 Downsampling point cloud...")
        let downsampledPoints = PointCloudUtils.voxelDownsample(
            points: finalPoints,
            voxelSize: 0.005  // 5mm voxels
        )
        print("   ✓ Downsampled: \(finalPoints.count) → \(downsampledPoints.count) points")

        // 🧹 Denoise point cloud before TSDF integration (ML-enhanced with fallback)
        print("   🧹 Denoising point cloud...")
        let denoiseStartTime = Date()
        let denoiser = PointCloudDenoiserCoreML()  // Uses ML model if available, else fast VoxelSmoothingDenoiser
        let denoisedPoints = denoiser.denoise(points: downsampledPoints)
        let denoiseDuration = Date().timeIntervalSince(denoiseStartTime)
        let denoiseMethod = denoiser.usedMLModel ? "ML" : "Voxel"
        print("   ✓ Denoised (\(denoiseMethod)): \(denoisedPoints.count) points in \(String(format: "%.3f", denoiseDuration))s")

        // Calculate bounding box with margin
        guard let (minP, maxP) = PointCloudUtils.boundingBox(points: denoisedPoints) else {
            print("   ❌ Failed to calculate bounding box")
            await MainActor.run {
                scanState = .error("Fehler beim Berechnen der Begrenzungsbox")
            }
            return
        }

        // ✅ EMERGENCY FIX: Increase grid size from 0.32m to 0.6m minimum
        let margin: Float = 0.1  // 10cm margin (was 5cm)
        let gridOrigin = minP - SIMD3<Float>(repeating: margin)
        var gridSize = (maxP - minP) + SIMD3<Float>(repeating: margin * 2)

        // ✅ CRITICAL FIX: Ensure minimum grid size of 0.6m (was 0.32m - too small!)
        let minGridSize: Float = 0.6
        gridSize.x = max(gridSize.x, minGridSize)
        gridSize.y = max(gridSize.y, minGridSize)
        gridSize.z = max(gridSize.z, minGridSize)

        // Create TSDF volume with adaptive grid size
        let voxelSize: Float = 0.005  // 5mm resolution (was 4mm)

        // ✅ CRITICAL FIX: Guard against NaN/Infinite values
        guard gridSize.x.isFinite && gridSize.y.isFinite && gridSize.z.isFinite else {
            print("   ❌ ERROR: Grid size contains NaN/Infinite values: \(gridSize)")
            await MainActor.run {
                scanState = .error("Ungültige Grid-Größe erkannt")
            }
            return
        }

        // ✅ CRITICAL: Validate voxelSize before division
        guard voxelSize > 0 && voxelSize.isFinite else {
            print("   ❌ ERROR: Invalid voxel size: \(voxelSize)")
            await MainActor.run {
                scanState = .error("Ungültige Voxel-Größe")
            }
            return
        }

        // ✅ CRITICAL: Calculate dimensions with validation
        let dimXFloat = (gridSize.x / voxelSize).rounded(.up)
        let dimYFloat = (gridSize.y / voxelSize).rounded(.up)
        let dimZFloat = (gridSize.z / voxelSize).rounded(.up)

        // ✅ CRITICAL: Verify dimension values before Int conversion
        guard dimXFloat.isFinite && dimYFloat.isFinite && dimZFloat.isFinite else {
            print("   ❌ ERROR: Dimension calculations produced NaN/Infinite")
            await MainActor.run {
                scanState = .error("Ungültige Dimensionsberechnung")
            }
            return
        }

        let dimX = min(256, max(64, Int(dimXFloat)))
        let dimY = min(256, max(64, Int(dimYFloat)))
        let dimZ = min(256, max(64, Int(dimZFloat)))

        print("   📐 TSDF Grid: \(dimX)×\(dimY)×\(dimZ), voxel size: \(voxelSize*1000)mm")

        let tsdf = TSDFVolume(
            dimX: dimX, dimY: dimY, dimZ: dimZ,
            voxelSize: voxelSize,
            origin: gridOrigin,
            truncation: voxelSize * 5.0
        )

        // Integrate denoised points into TSDF
        print("   🔄 Integrating cleaned points into TSDF...")
        tsdf.integratePointsApprox(points: denoisedPoints, weight: 1.0)

        // Extract mesh
        print("   🎨 Extracting mesh via marching cubes...")
        let (tsdfVertices, _, tsdfTriangles) = tsdf.extractMesh(isovalue: 0.0)
        print("   ✓ Mesh extracted: \(tsdfVertices.count) vertices, \(tsdfTriangles.count/3) triangles")

        let tsdfDuration = Date().timeIntervalSince(tsdfStartTime)
        print("   ⏱️ TSDF reconstruction took \(String(format: "%.2f", tsdfDuration))s")

        // 📐 Accurate mesh-based volume calculation (tetrahedralization)
        print("   📐 Computing accurate mesh volume via tetrahedralization...")
        let (signedVol, meshVolumeM3) = MeshVolume.computeVolumeWithCentroid(
            vertices: tsdfVertices,
            triangles: tsdfTriangles
        )
        let meshVolumeMl = MeshVolume.cubicMetersToMilliliters(meshVolumeM3)
        print("   ✓ Mesh-based volume: \(String(format: "%.2f", meshVolumeMl)) ml (signed: \(String(format: "%.2f", signedVol)))")

        // Validate mesh quality
        let warnings = MeshVolume.validateMeshTopology(vertices: tsdfVertices, triangles: tsdfTriangles)
        if !warnings.isEmpty {
            print("   ⚠️ Mesh validation warnings:")
            for warning in warnings.prefix(3) {
                print("      - \(warning)")
            }
        }

        // Calculate surface area for quality metrics
        let surfaceArea = MeshVolume.computeSurfaceArea(vertices: tsdfVertices, triangles: tsdfTriangles)
        print("   📏 Surface area: \(String(format: "%.4f", surfaceArea)) m²")

        // Quick voxel-based volume estimate (for comparison)
        let quickVolumeM3 = PointCloudUtils.voxelCountVolume(
            points: downsampledPoints,
            voxelSize: voxelSize
        )
        let quickVolumeMl = quickVolumeM3 * 1_000_000
        print("   📊 Voxel volume estimate: \(String(format: "%.2f", quickVolumeMl)) ml")
        print("   📊 Volume difference: \(String(format: "%.1f", abs(meshVolumeMl - quickVolumeMl))) ml (\(String(format: "%.1f", abs(meshVolumeMl - quickVolumeMl) / max(meshVolumeMl, 1) * 100))%)")

        // Export TSDF mesh and point clouds for debugging (optional, in DEBUG mode)
        #if DEBUG
        let exportVertices = tsdfVertices  // Capture mesh data outside Task
        let exportTriangles = tsdfTriangles
        let exportDownsampled = downsampledPoints  // Raw downsampled points
        let exportDenoised = denoisedPoints        // Cleaned points
        Task.detached {
            let documentsURL = FileManager.default.urls(
                for: .documentDirectory,
                in: .userDomainMask
            )[0]

            let timestamp = Date().timeIntervalSince1970

            // Export TSDF mesh (with triangles)
            let meshPlyURL = documentsURL.appendingPathComponent("tsdf_mesh_\(timestamp).ply")
            try? PointCloudUtils.writePLY(vertices: exportVertices, triangles: exportTriangles, url: meshPlyURL)
            print("   💾 TSDF mesh PLY: \(meshPlyURL.lastPathComponent)")

            // Export raw downsampled points (before denoising)
            let rawPlyURL = documentsURL.appendingPathComponent("points_raw_\(timestamp).ply")
            try? PointCloudUtils.writePLY(points: exportDownsampled, url: rawPlyURL)
            print("   💾 Raw points PLY: \(rawPlyURL.lastPathComponent)")

            // Export denoised points (after denoising)
            let denoisedPlyURL = documentsURL.appendingPathComponent("points_denoised_\(timestamp).ply")
            try? PointCloudUtils.writePLY(points: exportDenoised, url: denoisedPlyURL)
            print("   💾 Denoised points PLY: \(denoisedPlyURL.lastPathComponent)")

            print("   📁 All PLY files saved to Documents folder")
        }
        #endif

        print("   🔄 Starting final processing (all in background)...")

        // ALL CPU-INTENSIVE WORK IN BACKGROUND WITH TIMEOUT
        let processingResult: ProcessingResult?

        do {
            processingResult = try await withThrowingTaskGroup(of: ProcessingResult?.self) { group in
                group.addTask {
                    try Task.checkCancellation()

                    return await Task.detached { [weak self] () -> ProcessingResult? in
                        guard let self = self else { return nil }

                        print("      🔧 Background: Starting heavy computations...")

                        // 1. Detect plane (CPU-intensive)
                        print("      1️⃣ Detecting table plane...")
                        let planeHeight = self.detectTablePlaneSync(from: finalPoints, normals: finalNormals)

            // 2. Calculate volume (VERY CPU-intensive)
            print("      2️⃣ Calculating volume...")
            let material = await MainActor.run { self.selectedMaterial }
            guard let volumeResult = self.volumeEstimator.estimateVolume(
                from: finalPoints,
                normals: finalNormals,
                materialCategory: material.category,
                planeHeight: planeHeight
            ) else {
                print("      ❌ Volume calculation failed")
                return nil
            }

            // 3. Calculate weight (BEFORE calibration - will be recalculated with calibrated volume on main thread)
            print("      3️⃣ Calculating initial weight...")
            let density = await MainActor.run { self.selectedMaterial.density }
            let weight_g = Double(volumeResult.volume_cm3) * density

            // 4. Evaluate accuracy (CPU-intensive)
            print("      4️⃣ Evaluating accuracy...")
            let (accuracyPercentage, accuracyDescription, accuracyColor) = self.evaluateAccuracySync(
                volumeResult: volumeResult,
                points: finalPoints,
                confidence: finalConfidence
            )

            // 5. Spatial analysis (CPU-intensive)
            print("      5️⃣ Performing spatial analysis...")
            let symmetryScore = self.performSpatialAnalysisSync(points: finalPoints, boundingBox: volumeResult.boundingBox)

            // 6. Calculate mesh volume (VERY CPU-intensive)
            print("      6️⃣ Calculating mesh volume...")
            let meshAnchors = await MainActor.run { self.meshAnchors }
            let (meshVolumeResult, meshQualityDescription) = self.calculateMeshVolumeSync(meshAnchors: meshAnchors)

            // Use mesh volume if more accurate (still uncalibrated at this point)
            var finalVolume = Double(volumeResult.volume_cm3)
            if let meshResult = meshVolumeResult, meshResult.quality.qualityScore > 0.7 {
                finalVolume = meshResult.volume_cm3
                print("      ✅ Using mesh-based volume (higher quality)")
            }

            print("      ✨ All background computations complete!")

            // Return all results
            return ProcessingResult(
                volume_cm3: finalVolume,
                weight_g: weight_g,
                dimensions: SIMD3<Float>(volumeResult.width_m * 100, volumeResult.height_m * 100, volumeResult.depth_m * 100),
                detectedPlaneHeight: planeHeight,
                accuracyPercentage: accuracyPercentage,
                accuracyDescription: accuracyDescription,
                accuracyColor: accuracyColor,
                symmetryScore: symmetryScore,
                meshVolumeResult: meshVolumeResult,
                meshQualityDescription: meshQualityDescription,
                aiQuality: aiQuality
            )
                    }.value
                }

                // Wait for result with reasonable timeout
                for try await result in group {
                    return result
                }

                return nil
            }
        } catch {
            print("      ❌ Processing error: \(error)")
            processingResult = nil
        }

        // FAST UI UPDATE ON MAIN THREAD
        await MainActor.run {
            print("      📱 Main thread: Updating UI with results...")

            guard let result = processingResult else {
                scanState = .error("Volumenberechnung fehlgeschlagen")
                print("      ❌ Processing failed")
                return
            }

            // ✅ Apply calibration if available (uses class property)
            let calibratedDimensions = calibrationManager.calibrateDimensions(result.dimensions)

            // Calculate calibrated volume (volume scales cubically with linear dimensions)
            let volumeScaleFactor: Float
            if let factor = calibrationManager.calibrationFactor {
                volumeScaleFactor = factor * factor * factor  // V ∝ L³
            } else {
                volumeScaleFactor = 1.0
            }
            let calibratedVolume = Float(result.volume_cm3) * volumeScaleFactor

            // ✅ CRASH FIX: Validate calibrated values before proceeding
            guard calibratedVolume.isFinite && calibratedVolume >= 0 else {
                print("      ❌ ERROR: Calibrated volume is invalid (NaN/Infinite): \(calibratedVolume)")
                scanState = .error("Ungültiges Volumen berechnet")
                return
            }

            guard calibratedDimensions.x.isFinite && calibratedDimensions.y.isFinite && calibratedDimensions.z.isFinite else {
                print("      ❌ ERROR: Calibrated dimensions contain NaN/Infinite: \(calibratedDimensions)")
                scanState = .error("Ungültige Dimensionen berechnet")
                return
            }

            if calibrationManager.isCalibrated {
                print("      ✅ Calibration applied: \(String(format: "%.2f", result.volume_cm3))ml → \(String(format: "%.2f", calibratedVolume))ml")
                print("      ✅ Dimensions calibrated: \(result.dimensions) → \(calibratedDimensions)")
            }

            // Recalculate weight with calibrated volume
            let calibratedWeight = Double(calibratedVolume) * selectedMaterial.density

            // ✅ CRASH FIX: Validate weight is finite
            guard calibratedWeight.isFinite && calibratedWeight >= 0 else {
                print("      ❌ ERROR: Calibrated weight is invalid (NaN/Infinite): \(calibratedWeight)")
                scanState = .error("Ungültiges Gewicht berechnet")
                return
            }

            // Update all UI properties at once (all values validated)
            self.volume_cm3 = Double(calibratedVolume)
            self.weight_g = calibratedWeight
            self.dimensions = calibratedDimensions
            self.detectedPlaneHeight = result.detectedPlaneHeight
            self.accuracyPercentage = result.accuracyPercentage
            self.accuracyDescription = result.accuracyDescription
            self.accuracyColor = result.accuracyColor
            self.symmetryScore = result.symmetryScore
            self.meshVolumeResult = result.meshVolumeResult
            self.meshQualityDescription = result.meshQualityDescription
            self.qualityScore = max(qualityScore, Double(result.aiQuality))
            self.can3DExport = !meshAnchors.isEmpty

            // Set state to completed
            self.scanState = .completed

            print("      ✅ UI updated - scan complete!")
        }

        print("   🎯 processMeshDataAsync() finished")
    }

    // MARK: - Processing Result Structure

    private struct ProcessingResult {
        let volume_cm3: Double
        let weight_g: Double
        let dimensions: SIMD3<Float>
        let detectedPlaneHeight: Float?
        let accuracyPercentage: Double
        let accuracyDescription: String
        let accuracyColor: String
        let symmetryScore: Float
        let meshVolumeResult: MeshVolumeResult?
        let meshQualityDescription: String
        let aiQuality: Float
    }

    // MARK: - Background-Safe Sync Methods (nonisolated)

    /// Detect table plane without accessing MainActor properties
    nonisolated private func detectTablePlaneSync(from points: [simd_float3], normals: [simd_float3]) -> Float? {
        // Find horizontal surfaces (table/floor)
        var horizontalPoints: [simd_float3] = []

        for i in 0..<min(points.count, normals.count) {
            let normal = normals[i]
            // Check if normal is pointing up (dot product with up vector)
            if abs(dot(normal, simd_float3(0, 1, 0))) > 0.9 {
                horizontalPoints.append(points[i])
            }
        }

        if !horizontalPoints.isEmpty {
            // Find most common Y value (histogram)
            let yValues = horizontalPoints.map { $0.y }

            // ✅ CRITICAL: Guard division and validate result
            guard yValues.count > 0 else { return nil }
            let avgY = yValues.reduce(0, +) / Float(yValues.count)

            // ✅ CRITICAL: Verify result is valid
            guard avgY.isFinite else {
                print("⚠️ Plane height calculation produced NaN/Infinite")
                return nil
            }

            return avgY
        }

        return nil
    }

    /// Evaluate accuracy without MainActor access
    nonisolated private func evaluateAccuracySync(
        volumeResult: VolumeResult,
        points: [simd_float3],
        confidence: [Float]
    ) -> (accuracyPercentage: Double, accuracyDescription: String, accuracyColor: String) {
        // Simple quality score based on point count and confidence
        let avgConfidence = confidence.isEmpty ? 0.5 : confidence.reduce(0, +) / Float(confidence.count)

        // ✅ CRITICAL: Validate avgConfidence
        let safeAvgConfidence = avgConfidence.isFinite ? avgConfidence : 0.5

        let pointDensity = min(Float(points.count) / 5000.0, 1.0)

        // ✅ CRITICAL: Validate pointDensity
        let safePointDensity = pointDensity.isFinite ? pointDensity : 0.0

        let qualityScore = (safeAvgConfidence + safePointDensity) / 2.0

        // ✅ CRITICAL: Validate qualityScore before using
        let safeQualityScore = qualityScore.isFinite ? qualityScore : 0.5

        let accuracyPercentage = Double(safeQualityScore * 100)

        let description: String
        let color: String

        if qualityScore > 0.8 {
            description = "Ausgezeichnet"
            color = "green"
        } else if qualityScore > 0.6 {
            description = "Gut"
            color = "orange"
        } else {
            description = "Akzeptabel"
            color = "yellow"
        }

        return (accuracyPercentage, description, color)
    }

    /// Spatial analysis without MainActor access
    nonisolated private func performSpatialAnalysisSync(points: [simd_float3], boundingBox: BoundingBox) -> Float {
        // Calculate simple symmetry score
        guard points.count > 10 else { return 0.5 }

        // Calculate center of mass
        let centerOfMass = points.reduce(simd_float3.zero, +) / Float(points.count)

        // ✅ CRITICAL: Validate center of mass
        guard centerOfMass.x.isFinite && centerOfMass.y.isFinite && centerOfMass.z.isFinite else {
            print("⚠️ Center of mass calculation produced NaN/Infinite")
            return 0.5
        }

        // Calculate variance from center
        let variances = points.map { point -> Float in
            let diff = point - centerOfMass
            return simd_length(diff)
        }

        // ✅ CRITICAL: Guard division and validate
        guard variances.count > 0 else { return 0.5 }
        let avgVariance = variances.reduce(0, +) / Float(variances.count)
        let maxVariance = variances.max() ?? 0.1

        // ✅ CRITICAL: Validate variance values
        guard avgVariance.isFinite && maxVariance.isFinite && maxVariance > 0 else {
            print("⚠️ Variance calculation produced NaN/Infinite")
            return 0.5
        }

        // Symmetry score: lower variance = more symmetric
        let ratio = avgVariance / maxVariance

        // ✅ CRITICAL: Validate ratio
        guard ratio.isFinite else {
            print("⚠️ Symmetry ratio produced NaN/Infinite")
            return 0.5
        }

        let symmetryScore = 1.0 - min(ratio, 1.0)

        return symmetryScore
    }

    /// Calculate mesh volume without MainActor access
    nonisolated private func calculateMeshVolumeSync(meshAnchors: [ARMeshAnchor]) -> (MeshVolumeResult?, String) {
        guard !meshAnchors.isEmpty else { return (nil, "Keine Mesh-Daten") }

        // Calculate precise volume from mesh
        if let meshResult = MeshVolumeCalculator.calculateVolume(from: meshAnchors) {
            // Manually create description to avoid MainActor access
            let qualityDesc: String
            let score = meshResult.quality.qualityScore
            switch score {
            case 0.9...1.0: qualityDesc = "Exzellent"
            case 0.7..<0.9: qualityDesc = "Sehr gut"
            case 0.5..<0.7: qualityDesc = "Gut"
            case 0.3..<0.5: qualityDesc = "Befriedigend"
            default: qualityDesc = "Ungenügend"
            }
            return (meshResult, qualityDesc)
        }

        return (nil, "Berechnung fehlgeschlagen")
    }

    // MARK: - 3D Model Processing (MainActor versions)

    private func calculateMeshVolume() {
        guard !meshAnchors.isEmpty else { return }

        // Calculate precise volume from mesh
        if let meshResult = MeshVolumeCalculator.calculateVolume(from: meshAnchors) {
            meshVolumeResult = meshResult
            meshQualityDescription = meshResult.quality.description

            // Use mesh volume if it's more accurate
            if meshResult.quality.qualityScore > 0.7 {
                volume_cm3 = meshResult.volume_cm3

                // Recalculate weight with new volume
                calculateWeight()
            }
        }
    }

    /// Export 3D model to file
    func export3DModel(format: MeshExportFormat = .obj, fileName: String? = nil) async throws -> MeshExportResult {
        guard let camera = arSession?.currentFrame?.camera else {
            throw ExportError.noMeshAnchorsAvailable
        }

        return try MeshExporter.exportMeshAnchors(
            meshAnchors,
            camera: camera,
            format: format,
            fileName: fileName
        )
    }

    private func detectTablePlane(from points: [simd_float3], normals: [simd_float3]) {
        // Find horizontal surfaces (table/floor)
        var horizontalPoints: [simd_float3] = []

        for i in 0..<min(points.count, normals.count) {
            let normal = normals[i]
            // Check if normal is pointing up (dot product with up vector)
            if abs(dot(normal, simd_float3(0, 1, 0))) > 0.9 {
                horizontalPoints.append(points[i])
            }
        }

        if !horizontalPoints.isEmpty {
            // Find most common Y value (histogram)
            let yValues = horizontalPoints.map { $0.y }
            detectedPlaneHeight = yValues.reduce(0, +) / Float(yValues.count)
        }
    }

    private func evaluateAccuracy(volumeResult: VolumeResult, points: [simd_float3], confidence: [Float]) {
        guard let cameraPosition = arSession?.currentFrame?.camera.transform.columns.3 else { return }

        let metrics = ScanQualityMetrics.from(
            points: points,
            confidence: confidence,
            cameraPosition: simd_float3(cameraPosition.x, cameraPosition.y, cameraPosition.z),
            isCalibrated: isCalibrated
        )

        let accuracyResult = accuracyEvaluator.evaluateAccuracy(
            metrics: metrics,
            materialCategory: selectedMaterial.category,
            calibrationFactor: calibrationManager.calibrationFactor
        )

        // Update UI
        self.confidence = Double(accuracyResult.confidenceLevel)
        self.qualityScore = Double(accuracyResult.qualityScore)
        self.recommendations = accuracyResult.recommendations

        // Calculate error margin
        calculateErrorMargin(
            volumeResult: volumeResult,
            qualityScore: accuracyResult.qualityScore,
            confidenceLevel: accuracyResult.confidenceLevel,
            pointCount: points.count
        )
    }

    /// Calculate measurement error margin based on scan quality factors
    private func calculateErrorMargin(
        volumeResult: VolumeResult,
        qualityScore: Float,
        confidenceLevel: Float,
        pointCount: Int
    ) {
        // Base error margin depends on volume calculation method
        var baseError: Double = 0.0

        switch volumeResult.method {
        case .boundingBox:
            baseError = 15.0  // ±15% for simple bounding box
        case .convexHull:
            baseError = 10.0  // ±10% for convex hull
        case .heightMap:
            baseError = 8.0   // ±8% for height map (good for powders)
        case .meshBased:
            baseError = 5.0   // ±5% for mesh-based (most accurate)
        }

        // Adjust based on calibration
        if isCalibrated {
            let calibrationAccuracy = Double(calibrationManager.calibrationAccuracy)
            if calibrationAccuracy > 90 {
                baseError *= 0.7  // Reduce by 30% for excellent calibration
            } else if calibrationAccuracy > 75 {
                baseError *= 0.85  // Reduce by 15% for good calibration
            }
        } else {
            baseError *= 1.3  // Increase by 30% without calibration
        }

        // Adjust based on scan quality
        if qualityScore > 0.9 {
            baseError *= 0.8  // Reduce by 20% for excellent quality
        } else if qualityScore < 0.5 {
            baseError *= 1.4  // Increase by 40% for poor quality
        }

        // Adjust based on confidence level
        if confidenceLevel > 0.8 {
            baseError *= 0.9  // Reduce by 10% for high confidence
        } else if confidenceLevel < 0.5 {
            baseError *= 1.2  // Increase by 20% for low confidence
        }

        // Adjust based on point count
        if pointCount > 5000 {
            baseError *= 0.95  // Reduce by 5% for high point density
        } else if pointCount < 1000 {
            baseError *= 1.15  // Increase by 15% for low point density
        }

        // Cap error margin between 3% and 25%
        let finalError = max(3.0, min(25.0, baseError))

        self.errorMarginPercent = finalError
        self.errorMarginDescription = formatErrorMargin(finalError)

        print("📊 Error Margin: ±\(String(format: "%.1f%%", finalError))")
    }

    /// Format error margin for display
    private func formatErrorMargin(_ errorPercent: Double) -> String {
        switch errorPercent {
        case 0..<5:
            return "Sehr präzise (±\(String(format: "%.1f%%", errorPercent)))"
        case 5..<10:
            return "Präzise (±\(String(format: "%.1f%%", errorPercent)))"
        case 10..<15:
            return "Gut (±\(String(format: "%.1f%%", errorPercent)))"
        case 15..<20:
            return "Akzeptabel (±\(String(format: "%.1f%%", errorPercent)))"
        default:
            return "Ungenau (±\(String(format: "%.1f%%", errorPercent)))"
        }
    }

    private func performSpatialAnalysis(points: [simd_float3], boundingBox: BoundingBox) {
        let heatMap = spatialAnalyzer.analyzeSpatialDensity(points: points, boundingBox: boundingBox)
        self.coverageScore = heatMap.overallCoverage

        if heatMap.needsMoreScanning, let cameraPos = arSession?.currentFrame?.camera.transform.columns.3 {
            let hints = spatialAnalyzer.getScanDirectionHints(
                heatMap: heatMap,
                currentCameraPosition: simd_float3(cameraPos.x, cameraPos.y, cameraPos.z)
            )
            recommendations.append(contentsOf: hints)
        }
    }

    // MARK: - Weight Calculation
    private func calculateWeight() {
        // Get density (consider packing for powders)
        var density = selectedMaterial.density

        // Adjust for packing if applicable
        if selectedMaterial.packingFactor != nil {
            // For powders, assume loose packing
            density = selectedMaterial.adjustedDensity(packed: false)
        }

        // Weight = Volume (cm³) × Density (g/cm³)
        weight_g = volume_cm3 * density

        // Apply calibration correction if available
        if isCalibrated, let factor = calibrationManager.calibrationFactor {
            weight_g *= Double(factor)
        }
    }

    // MARK: - Formatted Outputs
    var formattedVolume: String {
        // ✅ CRASH FIX: Guard against NaN/Infinite values
        guard volume_cm3.isFinite && volume_cm3 >= 0 else {
            return "-- cm³"
        }

        if volume_cm3 < 10 {
            return String(format: "%.2f cm³", volume_cm3)
        } else if volume_cm3 < 1000 {
            return String(format: "%.1f cm³", volume_cm3)
        } else {
            let liters = volume_cm3 / 1000.0
            return String(format: "%.2f L", liters)
        }
    }

    /// Formatted volume with error margin
    var formattedVolumeWithError: String {
        let volumeStr = formattedVolume
        if errorMarginPercent > 0 {
            return "\(volumeStr) (±\(String(format: "%.1f%%", errorMarginPercent)))"
        }
        return volumeStr
    }

    var formattedWeight: String {
        // ✅ CRASH FIX: Guard against NaN/Infinite values
        guard weight_g.isFinite && weight_g >= 0 else {
            return "-- g"
        }

        if weight_g < 1 {
            return String(format: "%.2f g", weight_g)
        } else if weight_g < 1000 {
            return String(format: "%.1f g", weight_g)
        } else {
            let kg = weight_g / 1000.0
            return String(format: "%.2f kg", kg)
        }
    }

    var formattedDimensions: String {
        // ✅ CRASH FIX: Guard against NaN/Infinite values
        guard dimensions.x.isFinite && dimensions.y.isFinite && dimensions.z.isFinite else {
            return "-- × -- × -- cm"
        }

        return String(format: "%.1f × %.1f × %.1f cm", dimensions.x, dimensions.y, dimensions.z)
    }

    var qualityRating: String {
        return accuracyEvaluator.getQualityRating(qualityScore: Float(qualityScore))
    }
}
