//
//  TSDFVolume.swift
//  SUPERWAAGE
//
//  TSDF (Truncated Signed Distance Function) volume for accurate 3D reconstruction
//  Integrates multiple depth frames to build a high-quality volumetric representation
//
//  Usage:
//    let tsdf = TSDFVolume(dimX: 128, dimY: 128, dimZ: 128, voxelSize: 0.005, origin: worldOrigin)
//    // Per-frame integration:
//    tsdf.integrateDepth(depth: depthMap, intrinsics: intrinsics, cameraTransform: camTransform)
//    // After all frames integrated, extract mesh:
//    let (vertices, normals, triangles) = tsdf.extractMesh()
//

import Foundation
import simd
import ARKit
import CoreVideo

public final class TSDFVolume {

    // Grid dimensions
    public let dimX: Int
    public let dimY: Int
    public let dimZ: Int
    public let voxelSize: Float  // Voxel size in meters

    // World-space origin (position of grid[0,0,0])
    public let origin: SIMD3<Float>

    // Truncation distance in meters (typically 3-5 voxels)
    public let truncation: Float

    // TSDF and weight arrays (row-major, Z-fastest indexing)
    private var tsdf: [Float]       // Signed distance values
    private var weights: [Float]    // Integration weights
    private let count: Int          // Total voxel count

    /// Initialize TSDF volume
    /// - Parameters:
    ///   - dimX: Voxels along X axis
    ///   - dimY: Voxels along Y axis
    ///   - dimZ: Voxels along Z axis
    ///   - voxelSize: Voxel size in meters (e.g., 0.005 = 5mm)
    ///   - origin: World-space position of grid minimum corner
    ///   - truncation: Truncation distance (nil = auto 5x voxelSize)
    public init(dimX: Int = 128,
                dimY: Int = 128,
                dimZ: Int = 128,
                voxelSize: Float = 0.005,
                origin: SIMD3<Float> = SIMD3<Float>(0,0,0),
                truncation: Float? = nil) {

        // ✅ CRASH FIX: Validate parameters to prevent NaN/Infinite
        precondition(dimX > 0 && dimY > 0 && dimZ > 0, "TSDF dimensions must be positive")
        precondition(voxelSize > 0 && voxelSize.isFinite, "TSDF voxelSize must be positive and finite")
        precondition(origin.x.isFinite && origin.y.isFinite && origin.z.isFinite, "TSDF origin must be finite")

        self.dimX = dimX
        self.dimY = dimY
        self.dimZ = dimZ
        self.voxelSize = voxelSize
        self.origin = origin

        let computedTruncation = truncation ?? (voxelSize * 5.0)
        // ✅ CRASH FIX: Validate truncation
        precondition(computedTruncation > 0 && computedTruncation.isFinite, "TSDF truncation must be positive and finite")
        self.truncation = computedTruncation

        self.count = dimX * dimY * dimZ

        // Initialize TSDF to far positive (i.e., far from surface)
        self.tsdf = [Float](repeating: 1.0, count: count)
        self.weights = [Float](repeating: 0.0, count: count)
    }

    // MARK: - Indexing Helpers

    /// Convert 3D grid coordinates to flat array index
    private func index(x: Int, y: Int, z: Int) -> Int {
        return (x * dimY + y) * dimZ + z
    }

    /// Convert world-space point to voxel grid coordinates (floating-point)
    private func worldToVoxel(_ world: SIMD3<Float>) -> SIMD3<Float> {
        let local = world - origin
        return SIMD3<Float>(
            local.x / voxelSize,
            local.y / voxelSize,
            local.z / voxelSize
        )
    }

    /// Convert voxel grid coordinates to world-space (voxel center)
    private func voxelToWorld(ix: Int, iy: Int, iz: Int) -> SIMD3<Float> {
        return origin + SIMD3<Float>(
            Float(ix) + 0.5,
            Float(iy) + 0.5,
            Float(iz) + 0.5
        ) * voxelSize
    }

    // MARK: - Depth Integration

