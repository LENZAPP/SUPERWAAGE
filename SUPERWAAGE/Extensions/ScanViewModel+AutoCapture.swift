//
//  ScanViewModel+AutoCapture.swift
//  SUPERWAAGE
//
//  Integration of AutoCaptureController for intelligent auto-scanning
//  into the existing ScanViewModel SwiftUI/Combine architecture.
//
//  WHAT THIS ADDS:
//  - Automatic frame capture when quality is good
//  - Real-time quality feedback (features, lighting, depth, motion)
//  - Coverage tracking with intelligent completion
//  - User guidance ("move slower", "improve lighting", etc.)
//
//  INTEGRATION:
//  1. Add AutoCaptureController.swift to your project
//  2. Add ScanQualityMeter.swift to your project
//  3. Add this extension file to your project
//  4. Call setupAutoCapture() in startScanning()
//  5. Call feedARFrameToAutoCapture() from ARSession delegate
//

import SwiftUI
import ARKit
import Combine

// MARK: - Auto-Capture Integration Extension

extension ScanViewModel: AutoCaptureDelegate {

    // MARK: - Associated Object Storage

    private static var autoCaptureControllerKey: UInt8 = 0

    /// Auto-capture controller instance
    private var autoCaptureController: AutoCaptureController {
        get {
            if let controller = objc_getAssociatedObject(self, &Self.autoCaptureControllerKey) as? AutoCaptureController {
                return controller
            }
            let controller = AutoCaptureController()
            controller.delegate = self
            objc_setAssociatedObject(self, &Self.autoCaptureControllerKey, controller, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            return controller
        }
        set {
            objc_setAssociatedObject(self, &Self.autoCaptureControllerKey, newValue, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        }
    }

    // MARK: - Setup

    /// Call this in startScanning() to enable auto-capture
    func setupAutoCapture() {
        print("🎯 Auto-Capture: Starting intelligent capture system")

        // Configure auto-capture based on scan quality preset
        let controller = autoCaptureController
        controller.delegate = self

        // Adjust thresholds based on user's scan quality setting
        switch scanQuality {
        case .performance:
            controller.qualityThreshold = 0.6  // Lower threshold for faster scanning
            controller.minFrameInterval = 0.15
        case .balanced:
            controller.qualityThreshold = 0.7  // Default
            controller.minFrameInterval = 0.1
        case .quality:
            controller.qualityThreshold = 0.75
            controller.minFrameInterval = 0.1
        case .maximum:
            controller.qualityThreshold = 0.8  // High threshold for best quality
            controller.minFrameInterval = 0.08
        }

        controller.start()
        print("   ✅ Auto-capture configured: quality=\(scanQuality.rawValue), threshold=\(controller.qualityThreshold)")
    }

    /// Call this from ARSession delegate to feed frames to auto-capture
    func feedARFrameToAutoCapture(_ frame: ARFrame) {
        guard scanState == .scanning else { return }

        // Feed frame to auto-capture controller
        // It will automatically trigger delegate callbacks when quality is good
        autoCaptureController.processFrame(frame)
    }

    // MARK: - AutoCaptureDelegate Implementation

    func autoCaptureDidTrigger() {
        // Frame captured automatically - no action needed
    }

    func autoCaptureDidUpdateProgress(_ progress: Double) {
        // Update UI with real-time progress
        self.scanProgress = max(self.scanProgress, progress)
    }

    func autoCaptureDidUpdateQuality(_ quality: Double) {
        // Update quality score
        self.qualityScore = max(self.qualityScore, quality)
    }

    func autoCaptureDidUpdateRecommendations(_ recommendations: [String]) {
        // Update user guidance
        self.recommendations = recommendations
    }

    func autoCaptureDidComplete() {
        print("✅ Auto-Capture Complete!")

        // Auto-capture has collected enough data - trigger completion
        self.scanProgress = 1.0

        // Show completion recommendation
        self.recommendations = ["Scan abgeschlossen! Tippen Sie auf 'Fertig', um die Ergebnisse zu sehen."]

        // Optionally auto-complete the scan (uncomment to enable):
        // DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
        //     self.completeScan()
        // }
    }

    // MARK: - Manual Completion Override

    /// Stop auto-capture (call when user manually stops scan)
    func stopAutoCapture() {
        autoCaptureController.stop()
        print("🛑 Auto-Capture: Stopped by user")
    }

    /// Reset auto-capture (call in reset())
    func resetAutoCapture() {
        autoCaptureController.stop()
        autoCaptureController.reset()
        print("🔄 Auto-Capture: Reset")
    }
}
