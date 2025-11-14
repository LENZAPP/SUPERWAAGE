//
//  VisionContourDetector.swift
//  SUPERWAAGE
//
//  Vision Framework based contour and object detection
//  for automatic calibration object recognition
//

import Foundation
import Vision
import CoreImage
import UIKit
import ARKit

/// Detects reference objects using Vision framework
class VisionContourDetector {

    // MARK: - Rectangle Detection

    /// Detect rectangular objects (bank cards, cubes)
    func detectRectangle(in pixelBuffer: CVPixelBuffer) async throws -> ContourDetectionResult? {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectRectanglesRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNRectangleObservation],
                      let bestMatch = observations.first else {
                    continuation.resume(returning: nil)
                    return
                }

                // Convert observation to ContourDetectionResult
                let imageSize = CGSize(
                    width: CVPixelBufferGetWidth(pixelBuffer),
                    height: CVPixelBufferGetHeight(pixelBuffer)
                )
                let result = self.convertRectangleObservation(bestMatch, imageSize: imageSize)
                continuation.resume(returning: result)
            }

            // Configure for best accuracy
            request.minimumAspectRatio = 0.3
            request.maximumAspectRatio = 3.0
            request.minimumSize = 0.1  // At least 10% of image
            request.maximumObservations = 1

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Detect circular objects (coins)
    func detectCircle(in pixelBuffer: CVPixelBuffer) async throws -> ContourDetectionResult? {
        return try await withCheckedThrowingContinuation { continuation in
            let request = VNDetectContoursRequest { request, error in
                if let error = error {
                    continuation.resume(throwing: error)
                    return
                }

                guard let observations = request.results as? [VNContoursObservation] else {
                    continuation.resume(returning: nil)
                    return
                }

                // Find best circular contour
                let bestCircle = self.findBestCircularContour(observations)
                if let circle = bestCircle {
                    let imageSize = CGSize(
                        width: CVPixelBufferGetWidth(pixelBuffer),
                        height: CVPixelBufferGetHeight(pixelBuffer)
                    )
                    let result = self.convertContourObservation(circle, imageSize: imageSize)
                    continuation.resume(returning: result)
                } else {
                    continuation.resume(returning: nil)
                }
            }

            // Configure for contour detection
            request.contrastAdjustment = 1.5
            request.detectsDarkOnLight = true

            let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])
            do {
                try handler.perform([request])
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Detect reference object automatically (try rectangle first, then circle)
    func detectReferenceObject(
        in pixelBuffer: CVPixelBuffer,
        expectedType: ReferenceObjectType
    ) async throws -> ContourDetectionResult? {
        switch expectedType.dimensions.shape {
        case .rectangular:
            return try await detectRectangle(in: pixelBuffer)
        case .circular:
            return try await detectCircle(in: pixelBuffer)
        }
    }

    // MARK: - Private Helpers

    private func convertRectangleObservation(_ observation: VNRectangleObservation, imageSize: CGSize) -> ContourDetectionResult {
        let boundingBox = observation.boundingBox

        // Convert corner points to contour
        let contourPoints = [
            observation.topLeft,
            observation.topRight,
            observation.bottomRight,
            observation.bottomLeft
        ]

        // Calculate pixel dimensions
        let pixelWidth = Float(boundingBox.width * imageSize.width)
        let pixelHeight = Float(boundingBox.height * imageSize.height)

        return ContourDetectionResult(
            boundingBox: boundingBox,
            confidence: observation.confidence,
            contourPoints: contourPoints,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }

    private func convertContourObservation(_ observation: VNContoursObservation, imageSize: CGSize) -> ContourDetectionResult {
        // Extract contour points
        var contourPoints: [CGPoint] = []

        if let contour = observation.topLevelContours.first {
            let normalizedPoints = contour.normalizedPoints
            contourPoints = normalizedPoints.map { CGPoint(x: CGFloat($0.x), y: CGFloat($0.y)) }
        }

        // Estimate bounding box from contour
        let boundingBox = self.boundingBox(for: contourPoints)

        // Calculate pixel dimensions
        let pixelWidth = Float(boundingBox.width * imageSize.width)
        let pixelHeight = Float(boundingBox.height * imageSize.height)

        return ContourDetectionResult(
            boundingBox: boundingBox,
            confidence: observation.confidence,
            contourPoints: contourPoints,
            pixelWidth: pixelWidth,
            pixelHeight: pixelHeight
        )
    }

    private func findBestCircularContour(_ observations: [VNContoursObservation]) -> VNContoursObservation? {
        // Score contours by how circular they are
        let scored = observations.map { observation -> (observation: VNContoursObservation, score: Float) in
            guard let contour = observation.topLevelContours.first else {
                return (observation, 0.0)
            }

            let circularity = self.calculateCircularity(contour: contour)
            return (observation, circularity * observation.confidence)
        }

        return scored.max(by: { $0.score < $1.score })?.observation
    }

    private func calculateCircularity(contour: VNContour) -> Float {
        // Circularity = 4π × Area / Perimeter²
        // Perfect circle = 1.0, less circular < 1.0

        // Calculate area from points
        let points = contour.normalizedPoints
        guard points.count > 2 else { return 0 }

        // Simple polygon area calculation (Shoelace formula)
        var area: Float = 0
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            area += points[i].x * points[j].y
            area -= points[j].x * points[i].y
        }
        area = abs(area) / 2.0

        // Calculate perimeter
        var perimeter: Float = 0
        for i in 0..<points.count {
            let j = (i + 1) % points.count
            let dx = points[j].x - points[i].x
            let dy = points[j].y - points[i].y
            perimeter += sqrt(dx * dx + dy * dy)
        }

        guard perimeter > 0 else { return 0 }

        let circularity = (4.0 * Float.pi * area) / (perimeter * perimeter)
        return min(1.0, circularity)
    }

    private func boundingBox(for points: [CGPoint]) -> CGRect {
        guard !points.isEmpty else { return .zero }

        let minX = points.map { $0.x }.min() ?? 0
        let maxX = points.map { $0.x }.max() ?? 0
        let minY = points.map { $0.y }.min() ?? 0
        let maxY = points.map { $0.y }.max() ?? 0

        return CGRect(
            x: minX,
            y: minY,
            width: maxX - minX,
            height: maxY - minY
        )
    }
}

// MARK: - Helpers

/// Get display size of pixel buffer
private func getDisplaySize(_ pixelBuffer: CVPixelBuffer) -> CGSize {
    return CGSize(
        width: CVPixelBufferGetWidth(pixelBuffer),
        height: CVPixelBufferGetHeight(pixelBuffer)
    )
}
