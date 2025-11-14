//
//  AutoCaptureController.swift
//  SUPERWAAGE
//
//  Intelligent auto-capture controller for AR scanning
//  Automatically triggers capture when quality is good
//

import Foundation
import ARKit
import Combine

// MARK: - Delegate Protocol

protocol AutoCaptureDelegate: AnyObject {
    func autoCaptureDidTrigger()
    func autoCaptureDidUpdateProgress(_ progress: Double)
    func autoCaptureDidUpdateQuality(_ quality: Double)
    func autoCaptureDidUpdateRecommendations(_ recommendations: [String])
    func autoCaptureDidComplete()
}

// MARK: - Auto-Capture Controller

@MainActor
class AutoCaptureController {

    // MARK: - Properties

    weak var delegate: AutoCaptureDelegate?

    private let qualityMeter = ScanQualityMeter()
    private var isEnabled = false

    // Capture settings
    var qualityThreshold: Float = 0.7  // Min quality to trigger (0.0-1.0)
    var minFrameInterval: TimeInterval = 0.1  // Min time between captures (seconds)
    var minCoverage: Float = 0.7  // Min coverage to complete (0.0-1.0)
    var targetFrameCount: Int = 50  // Target frames to capture

    // State tracking
    private var lastCaptureTime: Date = .distantPast
    private var capturedFrameCount = 0
    private var coverageScore: Float = 0.0
    private var currentQuality: Double = 0.0
    private var currentRecommendations: [String] = []

    // MARK: - Public Interface

    /// Start auto-capture
    func start() {
        isEnabled = true
        capturedFrameCount = 0
        coverageScore = 0.0
        currentQuality = 0.0
        currentRecommendations = []
        qualityMeter.resetCoverage()
        print("✅ AutoCapture: Started")
    }

    /// Stop auto-capture
    func stop() {
        isEnabled = false
        print("⏸️ AutoCapture: Stopped")
    }

    /// Reset state
    func reset() {
        isEnabled = false
        capturedFrameCount = 0
        coverageScore = 0.0
        currentQuality = 0.0
        currentRecommendations = []
        qualityMeter.resetCoverage()
    }

    // MARK: - Frame Processing

    /// Process AR frame for auto-capture
    func processFrame(_ frame: ARFrame) {
        guard isEnabled else { return }

        // Evaluate quality
        let metrics = qualityMeter.evaluateQuality(frame: frame)

        // Update state
        currentQuality = Double(metrics.overallScore)
        currentRecommendations = metrics.recommendations

        // Notify delegate of quality update
        delegate?.autoCaptureDidUpdateQuality(currentQuality)
        delegate?.autoCaptureDidUpdateRecommendations(currentRecommendations)

        // Check if should trigger capture
        let now = Date()
        let timeSinceLastCapture = now.timeIntervalSince(lastCaptureTime)

        if metrics.overallScore >= qualityThreshold && timeSinceLastCapture >= minFrameInterval {
            triggerCapture()
            lastCaptureTime = now
        }

        // Update progress
        updateProgress()

        // Check for completion
        checkCompletion()
    }

    // MARK: - Private Methods

    /// Trigger a capture
    private func triggerCapture() {
        capturedFrameCount += 1
        print("📸 AutoCapture: Frame \(capturedFrameCount)/\(targetFrameCount) (quality: \(Int(currentQuality * 100))%)")

        delegate?.autoCaptureDidTrigger()
        updateProgress()
    }

    /// Update progress
    private func updateProgress() {
        // Progress based on frame count and coverage
        let frameProgress = Float(capturedFrameCount) / Float(targetFrameCount)
        let progress = (frameProgress * 0.7 + coverageScore * 0.3)

        delegate?.autoCaptureDidUpdateProgress(Double(min(progress, 1.0)))
    }

    /// Check if auto-capture is complete
    private func checkCompletion() {
        let frameProgress = Float(capturedFrameCount) / Float(targetFrameCount)

        if frameProgress >= 1.0 && coverageScore >= minCoverage {
            complete()
        }
    }

    /// Complete auto-capture
    private func complete() {
        guard isEnabled else { return }

        isEnabled = false
        print("✅ AutoCapture: Complete! (\(capturedFrameCount) frames, \(Int(coverageScore * 100))% coverage)")

        delegate?.autoCaptureDidComplete()
    }

    // MARK: - Coverage Update

    /// Update coverage score (called by ScanViewModel)
    func updateCoverage(_ score: Float) {
        coverageScore = score
    }

    // MARK: - Status

    /// Check if auto-capture is enabled
    var isActive: Bool {
        return isEnabled
    }

    /// Get current capture count
    var captureCount: Int {
        return capturedFrameCount
    }
}

// MARK: - Usage Example

/*

 class ScanViewModel: AutoCaptureDelegate {

     private let autoCaptureController = AutoCaptureController()

     func setupAutoCapture() {
         autoCaptureController.delegate = self
         autoCaptureController.qualityThreshold = 0.7  // 70% quality min
         autoCaptureController.targetFrameCount = 50   // Capture 50 frames
         autoCaptureController.start()
     }

     func feedARFrameToAutoCapture(_ frame: ARFrame) {
         autoCaptureController.processFrame(frame)
     }

     // MARK: - AutoCaptureDelegate

     func autoCaptureDidTrigger() {
         // Frame captured automatically
     }

     func autoCaptureDidUpdateProgress(_ progress: Double) {
         self.scanProgress = progress
     }

     func autoCaptureDidUpdateQuality(_ quality: Double) {
         self.qualityScore = quality
     }

     func autoCaptureDidUpdateRecommendations(_ recommendations: [String]) {
         self.recommendations = recommendations
     }

     func autoCaptureDidComplete() {
         // Auto-capture finished!
         self.completeScan()
     }
 }

 */
