//
// PointCloudDenoiserCoreML.swift
// SUPERWAAGE
//
// Intelligent point cloud denoiser with Core ML model support and automatic fallback
// Uses ML-based denoising when model is available, otherwise falls back to VoxelSmoothingDenoiser
//
// Expected ML Model Format:
//   Input: MLMultiArray shape [N, 3] or [3*N] - point positions
//   Output: MLMultiArray shape [N, 3] or [3*N] - denoised positions
//
// Usage:
//   let denoiser = PointCloudDenoiserCoreML()
//   let cleaned = denoiser.denoise(points: noisyPoints)
//

import Foundation
import CoreML
import simd

/// Hybrid point cloud denoiser supporting both ML and traditional approaches
public final class PointCloudDenoiserCoreML {

    private var mlModel: MLModel?
    private let fallbackDenoiser: VoxelSmoothingDenoiser

    // Performance metrics
    public private(set) var lastDenoiseTime: TimeInterval = 0
    public private(set) var usedMLModel: Bool = false

    /// Initialize denoiser with optional Core ML model
    /// If no ML model is loaded, automatically uses fast VoxelSmoothingDenoiser
    public init() {
        // Try to get ML model from AIModelManager
        self.mlModel = AIModelManager.shared.mlModel(for: .pointCloudDenoiser)

        // Always prepare fallback denoiser
        self.fallbackDenoiser = VoxelSmoothingDenoiser(
            voxelSize: 0.005,        // 5mm spatial hash
            neighborRadius: 0.010,   // 1cm neighbor radius
            blendAlpha: 0.6          // Balanced smoothing
        )

        if mlModel != nil {
            print("✅ PointCloudDenoiserCoreML: ML model loaded, will use ML-based denoising")
        } else {
            print("ℹ️ PointCloudDenoiserCoreML: No ML model, using fast VoxelSmoothingDenoiser")
        }
    }

    // MARK: - Public API

    /// Denoise a point cloud using best available method
    /// - Parameter points: Input point cloud (world space, meters)
    /// - Returns: Denoised point cloud
    public func denoise(points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        guard !points.isEmpty else { return points }

        let startTime = Date()
        var result: [SIMD3<Float>]

        // Try ML model first, fallback to VoxelSmoothingDenoiser
        if let model = mlModel {
            result = denoiseWithML(points: points, model: model)
            usedMLModel = true
        } else {
            result = fallbackDenoiser.denoise(points: points, iterations: 1)
            usedMLModel = false
        }

        lastDenoiseTime = Date().timeIntervalSince(startTime)
        return result
    }

    /// Denoise with specified number of iterations (fallback mode only)
    /// ML model doesn't support iterations (single-pass)
    public func denoise(points: [SIMD3<Float>], iterations: Int) -> [SIMD3<Float>] {
        guard !points.isEmpty else { return points }

        let startTime = Date()
        var result: [SIMD3<Float>]

        // ML model is single-pass, fallback supports iterations
        if let model = mlModel {
            result = denoiseWithML(points: points, model: model)
            usedMLModel = true
        } else {
            result = fallbackDenoiser.denoise(points: points, iterations: iterations)
            usedMLModel = false
        }

        lastDenoiseTime = Date().timeIntervalSince(startTime)
        return result
    }

    // MARK: - Private ML Implementation

    private func denoiseWithML(points: [SIMD3<Float>], model: MLModel) -> [SIMD3<Float>] {
        let n = points.count

        do {
            // Attempt to create MLMultiArray in shape [N, 3]
            let inputArray = try MLMultiArray(shape: [NSNumber(value: n), NSNumber(value: 3)],
                                             dataType: .float32)

            // Fill input array
            for i in 0..<n {
                let p = points[i]
                inputArray[i * 3 + 0] = NSNumber(value: p.x)
                inputArray[i * 3 + 1] = NSNumber(value: p.y)
                inputArray[i * 3 + 2] = NSNumber(value: p.z)
            }

            // Get input feature name (first input)
            let inputName = model.modelDescription.inputDescriptionsByName.keys.first ?? "input"

            // Create input provider
            let inputProvider = try MLDictionaryFeatureProvider(dictionary: [inputName: inputArray])

            // Run prediction
            let outputProvider = try model.prediction(from: inputProvider)

            // Extract output array
            guard let outputName = outputProvider.featureNames.first,
                  let outputArray = outputProvider.featureValue(for: outputName)?.multiArrayValue else {
                print("⚠️ ML denoiser: No output, falling back")
                return fallbackDenoiser.denoise(points: points, iterations: 1)
            }

            // Parse output based on shape
            var denoisedPoints: [SIMD3<Float>] = []
            denoisedPoints.reserveCapacity(n)

            if outputArray.shape.count == 2 && outputArray.shape[1].intValue == 3 {
                // Shape [N, 3]
                for i in 0..<n {
                    let x = outputArray[i * 3 + 0].floatValue
                    let y = outputArray[i * 3 + 1].floatValue
                    let z = outputArray[i * 3 + 2].floatValue
                    denoisedPoints.append(SIMD3<Float>(x, y, z))
                }
            } else if outputArray.count == n * 3 {
                // Flattened shape [3*N]
                for i in 0..<n {
                    let x = outputArray[i * 3 + 0].floatValue
                    let y = outputArray[i * 3 + 1].floatValue
                    let z = outputArray[i * 3 + 2].floatValue
                    denoisedPoints.append(SIMD3<Float>(x, y, z))
                }
            } else {
                // Unexpected output shape, fallback
                print("⚠️ ML denoiser: Unexpected output shape \(outputArray.shape), falling back")
                return fallbackDenoiser.denoise(points: points, iterations: 1)
            }

            return denoisedPoints

        } catch {
            // Any ML error: fallback to VoxelSmoothingDenoiser
            print("⚠️ ML denoiser error: \(error), using fallback")
            return fallbackDenoiser.denoise(points: points, iterations: 1)
        }
    }

    // MARK: - Utilities

    /// Get current denoising mode
    public var currentMode: DenoiserMode {
        return mlModel != nil ? .machineLearning : .voxelSmoothing
    }

    /// Get performance statistics
    public func getPerformanceStats() -> String {
        let mode = usedMLModel ? "ML" : "Voxel"
        return String(format: "%@ denoising: %.3fs", mode, lastDenoiseTime)
    }
}

// MARK: - Denoiser Mode

public enum DenoiserMode {
    case machineLearning    // Using Core ML model
    case voxelSmoothing     // Using fast VoxelSmoothingDenoiser

    public var description: String {
        switch self {
        case .machineLearning: return "Machine Learning"
        case .voxelSmoothing: return "Voxel Smoothing"
        }
    }
}
