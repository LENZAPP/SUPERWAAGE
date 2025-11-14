//
//  QuickCalibrationCoordinator.swift
//  SUPERWAAGE
//
//  Orchestrates the quick calibration flow
//  - Multi-angle capture
//  - Vision detection
//  - Depth bias regression
//  - Result computation
//

import Foundation
import Combine
import ARKit
import Vision

/// Coordinates the quick calibration process
@MainActor
class QuickCalibrationCoordinator: ObservableObject {

    // MARK: - Published State

    @Published private(set) var state: QuickCalibrationState = .notStarted
    @Published private(set) var selectedObject: ReferenceObjectType?
    @Published private(set) var currentAngle: CalibrationAngle?
    @Published private(set) var capturedFrames: [CalibrationFrame] = []
    @Published private(set) var result: EnhancedCalibrationResult?

    // ✅ NEW: Manual capture state
    @Published var isWellAligned: Bool = false
    @Published var alignmentQuality: Float = 0.0  // 0-1

    // ✅ NEW: Store latest frame data for manual capture
    private var latestPixelBuffer: CVPixelBuffer?
    private var latestCameraTransform: simd_float4x4?
    private var latestCameraIntrinsics: simd_float3x3?
    private var latestDepthMap: CVPixelBuffer?

    // MARK: - Dependencies

    private let contourDetector = VisionContourDetector()
    private let depthRegression = DepthBiasRegression()
    private var cancellables = Set<AnyCancellable>()

    // MARK: - Required Angles

    private let requiredAngles: [CalibrationAngle] = [
        .frontal,
        .leftAngle,
        .topAngle
    ]

    private var nextAngleIndex: Int = 0

    // MARK: - Public API

    /// Start the calibration flow (show object selection)
    func startFlow() {
        self.state = .selectingObject
    }

    /// Start calibration with selected object
    func startCalibration(with object: ReferenceObjectType) {
        self.selectedObject = object
        self.capturedFrames = []
        self.nextAngleIndex = 0
        self.currentAngle = requiredAngles.first
        self.state = .capturingFrame(
            angle: requiredAngles[0],
            progress: 0,
            total: requiredAngles.count
        )
    }

    /// Process AR frame to check alignment (NO auto-capture)
    func processFrame(
        pixelBuffer: CVPixelBuffer,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        depthMap: CVPixelBuffer?
    ) async {
        guard case .capturingFrame = state else {
            // Clear stored frames when not capturing
            clearStoredFrameData()
            return
        }
        guard let object = selectedObject else { return }

        // ✅ Store latest frame data for manual capture (keep only latest to avoid memory buildup)
        self.latestPixelBuffer = pixelBuffer
        self.latestCameraTransform = cameraTransform
        self.latestCameraIntrinsics = cameraIntrinsics
        self.latestDepthMap = depthMap

        // Detect reference object
        do {
            if let detection = try await contourDetector.detectReferenceObject(
                in: pixelBuffer,
                expectedType: object
            ) {
                // ✅ Calculate alignment quality
                let quality = calculateAlignmentQuality(detection: detection, object: object)

                await MainActor.run {
                    self.alignmentQuality = quality
                    self.isWellAligned = quality > 0.85  // 85%+ = well aligned
                }
            } else {
                // No detection
                await MainActor.run {
                    self.alignmentQuality = 0.0
                    self.isWellAligned = false
                }
            }
        } catch {
            print("❌ Detection error: \(error)")
            await MainActor.run {
                self.alignmentQuality = 0.0
                self.isWellAligned = false
            }
        }
    }

    /// Manual capture triggered by user button (uses latest stored frame)
    func manualCapture() async {
        print("🎯 manualCapture() called")

        guard case .capturingFrame = state else {
            print("❌ Wrong state: \(state)")
            return
        }
        guard let object = selectedObject else {
            print("❌ No object selected")
            return
        }
        guard let angle = currentAngle else {
            print("❌ No current angle")
            return
        }

        // Use stored latest frame data
        guard let pixelBuffer = latestPixelBuffer,
              let cameraTransform = latestCameraTransform,
              let cameraIntrinsics = latestCameraIntrinsics else {
            print("⚠️ No frame data available for capture")
            return
        }

        print("📸 Starting detection for capture...")

        // Detect reference object one more time for capture
        do {
            if let detection = try await contourDetector.detectReferenceObject(
                in: pixelBuffer,
                expectedType: object
            ) {
                print("✅ Detection successful! Quality: \(Int(alignmentQuality * 100))%")
                print("   Detected size: \(detection.pixelWidth) x \(detection.pixelHeight)")

                // ✅ Create a copy of the pixel buffer to avoid retention issues
                let copiedPixelBuffer = copyPixelBuffer(pixelBuffer)

                // Capture frame
                await captureFrame(
                    detection: detection,
                    pixelBuffer: copiedPixelBuffer ?? pixelBuffer,
                    cameraTransform: cameraTransform,
                    cameraIntrinsics: cameraIntrinsics,
                    depthMap: latestDepthMap,
                    angle: angle
                )
            } else {
                print("⚠️ No object detected for capture")
                await MainActor.run {
                    // Show error feedback
                }
            }
        } catch {
            print("❌ Capture error: \(error)")
            print("   Error details: \(error.localizedDescription)")
        }
    }

