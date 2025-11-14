//
//  MultiScanManager.swift
//  SUPERWAAGE
//
//  Multi-angle scanning system for improved accuracy on powders, granular materials
//  Adapted from Kuechenwaage project and enhanced
//

import Foundation
import ARKit
import simd
import Combine

/// Manages multiple scans from different angles for improved volume estimation
class MultiScanManager: ObservableObject {

    // MARK: - Published Properties
    @Published var currentScanIndex: Int = 0
    @Published var totalScans: Int = 3
    @Published var scanProgress: Double = 0.0
    @Published var isMultiScanMode: Bool = false
    @Published var scanQualityScore: Double = 0.0

    // MARK: - Private Properties
    private var scanResults: [ScanResult] = []
    private var requiredAngles: [ScanAngle] = []
    private var currentCameraPosition: simd_float3?
    private var referencePosition: simd_float3?

    // MARK: - Configuration
    private let minimumPointsPerScan: Int = 100
    private let maximumScanTime: TimeInterval = 10.0
    private var scanStartTime: Date?

    // MARK: - Scan Result Structure
    struct ScanResult {
        let timestamp: Date
        let points: [simd_float3]
        let normals: [simd_float3]
        let confidence: [Float]
        let cameraPosition: simd_float3
        let angle: ScanAngle
        let qualityScore: Double
    }

    // MARK: - Scan Angle Types
    enum ScanAngle: String, CaseIterable {
        case front = "Front View"
        case top = "Top View"
        case side = "Side View"
        case angle45 = "45° Angle"
        case angle135 = "135° Angle"

        var requiredRotation: Float {
            switch self {
            case .front: return 0.0
            case .top: return Float.pi / 2
            case .side: return Float.pi / 2
            case .angle45: return Float.pi / 4
            case .angle135: return 3 * Float.pi / 4
            }
        }
    }

    // MARK: - Initialization
    init() {
        setupDefaultScanPattern()
    }

    // MARK: - Setup Methods
    private func setupDefaultScanPattern() {
        // For kitchen materials, we need front, top, and one angled view
        requiredAngles = [.front, .top, .angle45]
        totalScans = requiredAngles.count
    }

    func setupForMaterialType(_ materialType: MaterialType) {
        switch materialType {
        case .powder, .granular:
            // Powders need more angles due to irregular shapes
            requiredAngles = [.front, .top, .angle45, .angle135]
            totalScans = 4
        case .solid, .liquid:
            // Solid objects need fewer scans
            requiredAngles = [.front, .top, .side]
            totalScans = 3
        case .irregular:
            // Irregular objects need comprehensive coverage
            requiredAngles = ScanAngle.allCases
            totalScans = 5
        }
        isMultiScanMode = true
        currentScanIndex = 0
    }

    // MARK: - Material Type
    enum MaterialType {
        case powder      // Flour, sugar, salt
        case granular    // Rice, beans, breadcrumbs
        case solid       // Butter, cheese
        case liquid      // Water, oil
        case irregular   // Herbs, spices
    }

    // MARK: - Scan Management
    func startMultiScan() {
        scanResults.removeAll()
        currentScanIndex = 0
        scanProgress = 0.0
        scanStartTime = Date()
        isMultiScanMode = true
    }

    func recordScan(points: [simd_float3], normals: [simd_float3], confidence: [Float], cameraTransform: simd_float4x4) {
        guard currentScanIndex < totalScans else { return }

        let cameraPosition = simd_float3(cameraTransform.columns.3.x,
                                         cameraTransform.columns.3.y,
                                         cameraTransform.columns.3.z)

        // Calculate quality score
        let quality = calculateScanQuality(points: points, confidence: confidence, cameraPosition: cameraPosition)

        let result = ScanResult(
            timestamp: Date(),
            points: points,
            normals: normals,
            confidence: confidence,
            cameraPosition: cameraPosition,
            angle: requiredAngles[currentScanIndex],
            qualityScore: quality
        )

        scanResults.append(result)
        currentScanIndex += 1
        updateProgress()

        // Auto-advance to next scan
        if currentScanIndex >= totalScans {
            completeMultiScan()
        }
    }

