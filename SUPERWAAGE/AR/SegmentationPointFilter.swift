//
//  SegmentationPointFilter.swift
//  SUPERWAAGE
//
//  Advanced point cloud filtering using Vision segmentation
//  Removes background points for more accurate object measurement
//

import Foundation
import Vision
import CoreML
import UIKit
import ARKit
import simd

/// Segmentation mode for filtering point clouds
public enum SegmentationMode {
    case person                           // Vision's built-in person/foreground segmentation
    case object                           // Generic object segmentation (foreground detection)
}

/// High-performance point cloud filter using Vision framework segmentation
@MainActor
public final class SegmentationPointFilter {
    private let mode: SegmentationMode
    nonisolated(unsafe) private var request: VNRequest?
    private let queue = DispatchQueue(label: "com.superwaage.segmentation", qos: .userInitiated)

    // Cache for performance
    nonisolated(unsafe) private var lastMask: CVPixelBuffer?
    nonisolated(unsafe) private var lastProcessedTime: TimeInterval = 0
    private let minProcessingInterval: TimeInterval = 0.1  // Process every 100ms max

    /// Create a filter
    public init(mode: SegmentationMode = .object) {
        self.mode = mode
        setupVisionRequest()
    }

    private func setupVisionRequest() {
        switch mode {
        case .person:
            let req = VNGeneratePersonSegmentationRequest()
            req.qualityLevel = .balanced         // Balance speed vs accuracy
            req.outputPixelFormat = kCVPixelFormatType_OneComponent8
            self.request = req

        case .object:
            // Use foreground detection (available iOS 15+)
            if #available(iOS 15.0, *) {
                let req = VNGenerateForegroundInstanceMaskRequest()
                // Note: Instance mask request doesn't support outputPixelFormat
                self.request = req
            } else {
                // Fallback to person segmentation
                let req = VNGeneratePersonSegmentationRequest()
                req.qualityLevel = .balanced
                req.outputPixelFormat = kCVPixelFormatType_OneComponent8
                self.request = req
            }
        }
    }

    /// Run segmentation on a CVPixelBuffer (camera image)
    public func segment(pixelBuffer: CVPixelBuffer,
                       orientation: CGImagePropertyOrientation = .right,
                       completion: @escaping (CVPixelBuffer?) -> Void) {

        // Throttle processing
        let now = CACurrentMediaTime()
        guard now - lastProcessedTime >= minProcessingInterval else {
            completion(lastMask)
            return
        }
        lastProcessedTime = now

        queue.async { [weak self] in
            guard let self = self, let request = self.request else {
                DispatchQueue.main.async { completion(nil) }
                return
            }

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer,
                                               orientation: orientation,
                                               options: [:])
            do {
                try handler.perform([request])

                // Extract mask from results
                if let res = request.results?.first as? VNPixelBufferObservation {
                    DispatchQueue.main.async {
                        self.lastMask = res.pixelBuffer
                        completion(res.pixelBuffer)
                    }
                    return
                }

                // iOS 15+ instance mask handling
                if #available(iOS 15.0, *) {
                    if let instanceRes = request.results?.first as? VNInstanceMaskObservation {
                        // Generate pixel buffer from instance mask
                        do {
                            let pixelBuffer = try instanceRes.generateMaskedImage(
                                ofInstances: instanceRes.allInstances,
                                from: handler,
                                croppedToInstancesExtent: false
                            )
                            DispatchQueue.main.async {
                                self.lastMask = pixelBuffer
                                completion(pixelBuffer)
                            }
                            return
                        } catch {
                            print("⚠️ Failed to generate masked image: \(error)")
                        }
                    }
                }

                DispatchQueue.main.async { completion(nil) }

            } catch {
                print("⚠️ Segmentation error: \(error)")
                DispatchQueue.main.async { completion(nil) }
            }
        }
    }

    /// Filter 3D points using segmentation mask
    public func filterPoints(_ points: [SIMD3<Float>],
                            frame: ARFrame,
                            mask: CVPixelBuffer,
                            viewportSize: CGSize,
                            maskThreshold: UInt8 = 128) -> [SIMD3<Float>] {

        guard !points.isEmpty else { return [] }

        var filtered: [SIMD3<Float>] = []
        filtered.reserveCapacity(points.count)

        let maskW = CVPixelBufferGetWidth(mask)
        let maskH = CVPixelBufferGetHeight(mask)

        // Lock mask for reading
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(mask) else { return [] }
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)

        // Project each point and check mask
        for point in points {
            // Project 3D point to 2D image coordinates
            let imagePoint = frame.camera.projectPoint(
                point,
                orientation: .landscapeRight,  // Adjust based on device orientation
                viewportSize: viewportSize
            )

            // Convert to camera pixel coordinates
            let nx = imagePoint.x / viewportSize.width
            let ny = imagePoint.y / viewportSize.height

            // Map to mask coordinates
            let mx = Int(nx * CGFloat(maskW))
            let my = Int(ny * CGFloat(maskH))

            // Bounds check
            guard mx >= 0, mx < maskW, my >= 0, my < maskH else { continue }

            // Sample mask value
            let ptr = baseAddress.advanced(by: my * rowBytes + mx)
            let maskValue = ptr.load(as: UInt8.self)

            // Include point if mask value exceeds threshold
            if maskValue >= maskThreshold {
                filtered.append(point)
            }
        }

        return filtered
    }

    /// Helper to sample mask value at specific coordinates
    public static func maskValue(atX x: Int, y: Int, mask: CVPixelBuffer) -> UInt8 {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        let w = CVPixelBufferGetWidth(mask)
        let h = CVPixelBufferGetHeight(mask)
        guard x >= 0, x < w, y >= 0, y < h else { return 0 }

        guard let base = CVPixelBufferGetBaseAddress(mask) else { return 0 }
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)
        let ptr = base.advanced(by: y * rowBytes + x)
        return ptr.load(as: UInt8.self)
    }

    /// Calculate coverage percentage (what % of points are in foreground)
    public func calculateCoverage(mask: CVPixelBuffer) -> Float {
        CVPixelBufferLockBaseAddress(mask, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(mask, .readOnly) }

        let w = CVPixelBufferGetWidth(mask)
        let h = CVPixelBufferGetHeight(mask)
        guard let base = CVPixelBufferGetBaseAddress(mask) else { return 0.0 }
        let rowBytes = CVPixelBufferGetBytesPerRow(mask)

        var foregroundPixels = 0
        let totalPixels = w * h

        for y in 0..<h {
            let rowPtr = base.advanced(by: y * rowBytes)
            for x in 0..<w {
                let val = rowPtr.advanced(by: x).load(as: UInt8.self)
                if val > 128 {
                    foregroundPixels += 1
                }
            }
        }

        return Float(foregroundPixels) / Float(totalPixels)
    }
}

// MARK: - CGImagePropertyOrientation Helper

fileprivate extension CGImagePropertyOrientation {
    init(from deviceOrientation: UIDeviceOrientation) {
        switch deviceOrientation {
        case .portrait: self = .right
        case .portraitUpsideDown: self = .left
        case .landscapeLeft: self = .up
        case .landscapeRight: self = .down
        default: self = .right
        }
    }

    init(from ui: UIInterfaceOrientation) {
        switch ui {
        case .portrait: self = .right
        case .portraitUpsideDown: self = .left
        case .landscapeLeft: self = .up
        case .landscapeRight: self = .down
        default: self = .right
        }
    }
}