    /// Copy pixel buffer to avoid memory issues
    private func copyPixelBuffer(_ pixelBuffer: CVPixelBuffer) -> CVPixelBuffer? {
        let width = CVPixelBufferGetWidth(pixelBuffer)
        let height = CVPixelBufferGetHeight(pixelBuffer)
        let format = CVPixelBufferGetPixelFormatType(pixelBuffer)

        var copiedBuffer: CVPixelBuffer?
        let status = CVPixelBufferCreate(
            kCFAllocatorDefault,
            width,
            height,
            format,
            nil,
            &copiedBuffer
        )

        guard status == kCVReturnSuccess, let copied = copiedBuffer else {
            return nil
        }

        CVPixelBufferLockBaseAddress(pixelBuffer, .readOnly)
        CVPixelBufferLockBaseAddress(copied, [])

        let srcData = CVPixelBufferGetBaseAddress(pixelBuffer)
        let dstData = CVPixelBufferGetBaseAddress(copied)
        let dataSize = CVPixelBufferGetDataSize(pixelBuffer)

        memcpy(dstData, srcData, dataSize)

        CVPixelBufferUnlockBaseAddress(copied, [])
        CVPixelBufferUnlockBaseAddress(pixelBuffer, .readOnly)

        return copied
    }

    /// Cancel calibration
    func cancel() {
        self.state = .notStarted
        self.selectedObject = nil
        self.capturedFrames = []
        self.nextAngleIndex = 0
        self.currentAngle = nil
        clearStoredFrameData()
    }

    /// Reset and start over
    func reset() {
        cancel()
    }

    /// Clear stored frame data to free memory
    private func clearStoredFrameData() {
        self.latestPixelBuffer = nil
        self.latestCameraTransform = nil
        self.latestCameraIntrinsics = nil
        self.latestDepthMap = nil
    }

    // MARK: - Private Methods

    private func captureFrame(
        detection: ContourDetectionResult,
        pixelBuffer: CVPixelBuffer,
        cameraTransform: simd_float4x4,
        cameraIntrinsics: simd_float3x3,
        depthMap: CVPixelBuffer?,
        angle: CalibrationAngle
    ) async {
        print("📦 captureFrame() called for angle: \(angle.rawValue)")

        guard let object = selectedObject else {
            print("❌ No object in captureFrame")
            return
        }

        // ✅ Validate detection dimensions
        guard detection.pixelWidth > 0 && detection.pixelHeight > 0 else {
            print("❌ Invalid detection dimensions: \(detection.pixelWidth) x \(detection.pixelHeight)")
            await MainActor.run {
                self.state = .failed("Ungültige Objekterkennung")
            }
            return
        }

        // Estimate depth from depth map
        let depthEstimate = estimateDepth(from: depthMap, at: detection.boundingBox)
        print("   Depth estimate: \(depthEstimate?.description ?? "nil")")

        // Create calibration frame
        let frame = CalibrationFrame(
            timestamp: Date(),
            referenceObject: object,
            angleDescription: angle,
            cameraTransform: cameraTransform,
            cameraIntrinsics: cameraIntrinsics,
            detectedContour: detection.contourPoints,
            depthMap: depthMap,
            depthEstimate: depthEstimate,
            pixelWidth: detection.pixelWidth,
            pixelHeight: detection.pixelHeight,
            capturedImage: pixelBuffer
        )

        // ✅ Update on main thread
        await MainActor.run {
            self.capturedFrames.append(frame)
                print("✅ Frame captured! Total frames: \(self.capturedFrames.count)")

                // Haptic feedback
                let generator = UIImpactFeedbackGenerator(style: .medium)
                generator.impactOccurred()

                // Reset alignment for next capture
                self.isWellAligned = false
                self.alignmentQuality = 0.0
            }

            // Move to next angle or complete
            await MainActor.run {
                self.nextAngleIndex += 1
            }

            if nextAngleIndex < requiredAngles.count {
                print("➡️ Moving to next angle: \(requiredAngles[nextAngleIndex].rawValue)")

                await MainActor.run {
                    self.currentAngle = requiredAngles[nextAngleIndex]
                    self.state = .capturingFrame(
                        angle: requiredAngles[nextAngleIndex],
                        progress: nextAngleIndex,
                        total: requiredAngles.count
                    )
                }

                // Small delay before next capture
                try? await Task.sleep(nanoseconds: 1_500_000_000)  // 1.5 seconds

            } else {
                print("🎉 All frames captured! Starting processing...")
                // All frames captured, process
                await processCalibration()
            }
    }

