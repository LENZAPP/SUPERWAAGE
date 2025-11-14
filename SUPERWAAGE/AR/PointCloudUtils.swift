//
//  PointCloudUtils.swift
//  SUPERWAAGE
//
//  Utilities for point cloud processing:
//  - Voxel downsampling for memory optimization
//  - Quick volume estimation via voxel counting
//  - PLY file export for debugging and external processing
//
//  Usage:
//    let downsampled = PointCloudUtils.voxelDownsample(points: filteredPoints, voxelSize: 0.005)
//    try PointCloudUtils.writePLY(points: downsampled, url: exportURL)
//    let volumeM3 = PointCloudUtils.voxelCountVolume(points: downsampled, voxelSize: 0.005)
//

import Foundation
import simd
import ARKit

public enum PointCloudUtils {

    /// Voxel-grid downsampling: groups points into voxels and picks centroid per voxel
    /// This dramatically reduces point count while preserving shape
    /// - Parameters:
    ///   - points: Input point cloud in world space (meters)
    ///   - voxelSize: Voxel size in meters (e.g., 0.005 = 5mm voxels)
    /// - Returns: Downsampled point cloud
    public static func voxelDownsample(points: [SIMD3<Float>], voxelSize: Float) -> [SIMD3<Float>] {
        guard !points.isEmpty, voxelSize > 0 else { return points }

        var dict = [VoxelKey: (sum: SIMD3<Float>, count: Int)]()
        dict.reserveCapacity(points.count / 4)

        for p in points {
            let key = VoxelKey.from(point: p, voxelSize: voxelSize)
            if var entry = dict[key] {
                entry.sum += p
                entry.count += 1
                dict[key] = entry
            } else {
                dict[key] = (sum: p, count: 1)
            }
        }

        var out: [SIMD3<Float>] = []
        out.reserveCapacity(dict.count)

        for (_, e) in dict {
            out.append(e.sum / Float(e.count))
        }

        return out
    }

    /// Compute approximate volume (m³) by counting occupied voxels
    /// This is a quick estimate best used with well-sampled surface points
    /// - Parameters:
    ///   - points: Point cloud in world space (meters)
    ///   - voxelSize: Voxel size in meters
    /// - Returns: Estimated volume in cubic meters
    public static func voxelCountVolume(points: [SIMD3<Float>], voxelSize: Float) -> Float {
        guard !points.isEmpty, voxelSize > 0 else { return 0 }

        var set = Set<VoxelKey>()
        set.reserveCapacity(points.count)

        for p in points {
            set.insert(VoxelKey.from(point: p, voxelSize: voxelSize))
        }

        let voxelCount = Float(set.count)
        let voxelVolume = voxelSize * voxelSize * voxelSize

        return voxelCount * voxelVolume
    }

    /// Write simple ASCII PLY (vertex-only) to disk
    /// Suitable for small/medium point clouds, can be imported into MeshLab, CloudCompare, etc.
    /// - Parameters:
    ///   - points: Point cloud to export
    ///   - url: File URL to write to
    nonisolated public static func writePLY(points: [SIMD3<Float>], url: URL) throws {
        var s = ""
        s += "ply\n"
        s += "format ascii 1.0\n"
        s += "element vertex \(points.count)\n"
        s += "property float x\n"
        s += "property float y\n"
        s += "property float z\n"
        s += "end_header\n"

        for p in points {
            s += "\(p.x) \(p.y) \(p.z)\n"
        }

        try s.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Write PLY with vertices and triangles (mesh export)
    /// - Parameters:
    ///   - vertices: Vertex positions
    ///   - triangles: Triangle indices (triplets of vertex indices)
    ///   - url: Output file URL
    nonisolated public static func writePLY(vertices: [SIMD3<Float>], triangles: [UInt32], url: URL) throws {
        var s = ""
        s += "ply\n"
        s += "format ascii 1.0\n"
        s += "element vertex \(vertices.count)\n"
        s += "property float x\n"
        s += "property float y\n"
        s += "property float z\n"

        if triangles.count > 0 {
            let faceCount = triangles.count / 3
            s += "element face \(faceCount)\n"
            s += "property list uchar int vertex_indices\n"
        }

        s += "end_header\n"

        // Write vertices
        for p in vertices {
            s += "\(p.x) \(p.y) \(p.z)\n"
        }

        // Write faces
        if triangles.count > 0 {
            for i in stride(from: 0, to: triangles.count, by: 3) {
                let a = triangles[i], b = triangles[i+1], c = triangles[i+2]
                s += "3 \(a) \(b) \(c)\n"
            }
        }

        try s.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Write PLY with normals (if available)
    /// - Parameters:
    ///   - points: Point cloud
    ///   - normals: Normal vectors (must match points count)
    ///   - url: Output file URL
    nonisolated public static func writePLYWithNormals(points: [SIMD3<Float>], normals: [SIMD3<Float>], url: URL) throws {
        guard points.count == normals.count else {
            throw NSError(domain: "PointCloudUtils", code: -1,
                         userInfo: [NSLocalizedDescriptionKey: "Points and normals count mismatch"])
        }

        var s = ""
        s += "ply\n"
        s += "format ascii 1.0\n"
        s += "element vertex \(points.count)\n"
        s += "property float x\n"
        s += "property float y\n"
        s += "property float z\n"
        s += "property float nx\n"
        s += "property float ny\n"
        s += "property float nz\n"
        s += "end_header\n"

        for i in 0..<points.count {
            let p = points[i]
            let n = normals[i]
            s += "\(p.x) \(p.y) \(p.z) \(n.x) \(n.y) \(n.z)\n"
        }

        try s.write(to: url, atomically: true, encoding: .utf8)
    }

    /// Calculate bounding box of point cloud
    /// - Parameter points: Input points
    /// - Returns: (min, max) corners of AABB
    public static func boundingBox(points: [SIMD3<Float>]) -> (min: SIMD3<Float>, max: SIMD3<Float>)? {
        guard !points.isEmpty else { return nil }

        var minP = points[0]
        var maxP = points[0]

        for p in points {
            minP = min(minP, p)
            maxP = max(maxP, p)
        }

        return (min: minP, max: maxP)
    }

    /// Calculate centroid of point cloud
    /// - Parameter points: Input points
    /// - Returns: Average position
    public static func centroid(points: [SIMD3<Float>]) -> SIMD3<Float>? {
        guard !points.isEmpty else { return nil }

        var sum = SIMD3<Float>(0, 0, 0)
        for p in points {
            sum += p
        }

        return sum / Float(points.count)
    }
}

// MARK: - Private Helper

/// Integer voxel key for spatial hashing
fileprivate struct VoxelKey: Hashable {
    let x: Int
    let y: Int
    let z: Int

    static func from(point p: SIMD3<Float>, voxelSize: Float) -> VoxelKey {
        // Floor division to bucket coordinates
        let ix = Int(floor(p.x / voxelSize))
        let iy = Int(floor(p.y / voxelSize))
        let iz = Int(floor(p.z / voxelSize))
        return VoxelKey(x: ix, y: iy, z: iz)
    }
}
