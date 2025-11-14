//
//  CoreMLRunner.swift
//  SUPERWAAGE
//
//  Thread-safe Core ML runner with throttling to prevent GPU saturation
//  Provides segmentation inference with automatic fallback
//

import Foundation
import CoreML
import Vision
import CoreVideo
import ARKit

/// Thread-safe Core ML runner for object segmentation
/// Throttles inference to prevent GPU saturation and maintain 30-60 FPS
@MainActor
class CoreMLRunner {

    // MARK: - Singleton

    static let shared = CoreMLRunner()

    // MARK: - Properties

    private var segmentationModel: VNCoreMLModel?
    private var lastInferenceTime: Date = .distantPast
    private let minInferenceInterval: TimeInterval = 0.2 // 200ms = 5 FPS max

    private var isProcessing = false
    private var modelLoaded = false

    // MARK: - Initialization

    init() {
        Task {
            await loadModel()
        }
    }

    // MARK: - Model Loading

    /// Attempt to load segmentation model (DeepLabV3, etc.)
    /// Falls back gracefully if no model available
    private func loadModel() async {
        // Try to load DeepLabV3 model (iOS 12+)
        do {
            // Check if DeepLabV3 model is available
            if let modelURL = Bundle.main.url(forResource: "DeepLabV3", withExtension: "mlmodelc") {
                let model = try MLModel(contentsOf: modelURL)
                segmentationModel = try VNCoreMLModel(for: model)
                modelLoaded = true
                print("✅ CoreMLRunner: DeepLabV3 model loaded")
            } else {
                print("⚠️ CoreMLRunner: No ML model found - using feature-based fallback")
            }
        } catch {
            print("⚠️ CoreMLRunner: Failed to load model - \(error.localizedDescription)")
            print("   Using feature-based segmentation fallback")
        }
    }

    // MARK: - Public Interface

    /// Run segmentation on pixel buffer with throttling
    /// - Parameters:
    ///   - pixelBuffer: Camera image to segment
    ///   - completion: Called with segmentation mask (or nil if throttled/failed)
    func runSegmentation(
        pixelBuffer: CVPixelBuffer,
        completion: @escaping (CVPixelBuffer?) -> Void
    ) {
        // Throttle: Skip if too soon since last inference
        let now = Date()
        guard now.timeIntervalSince(lastInferenceTime) >= minInferenceInterval else {
            completion(nil) // Throttled
            return
        }

        // Skip if already processing
        guard !isProcessing else {
            completion(nil)
            return
        }

        lastInferenceTime = now
        isProcessing = true

        // If no model loaded, return nil (fallback to feature-based)
        guard modelLoaded, let model = segmentationModel else {
            isProcessing = false
            completion(nil) // Use fallback
            return
        }

        // Run inference in background
        Task.detached(priority: .utility) { [weak self] in
            guard let self = self else { return }
            let mask = await self.performInference(pixelBuffer: pixelBuffer, model: model)

            // CVPixelBuffer is thread-safe at runtime despite not being marked Sendable
            await MainActor.run { [weak self] in
                guard let self = self else { return }
                self.isProcessing = false
                completion(mask)  // CVPixelBuffer is actually thread-safe
            }
        }
    }

    // MARK: - Private Inference

    /// Perform actual ML inference
    private func performInference(
        pixelBuffer: CVPixelBuffer,
        model: VNCoreMLModel
    ) async -> CVPixelBuffer? {
        return await withCheckedContinuation { continuation in
            let request = VNCoreMLRequest(model: model) { request, error in
                if let error = error {
                    print("⚠️ CoreMLRunner inference error: \(error.localizedDescription)")
                    continuation.resume(returning: nil)
                    return
                }

                guard let results = request.results as? [VNPixelBufferObservation],
                      let mask = results.first?.pixelBuffer else {
                    continuation.resume(returning: nil)
                    return
                }

                continuation.resume(returning: mask)
            }

            // Configure request
            request.imageCropAndScaleOption = .scaleFit

            // Perform request
            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([request])
            } catch {
                print("⚠️ CoreMLRunner: Request failed - \(error.localizedDescription)")
                continuation.resume(returning: nil)
            }
        }
    }
}

// MARK: - Usage Example

/*

 // In your ARSession delegate:

 func session(_ session: ARSession, didUpdate frame: ARFrame) {
     let pixelBuffer = frame.capturedImage

     CoreMLRunner.shared.runSegmentation(pixelBuffer: pixelBuffer) { mask in
         guard let mask = mask else {
             // Throttled or no model - use fallback
             return
         }

         // Use segmentation mask
         self.processSegmentationMask(mask)
     }
 }

 */
