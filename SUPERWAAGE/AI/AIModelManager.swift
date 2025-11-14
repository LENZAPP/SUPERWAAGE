//
// AIModelManager.swift
// SUPERWAAGE
//
// Central manager to load and manage Core ML models
// Provides centralized access to Vision/CoreML models for segmentation, denoising, classification
//
// Usage:
//   try AIModelManager.shared.load(model: .foodSegmentation, filename: "FoodSegmenter")
//   let request = AIModelManager.shared.makeRequest(for: .foodSegmentation) { ... }
//

import Foundation
import Vision
import CoreML
import UIKit

/// Types of AI models supported by SUPERWAAGE
public enum AIModelType {
    case foodSegmentation        // Custom U-Net / DeepLab for food/object segmentation
    case pointCloudDenoiser      // Model that accepts Nx3 points -> Nx3 denoised points
    case foodClassifier          // Classifier to identify food/material type
    case meshRefinement          // Advanced mesh refinement model (future)
}

/// Centralized Core ML model manager
/// Loads models once and provides reusable Vision requests
@MainActor
public final class AIModelManager {
    public static let shared = AIModelManager()

    // Loaded VNCoreMLModel instances (Vision-compatible)
    private var visionModels: [AIModelType: VNCoreMLModel] = [:]

    // Raw MLModel instances (for direct inference)
    private var mlModels: [AIModelType: MLModel] = [:]

    private init() {}

    // MARK: - Model Loading

    /// Load a Core ML model from the app bundle
    /// - Parameters:
    ///   - type: Type of model to load
    ///   - filename: Model filename (without .mlmodelc extension)
    /// - Throws: Error if model not found or failed to load
    public func load(model type: AIModelType, filename: String) throws {
        // Try with .mlmodelc extension first (compiled model)
        var modelURL = Bundle.main.url(forResource: filename, withExtension: "mlmodelc")

        // Fallback to .mlmodel (uncompiled)
        if modelURL == nil {
            modelURL = Bundle.main.url(forResource: filename, withExtension: "mlmodel")
        }

        guard let url = modelURL else {
            throw AIModelError.modelNotFound(filename)
        }

        // Load MLModel
        let mlModel = try MLModel(contentsOf: url)
        mlModels[type] = mlModel

        // Create VNCoreMLModel for Vision integration
        let vnModel = try VNCoreMLModel(for: mlModel)
        visionModels[type] = vnModel

        print("✅ AIModelManager: Loaded \(type) from \(filename)")
    }

    /// Check if a model is loaded
    public func isLoaded(_ type: AIModelType) -> Bool {
        return visionModels[type] != nil
    }

    // MARK: - Vision Request Creation

    /// Create a Vision request for the specified model type
    /// - Parameters:
    ///   - type: Model type
    ///   - completion: Completion handler for request results
    /// - Returns: VNRequest configured for this model, or nil if model not loaded
    public func makeRequest(for type: AIModelType,
                           completion: @escaping (VNRequest, Error?) -> Void) -> VNRequest? {
        guard let vnModel = visionModels[type] else {
            print("⚠️ AIModelManager: Model \(type) not loaded")
            return nil
        }

        switch type {
        case .foodSegmentation:
            // Segmentation model that returns pixel buffer observation
            let req = VNCoreMLRequest(model: vnModel) { req, err in
                completion(req, err)
            }
            req.imageCropAndScaleOption = .scaleFill
            return req

        case .pointCloudDenoiser:
            // Point-cloud denoiser uses direct MLModel inference, not Vision
            return nil

        case .foodClassifier:
            // Classification model
            let req = VNCoreMLRequest(model: vnModel) { req, err in
                completion(req, err)
            }
            req.imageCropAndScaleOption = .centerCrop
            return req

        case .meshRefinement:
            // Future: mesh refinement via Core ML
            return nil
        }
    }

    // MARK: - Direct Model Access

    /// Get raw MLModel for direct inference (e.g., point cloud denoising)
    /// - Parameter type: Model type
    /// - Returns: MLModel instance or nil if not loaded
    public func mlModel(for type: AIModelType) -> MLModel? {
        return mlModels[type]
    }

    /// Get VNCoreMLModel for Vision-based inference
    /// - Parameter type: Model type
    /// - Returns: VNCoreMLModel instance or nil if not loaded
    public func visionModel(for type: AIModelType) -> VNCoreMLModel? {
        return visionModels[type]
    }

    // MARK: - Batch Processing

    /// Unload a specific model to free memory
    public func unload(_ type: AIModelType) {
        visionModels.removeValue(forKey: type)
        mlModels.removeValue(forKey: type)
        print("🗑️ AIModelManager: Unloaded \(type)")
    }

    /// Unload all models
    public func unloadAll() {
        visionModels.removeAll()
        mlModels.removeAll()
        print("🗑️ AIModelManager: Unloaded all models")
    }

    // MARK: - Model Info

    /// Get model description
    public func modelDescription(for type: AIModelType) -> String? {
        guard let model = mlModels[type] else { return nil }
        return model.modelDescription.metadata[MLModelMetadataKey.description] as? String
    }

    /// Get model input feature names
    public func inputFeatures(for type: AIModelType) -> [String] {
        guard let model = mlModels[type] else { return [] }
        return Array(model.modelDescription.inputDescriptionsByName.keys)
    }

    /// Get model output feature names
    public func outputFeatures(for type: AIModelType) -> [String] {
        guard let model = mlModels[type] else { return [] }
        return Array(model.modelDescription.outputDescriptionsByName.keys)
    }
}

// MARK: - Errors

public enum AIModelError: LocalizedError {
    case modelNotFound(String)
    case modelLoadFailed(String)
    case incompatibleModelFormat(String)

    public var errorDescription: String? {
        switch self {
        case .modelNotFound(let name):
            return "Core ML model '\(name)' not found in app bundle"
        case .modelLoadFailed(let reason):
            return "Failed to load Core ML model: \(reason)"
        case .incompatibleModelFormat(let details):
            return "Incompatible model format: \(details)"
        }
    }
}

// MARK: - Convenience Extensions

extension AIModelType: CustomStringConvertible {
    public var description: String {
        switch self {
        case .foodSegmentation: return "Food Segmentation"
        case .pointCloudDenoiser: return "Point Cloud Denoiser"
        case .foodClassifier: return "Food Classifier"
        case .meshRefinement: return "Mesh Refinement"
        }
    }
}