    private func processCalibration() async {
        print("🔄 processCalibration() started")

        await MainActor.run {
            self.state = .processing
        }

        // Small delay for UX
        try? await Task.sleep(nanoseconds: 500_000_000)  // 0.5 seconds

        guard capturedFrames.count >= 2 else {
            print("❌ Not enough frames: \(capturedFrames.count)")
            await MainActor.run {
                self.state = .failed("Nicht genug Frames erfasst (\(capturedFrames.count))")
            }
            return
        }

        print("📊 Computing calibration from \(capturedFrames.count) frames...")

        // ✅ Compute calibration
        let result: EnhancedCalibrationResult?
        do {
            result = try computeEnhancedCalibration()
            print("✅ Calibration computed successfully!")
        } catch {
            print("❌ Computation failed: \(error)")
            print("   Error type: \(type(of: error))")
            print("   Error description: \(error.localizedDescription)")
            await MainActor.run {
                self.state = .failed("Berechnung fehlgeschlagen: \(error.localizedDescription)")
            }
            return
        }

        guard let finalResult = result else {
            print("❌ No result from computation")
            await MainActor.run {
                self.state = .failed("Kein Ergebnis berechnet")
            }
            return
        }

        // ✅ Validate result before proceeding
        guard finalResult.scaleFactor > 0 && finalResult.scaleFactor.isFinite else {
            print("❌ Invalid scale factor: \(finalResult.scaleFactor)")
            await MainActor.run {
                self.state = .failed("Ungültiger Skalierungsfaktor")
            }
            return
        }

        print("💾 Saving calibration result...")

        // Save to CalibrationManager
        do {
            try await saveToCalibrationManager(finalResult)
            print("✅ Saved successfully!")
        } catch {
            print("❌ Save failed: \(error)")
            await MainActor.run {
                self.state = .failed("Speichern fehlgeschlagen")
            }
            return
        }

        // Update state on main thread
        print("🎉 Transitioning to completed state...")
        await MainActor.run {
            self.result = finalResult
            self.state = .completed(finalResult)
            print("🎉 Calibration completed! Quality: \(finalResult.qualityScore)%")
        }

        print("✅ processCalibration() finished successfully")
    }

    private func computeEnhancedCalibration() throws -> EnhancedCalibrationResult {
        print("🧮 computeEnhancedCalibration() started")

        guard !capturedFrames.isEmpty else {
            print("❌ No captured frames!")
            throw CalibrationError.insufficientFrames
        }

        // Extract scale factors and depths from each frame
        var scaleFactors: [Double] = []
        var depths: [Double] = []
        var errors: [Double] = []

        for (index, frame) in capturedFrames.enumerated() {
            let scaleFactor = frame.scaleFactorEstimate

            // ✅ Validate scale factor
            guard scaleFactor > 0 && scaleFactor.isFinite && scaleFactor < 1.0 else {
                print("❌ Invalid scale factor for frame \(index+1): \(scaleFactor)")
                continue  // Skip invalid frames
            }

            scaleFactors.append(scaleFactor)
            print("   Frame \(index+1): scaleFactor = \(scaleFactor)")

            if let depth = frame.depthEstimate {
                depths.append(Double(depth))

                // Calculate error (difference from expected)
                let expectedDepth = 0.3  // Assume ~30cm calibration distance
                let error = Double(depth) - expectedDepth
                errors.append(error)
                print("   Frame \(index+1): depth = \(depth)m, error = \(error)")
            }
        }

        guard !scaleFactors.isEmpty else {
            throw CalibrationError.insufficientFrames
        }

        // Compute average scale factor
        let avgScaleFactor = scaleFactors.reduce(0, +) / Double(scaleFactors.count)
        print("   Average scale factor: \(avgScaleFactor)")

        // Compute depth bias coefficients (linear regression)
        var depthBiasCoefficients: [Double] = [0.0, 0.0]
        var mse: Double = 0.0

        if depths.count >= 2 {
            print("   Performing linear regression with \(depths.count) depth samples...")
            if let regression = depthRegression.linearRegression(x: depths, y: errors) {
                depthBiasCoefficients = regression.coefficients
                mse = regression.mse
                print("   Regression: a=\(depthBiasCoefficients[0]), b=\(depthBiasCoefficients[1]), mse=\(mse)")
            } else {
                print("   ⚠️ Regression failed, using default coefficients")
            }
        } else {
            print("   ⚠️ Not enough depth samples for regression")
        }

        // Compute quality score based on consistency
        let scaleFactorVariance = variance(scaleFactors)
        let qualityScore = max(0, min(100, 100.0 * (1.0 - scaleFactorVariance)))
        print("   Variance: \(scaleFactorVariance), Quality: \(qualityScore)%")

        guard let object = selectedObject else {
            throw CalibrationError.noObjectSelected
        }

        let result = EnhancedCalibrationResult(
            scaleFactor: avgScaleFactor,
            depthBiasCoefficients: depthBiasCoefficients,
            qualityScore: qualityScore,
            referenceObject: object,
            frameCount: capturedFrames.count,
            timestamp: Date(),
            mse: mse
        )

        print("✅ Calibration result created successfully")
        return result
    }

