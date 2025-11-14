//
// VoxelSmoothingDenoiser.swift
// SUPERWAAGE
//
// Fast, pure-Swift voxel-hash spatial smoothing denoiser for point clouds.
// No ML, no external deps — suitable as a quick on-device denoiser before TSDF integration.
//
// Usage:
//   let denoiser = VoxelSmoothingDenoiser(voxelSize: 0.005, neighborRadius: 0.01)
//   let cleaned = denoiser.denoise(points: filteredPoints, iterations: 2)
//   tsdf.integratePointsApprox(points: cleaned)
//
// Notes:
// - voxelSize influences hash bucket size (smaller -> more buckets).
// - neighborRadius is the radius used to average neighbors (meters).
// - iterations controls repeated smoothing passes (1..3 typical).
//

import Foundation
import simd

/// Fast spatial smoothing denoiser using voxel-based spatial hashing
/// Removes noise from LiDAR point clouds while preserving shape features
public final class VoxelSmoothingDenoiser {

    public let voxelSize: Float            // cell size for spatial hash
    public let neighborRadius: Float       // neighbor search radius (meters)
    public let blendAlpha: Float           // blend original vs neighbor average (0..1)

    /// Create denoiser.
    /// - Parameters:
    ///   - voxelSize: Spatial hash cell size in meters (e.g. 0.005 = 5mm)
    ///   - neighborRadius: Neighbor search radius in meters (e.g. 0.01 = 1cm)
    ///   - blendAlpha: Weight for original point when blending (0.5..0.9 recommended)
    ///                Higher values preserve sharp features, lower values smooth more
    public init(voxelSize: Float = 0.005, neighborRadius: Float = 0.01, blendAlpha: Float = 0.6) {
        precondition(voxelSize > 0 && neighborRadius > 0, "voxelSize and neighborRadius must be positive")
        precondition(blendAlpha >= 0 && blendAlpha <= 1, "blendAlpha must be in [0, 1]")

        self.voxelSize = voxelSize
        self.neighborRadius = neighborRadius
        self.blendAlpha = min(max(blendAlpha, 0.0), 1.0)
    }

    /// Main entry: denoise a point list.
    /// - Parameters:
    ///   - points: Input world-space points (meters)
    ///   - iterations: Number of smoothing passes (1..3 typical, 1 is often sufficient)
    /// - Returns: Denoised point list with same length as input
    public func denoise(points: [SIMD3<Float>], iterations: Int = 1) -> [SIMD3<Float>] {
        guard !points.isEmpty else { return points }

        var pts = points
        let iters = max(1, iterations)

        for _ in 0..<iters {
            pts = smoothOnce(points: pts)
        }

        return pts
    }

    // MARK: - Private Implementation

    /// Single smoothing pass using spatial hash acceleration
    private func smoothOnce(points: [SIMD3<Float>]) -> [SIMD3<Float>] {
        // Build spatial hash: VoxelKey -> indices
        var hash = [VoxelKey: [Int]]()
        hash.reserveCapacity(points.count)

        for (i, p) in points.enumerated() {
            let key = VoxelKey.from(point: p, voxelSize: voxelSize)
            hash[key, default: []].append(i)
        }

        let r2 = neighborRadius * neighborRadius
        var out = points

        // For each point, check neighbors in 3x3x3 voxel neighborhood
        for (i, p) in points.enumerated() {
            let centerKey = VoxelKey.from(point: p, voxelSize: voxelSize)
            var sum = SIMD3<Float>(0, 0, 0)
            var count: Int = 0

            // Examine 27 neighbor voxels (3x3x3 cube around center)
            for dx in -1...1 {
                for dy in -1...1 {
                    for dz in -1...1 {
                        let nk = VoxelKey(x: centerKey.x + dx,
                                        y: centerKey.y + dy,
                                        z: centerKey.z + dz)

                        guard let bucket = hash[nk] else { continue }

                        for idx in bucket {
                            let q = points[idx]
                            let d2 = distanceSquared(p, q)

                            if d2 <= r2 {
                                sum += q
                                count += 1
                            }
                        }
                    }
                }
            }

            if count > 0 {
                let avg = sum / Float(count)
                // Blend to preserve edges/features
                // High blendAlpha = more original point (sharper)
                // Low blendAlpha = more averaging (smoother)
                out[i] = blendAlpha * p + (1.0 - blendAlpha) * avg
            } else {
                // No neighbors found, keep original point
                out[i] = p
            }
        }

        return out
    }

    /// Fast squared-distance computation (avoids sqrt)
    @inline(__always)
    private func distanceSquared(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> Float {
        let d = a - b
        return dot(d, d)
    }

    // MARK: - Public Utilities

    /// Estimate appropriate parameters for object size
    /// - Parameter objectSizeMeters: Approximate object diameter in meters
    /// - Returns: Suggested (voxelSize, neighborRadius, blendAlpha)
    public static func recommendedParameters(for objectSizeMeters: Float) -> (voxelSize: Float, neighborRadius: Float, blendAlpha: Float) {
        // Rule of thumb: voxelSize ~ 0.5% of object size
        let voxelSize = objectSizeMeters * 0.005
        let neighborRadius = voxelSize * 2.0
        let blendAlpha: Float = 0.6

        return (voxelSize, neighborRadius, blendAlpha)
    }
}

// MARK: - Spatial Hash Key

/// Integer voxel key for efficient spatial hashing
fileprivate struct VoxelKey: Hashable {
    let x: Int
    let y: Int
    let z: Int

    init(x: Int, y: Int, z: Int) {
        self.x = x
        self.y = y
        self.z = z
    }

    /// Create voxel key from world-space point
    static func from(point p: SIMD3<Float>, voxelSize: Float) -> VoxelKey {
        let ix = Int(floor(p.x / voxelSize))
        let iy = Int(floor(p.y / voxelSize))
        let iz = Int(floor(p.z / voxelSize))
        return VoxelKey(x: ix, y: iy, z: iz)
    }
}

// MARK: - Integration Helper

public extension VoxelSmoothingDenoiser {

    /// Smooth then integrate points into TSDF (convenience method)
    /// - Parameters:
    ///   - points: Incoming filtered points (world-space)
    ///   - tsdf: TSDFVolume instance to integrate into
    ///   - iterations: Smoothing passes (default 1)
    ///   - weight: TSDF integration weight
    func smoothAndIntegrate(points: [SIMD3<Float>],
                           into tsdf: TSDFVolume,
                           iterations: Int = 1,
                           weight: Float = 1.0) {
        guard !points.isEmpty else { return }

        // 1. Denoise (fast, on-device)
        let cleaned = self.denoise(points: points, iterations: iterations)

        // 2. Integrate cleaned points into TSDF
        tsdf.integratePointsApprox(points: cleaned, weight: weight)
    }
}