    func calculateScanQuality(points: [simd_float3], confidence: [Float], cameraPosition: simd_float3) -> Double {
        guard !points.isEmpty else { return 0.0 }

        var qualityScore = 0.0

        // Factor 1: Number of points (more is better, up to a threshold)
        let pointScore = min(Double(points.count) / 1000.0, 1.0)
        qualityScore += pointScore * 0.3

        // Factor 2: Average confidence
        let avgConfidence = confidence.reduce(0.0, +) / Float(confidence.count)
        qualityScore += Double(avgConfidence) * 0.4

        // Factor 3: Point distribution (coverage)
        let coverageScore = calculateCoverageScore(points: points)
        qualityScore += coverageScore * 0.3

        return min(qualityScore, 1.0)
    }

    private func calculateCoverageScore(points: [simd_float3]) -> Double {
        guard points.count > 10 else { return 0.0 }

        // Calculate bounding box
        let minX = points.map { $0.x }.min() ?? 0
        let maxX = points.map { $0.x }.max() ?? 0
        let minY = points.map { $0.y }.min() ?? 0
        let maxY = points.map { $0.y }.max() ?? 0
        let minZ = points.map { $0.z }.min() ?? 0
        let maxZ = points.map { $0.z }.max() ?? 0

        let volume = (maxX - minX) * (maxY - minY) * (maxZ - minZ)

        // Good coverage means points fill the volume
        let density = Double(points.count) / Double(volume)
        return min(density / 100.0, 1.0)
    }

    private func updateProgress() {
        scanProgress = Double(currentScanIndex) / Double(totalScans)

        // Calculate overall quality from all scans
        if !scanResults.isEmpty {
            scanQualityScore = scanResults.map { $0.qualityScore }.reduce(0.0, +) / Double(scanResults.count)
        }
    }

    func completeMultiScan() {
        isMultiScanMode = false
        scanProgress = 1.0
    }

    // MARK: - Merge Scans
    func mergeScans() -> (points: [simd_float3], normals: [simd_float3], confidence: [Float])? {
        guard !scanResults.isEmpty else { return nil }

        var mergedPoints: [simd_float3] = []
        var mergedNormals: [simd_float3] = []
        var mergedConfidence: [Float] = []

        for result in scanResults {
            // Filter by confidence threshold
            for i in 0..<result.points.count {
                if result.confidence[i] >= 0.5 {
                    mergedPoints.append(result.points[i])
                    mergedNormals.append(result.normals[i])
                    mergedConfidence.append(result.confidence[i])
                }
            }
        }

        // Remove duplicate points (within threshold)
        let deduplicated = removeDuplicatePoints(points: mergedPoints,
                                                 normals: mergedNormals,
                                                 confidence: mergedConfidence)

        return deduplicated
    }

    private func removeDuplicatePoints(points: [simd_float3], normals: [simd_float3], confidence: [Float]) -> (points: [simd_float3], normals: [simd_float3], confidence: [Float]) {
        let threshold: Float = 0.005 // 5mm threshold

        var uniquePoints: [simd_float3] = []
        var uniqueNormals: [simd_float3] = []
        var uniqueConfidence: [Float] = []

        for i in 0..<points.count {
            let point = points[i]
            var isDuplicate = false

            for existingPoint in uniquePoints {
                if simd_distance(point, existingPoint) < threshold {
                    isDuplicate = true
                    break
                }
            }

            if !isDuplicate {
                uniquePoints.append(point)
                uniqueNormals.append(normals[i])
                uniqueConfidence.append(confidence[i])
            }
        }

        return (uniquePoints, uniqueNormals, uniqueConfidence)
    }

    // MARK: - Guidance
    func getNextScanGuidance() -> String {
        guard currentScanIndex < totalScans else {
            return "Multi-scan complete!"
        }

        let nextAngle = requiredAngles[currentScanIndex]
        return "Please scan from: \(nextAngle.rawValue)"
    }

    func shouldAllowNextScan() -> Bool {
        guard let lastResult = scanResults.last else { return true }
        return lastResult.qualityScore >= 0.6 // Require 60% quality
    }

    // MARK: - Reset
    func reset() {
        scanResults.removeAll()
        currentScanIndex = 0
        scanProgress = 0.0
        scanQualityScore = 0.0
        isMultiScanMode = false
        setupDefaultScanPattern()
    }
}