    private func saveToCalibrationManager(_ result: EnhancedCalibrationResult) async throws {
        print("💾 Saving to CalibrationManager...")

        // Save to the existing CalibrationManager (must be on main thread)
        await MainActor.run {
            let manager = CalibrationManager.shared
            manager.saveEnhancedCalibration(result)
        }

        print("✅ Calibration saved to CalibrationManager:")
        print("   Scale Factor: \(result.scaleFactor)")
        print("   Quality: \(result.qualityScore)%")
        print("   Depth Bias: \(result.depthBiasCoefficients)")
    }

    // MARK: - Helpers

    /// Calculate how well the detected object aligns with the silhouette overlay
    private func calculateAlignmentQuality(detection: ContourDetectionResult, object: ReferenceObjectType) -> Float {
        // Target overlay is at center of screen
        let targetCenter = CGPoint(x: 0.5, y: 0.5)
        let targetSize: CGFloat = object.dimensions.shape == .circular ? 0.3 : 0.35  // 30-35% of screen

        // Detected object center and size
        let detectedCenter = CGPoint(
            x: detection.boundingBox.midX,
            y: detection.boundingBox.midY
        )
        let detectedSize = max(detection.boundingBox.width, detection.boundingBox.height)

        // 1. Position score (how centered is it?)
        let distanceFromCenter = sqrt(
            pow(detectedCenter.x - targetCenter.x, 2) +
            pow(detectedCenter.y - targetCenter.y, 2)
        )
        let positionScore = max(0, 1.0 - Float(distanceFromCenter * 4.0))  // Within 25% tolerance

        // 2. Size score (how close is the size?)
        let sizeRatio = Float(detectedSize / targetSize)
        let sizeScore = max(0, 1.0 - abs(sizeRatio - 1.0))  // Perfect = 1.0

        // 3. Confidence score
        let confidenceScore = detection.confidence

        // Combined score (weighted average)
        let alignmentQuality = (
            positionScore * 0.4 +      // 40% position
            sizeScore * 0.4 +          // 40% size
            confidenceScore * 0.2      // 20% detection confidence
        )

        return min(1.0, max(0.0, alignmentQuality))
    }

    private func estimateDepth(from depthMap: CVPixelBuffer?, at boundingBox: CGRect) -> Float? {
        guard let depthMap = depthMap else { return nil }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return nil }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        // Sample center of bounding box
        let centerX = Int(boundingBox.midX * CGFloat(width))
        let centerY = Int(boundingBox.midY * CGFloat(height))

        guard centerX >= 0, centerX < width, centerY >= 0, centerY < height else { return nil }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float32.self)

        let index = centerY * (bytesPerRow / MemoryLayout<Float32>.stride) + centerX
        return floatBuffer[index]
    }

    private func variance(_ values: [Double]) -> Double {
        guard values.count > 1 else { return 0 }

        let mean = values.reduce(0, +) / Double(values.count)
        let squaredDiffs = values.map { pow($0 - mean, 2) }
        return squaredDiffs.reduce(0, +) / Double(values.count)
    }
}

// MARK: - Errors

enum CalibrationError: Error {
    case noObjectSelected
    case insufficientFrames
    case regressionFailed
}