    /// Integrate a depth map into the TSDF volume
    /// This is the preferred method for accurate reconstruction
    /// - Parameters:
    ///   - depth: CVPixelBuffer containing depth data (Float32, meters)
    ///   - intrinsics: Camera intrinsic matrix (3x3)
    ///   - cameraTransform: World-from-camera transform (4x4)
    ///   - weightScale: Weight scaling factor for this frame
    public func integrateDepth(depth: CVPixelBuffer,
                              intrinsics: simd_float3x3,
                              cameraTransform: simd_float4x4,
                              weightScale: Float = 1.0) {

        CVPixelBufferLockBaseAddress(depth, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depth, .readOnly) }

        let width = CVPixelBufferGetWidth(depth)
        let height = CVPixelBufferGetHeight(depth)
        let rowBytes = CVPixelBufferGetBytesPerRow(depth)

        guard let depthBase = CVPixelBufferGetBaseAddress(depth) else { return }

        // Camera parameters
        let fx = intrinsics[0,0]
        let fy = intrinsics[1,1]
        let cx = intrinsics[2,0]
        let cy = intrinsics[2,1]

        // Inverse transform (world to camera)
        let worldToCam = simd_inverse(cameraTransform)

        // Integrate each voxel
        for x in 0..<dimX {
            for y in 0..<dimY {
                for z in 0..<dimZ {
                    let idx = index(x: x, y: y, z: z)

                    // Compute world position of voxel center
                    let voxelCenter = voxelToWorld(ix: x, iy: y, iz: z)

                    // Transform to camera space
                    let pCam4 = worldToCam * SIMD4<Float>(voxelCenter.x, voxelCenter.y, voxelCenter.z, 1.0)
                    let pCam = SIMD3<Float>(pCam4.x, pCam4.y, pCam4.z)

                    // Skip if behind camera
                    if pCam.z <= 0 { continue }

                    // Project to pixel coordinates
                    let u = Int(round((pCam.x * fx) / pCam.z + cx))
                    let v = Int(round((pCam.y * fy) / pCam.z + cy))

                    // Check bounds
                    if u < 0 || u >= width || v < 0 || v >= height { continue }

                    // Read depth value
                    let pixelPtr = depthBase.advanced(by: v * rowBytes + u * MemoryLayout<Float32>.stride)
                    let d = pixelPtr.load(as: Float32.self)

                    // Skip invalid depth
                    if d.isNaN || d <= 0 { continue }

                    // Compute signed distance
                    let sdf = Float(d) - pCam.z

                    // Skip if too far behind surface
                    if sdf <= -truncation { continue }

                    // Normalize to [-1, 1]
                    let tsdfVal = min(1.0, max(-1.0, sdf / truncation))

                    // Weighted average integration
                    let wOld = weights[idx]
                    let tOld = tsdf[idx]
                    let wNew = wOld + weightScale
                    let tNew = (tOld * wOld + tsdfVal * weightScale) / wNew

                    tsdf[idx] = tNew
                    weights[idx] = wNew
                }
            }
        }
    }

    /// Quick approximate integration from point cloud
    /// Less accurate than depth-based integration but faster
    /// - Parameters:
    ///   - points: World-space points (meters)
    ///   - weight: Weight for this integration
    public func integratePointsApprox(points: [SIMD3<Float>], weight: Float = 1.0) {
        // ✅ FIX: Calculate bounding box center to determine inside/outside
        guard !points.isEmpty else { return }

        var center = SIMD3<Float>.zero
        for p in points {
            center += p
        }
        center /= Float(points.count)

        // ✅ FIX: Process all voxels in a wider neighborhood to create proper SDF
        let radius = Int(ceil(truncation / voxelSize)) + 2

        for p in points {
            let v = worldToVoxel(p)
            let ix = Int(floor(v.x))
            let iy = Int(floor(v.y))
            let iz = Int(floor(v.z))

            // Bounds check for center point
            if ix < 0 || ix >= dimX || iy < 0 || iy >= dimY || iz < 0 || iz >= dimZ {
                continue
            }

            let idx = index(x: ix, y: iy, z: iz)

            // Mark voxel as on-surface (SDF = 0)
            let measured: Float = 0.0
            let wOld = weights[idx]
            let tOld = tsdf[idx]
            let wNew = wOld + weight
            let tNew = (tOld * wOld + measured * weight) / wNew

            tsdf[idx] = tNew
            weights[idx] = wNew

            // ✅ FIX: Update wider neighborhood with proper signed distance
            // Use expanded radius to capture more volume
            for dx in -radius...radius {
                for dy in -radius...radius {
                    for dz in -radius...radius {
                        let nx = ix + dx
                        let ny = iy + dy
                        let nz = iz + dz

                        if nx < 0 || nx >= dimX || ny < 0 || ny >= dimY || nz < 0 || nz >= dimZ {
                            continue
                        }

                        let idxN = index(x: nx, y: ny, z: nz)
                        let worldN = voxelToWorld(ix: nx, iy: ny, iz: nz)
                        let dist = length(worldN - p)

                        // ✅ CRITICAL FIX: Determine if voxel is inside or outside
                        // Voxels closer to center than the surface point are "inside" (negative SDF)
                        let distToCenter = length(worldN - center)
                        let surfaceDistToCenter = length(p - center)
                        let isInside = distToCenter < surfaceDistToCenter

                        // Compute signed distance
                        var sdf = min(truncation, dist)
                        if isInside {
                            sdf = -sdf  // ✅ Mark as inside the object
                        }

                        let tsdfVal = sdf / truncation

                        let wOldN = weights[idxN]
                        let tOldN = tsdf[idxN]
                        let neighborWeight = weight * 0.3 * exp(-dist / truncation) // Decay with distance
                        let wNewN = wOldN + neighborWeight

                        // ✅ CRASH FIX: Guard against division by zero
                        guard wNewN > 0 && wNewN.isFinite else { continue }

                        let tNewN = (tOldN * wOldN + tsdfVal * neighborWeight) / wNewN

                        tsdf[idxN] = tNewN
                        weights[idxN] = wNewN
                    }
                }
            }
        }
    }

    // MARK: - Mesh Extraction

    /// Extract mesh using marching cubes algorithm
    /// - Parameter isovalue: Surface threshold (typically 0.0)
    /// - Returns: Tuple of (vertices, normals, triangle indices)
    public func extractMesh(isovalue: Float = 0.0) -> (vertices: [SIMD3<Float>],
                                                        normals: [SIMD3<Float>],
                                                        triangles: [UInt32]) {

        // Convert normalized TSDF to signed distance in meters
        var sdfMeters = [Float](repeating: truncation, count: count)
        for i in 0..<count {
            sdfMeters[i] = tsdf[i] * truncation
        }

        // Run CPU marching cubes
        let mc = MarchingCubesCPU()
        let (verts, norms, tris) = mc.runMarchingCubes(
            sdf: sdfMeters,
            dimX: dimX,
            dimY: dimY,
            dimZ: dimZ,
            voxelSize: voxelSize,
            origin: origin,
            isovalue: isovalue
        )

        return (vertices: verts, normals: norms, triangles: tris)
    }

    // MARK: - Utility Methods

    /// Sample TSDF value at world-space coordinate
    /// - Parameter world: World-space position
    /// - Returns: TSDF value or nil if out of bounds
    public func sampleTSDF(world: SIMD3<Float>) -> Float? {
        let v = worldToVoxel(world)
        let ix = Int(floor(v.x))
        let iy = Int(floor(v.y))
        let iz = Int(floor(v.z))

        if ix < 0 || ix >= dimX || iy < 0 || iy >= dimY || iz < 0 || iz >= dimZ {
            return nil
        }

        return tsdf[index(x: ix, y: iy, z: iz)]
    }

    /// Get weight at world-space coordinate
    /// - Parameter world: World-space position
    /// - Returns: Weight value or nil if out of bounds
    public func sampleWeight(world: SIMD3<Float>) -> Float? {
        let v = worldToVoxel(world)
        let ix = Int(floor(v.x))
        let iy = Int(floor(v.y))
        let iz = Int(floor(v.z))

        if ix < 0 || ix >= dimX || iy < 0 || iy >= dimY || iz < 0 || iz >= dimZ {
            return nil
        }

        return weights[index(x: ix, y: iy, z: iz)]
    }

    /// Reset volume to initial state
    public func reset() {
        for i in 0..<count {
            tsdf[i] = 1.0
            weights[i] = 0.0
        }
    }
}
