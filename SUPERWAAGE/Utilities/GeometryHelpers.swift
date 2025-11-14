//
//  GeometryHelpers.swift
//  SUPERWAAGE
//
//  Geometry calculation helpers adapted from various repos
//

import Foundation
import simd

// MARK: - Type Aliases
typealias Float2 = SIMD2<Float>
typealias Float3 = SIMD3<Float>
typealias Float4 = SIMD4<Float>

// MARK: - SIMD Extensions
extension SIMD3 where Scalar == Float {
    /// Calculate distance between two points
    func distance(to other: SIMD3<Float>) -> Float {
        return simd_distance(self, other)
    }

    /// Normalize the vector
    var normalized: SIMD3<Float> {
        return simd_normalize(self)
    }

    /// Length of the vector
    var length: Float {
        return simd_length(self)
    }

    /// Cross product
    func cross(_ other: SIMD3<Float>) -> SIMD3<Float> {
        return simd_cross(self, other)
    }
}

// MARK: - Matrix Extensions
extension matrix_float3x3 {
    mutating func copy(from affine: CGAffineTransform) {
        columns.0 = Float3(Float(affine.a), Float(affine.c), Float(affine.tx))
        columns.1 = Float3(Float(affine.b), Float(affine.d), Float(affine.ty))
        columns.2 = Float3(0, 0, 1)
    }
}

extension matrix_float4x4 {
    /// Extract translation from transformation matrix
    var translation: Float3 {
        return Float3(columns.3.x, columns.3.y, columns.3.z)
    }

    /// Extract scale from transformation matrix
    var scale: Float3 {
        let sx = simd_length(Float3(columns.0.x, columns.0.y, columns.0.z))
        let sy = simd_length(Float3(columns.1.x, columns.1.y, columns.1.z))
        let sz = simd_length(Float3(columns.2.x, columns.2.y, columns.2.z))
        return Float3(sx, sy, sz)
    }
}

// MARK: - Geometry Calculations
struct GeometryHelpers {
    /// Calculate volume of a tetrahedron
    static func tetrahedronVolume(
        p1: Float3,
        p2: Float3,
        p3: Float3,
        p4: Float3
    ) -> Float {
        let v1 = p2 - p1
        let v2 = p3 - p1
        let v3 = p4 - p1
        return abs(dot(v1, simd_cross(v2, v3))) / 6.0
    }

    /// Calculate area of a triangle
    static func triangleArea(
        p1: Float3,
        p2: Float3,
        p3: Float3
    ) -> Float {
        let v1 = p2 - p1
        let v2 = p3 - p1
        let crossProduct = simd_cross(v1, v2)
        return simd_length(crossProduct) / 2.0
    }

    /// Calculate bounding box from points
    static func boundingBox(points: [Float3]) -> (min: Float3, max: Float3)? {
        guard !points.isEmpty else { return nil }

        var minPoint = points[0]
        var maxPoint = points[0]

        for point in points {
            minPoint = Float3(
                min(minPoint.x, point.x),
                min(minPoint.y, point.y),
                min(minPoint.z, point.z)
            )
            maxPoint = Float3(
                max(maxPoint.x, point.x),
                max(maxPoint.y, point.y),
                max(maxPoint.z, point.z)
            )
        }

        return (minPoint, maxPoint)
    }

    /// Calculate centroid of points
    static func centroid(points: [Float3]) -> Float3? {
        guard !points.isEmpty else { return nil }

        var sum = Float3.zero
        for point in points {
            sum += point
        }

        return sum / Float(points.count)
    }

    /// Check if point is inside bounding box
    static func isPointInBounds(
        point: Float3,
        min: Float3,
        max: Float3
    ) -> Bool {
        return point.x >= min.x && point.x <= max.x &&
               point.y >= min.y && point.y <= max.y &&
               point.z >= min.z && point.z <= max.z
    }

    /// Convert meters to centimeters
    static func metersToCentimeters(_ meters: Float) -> Float {
        return meters * 100.0
    }

    /// Convert centimeters to meters
    static func centimetersToMeters(_ centimeters: Float) -> Float {
        return centimeters / 100.0
    }

    /// Convert cubic meters to cubic centimeters
    static func cubicMetersToCubicCentimeters(_ cubicMeters: Float) -> Float {
        return cubicMeters * 1_000_000.0
    }

    /// Convert cubic centimeters to liters
    static func cubicCentimetersToLiters(_ cubicCentimeters: Float) -> Float {
        return cubicCentimeters / 1000.0
    }
}

// MARK: - Mesh Geometry Helper
struct MeshGeometry {
    var vertices: [Float3]
    var normals: [Float3]
    var faces: [[Int]]

    init(vertices: [Float3], normals: [Float3] = [], faces: [[Int]] = []) {
        self.vertices = vertices
        self.normals = normals
        self.faces = faces
    }

    /// Calculate surface area of the mesh
    func surfaceArea() -> Float {
        var area: Float = 0.0

        for face in faces where face.count >= 3 {
            let p1 = vertices[face[0]]
            let p2 = vertices[face[1]]
            let p3 = vertices[face[2]]
            area += GeometryHelpers.triangleArea(p1: p1, p2: p2, p3: p3)
        }

        return area
    }

    /// Calculate volume using signed volume method
    func signedVolume() -> Float {
        var volume: Float = 0.0

        for face in faces where face.count >= 3 {
            let p1 = vertices[face[0]]
            let p2 = vertices[face[1]]
            let p3 = vertices[face[2]]

            // Signed volume of tetrahedron formed with origin
            let v = p1.x * (p2.y * p3.z - p2.z * p3.y) +
                    p2.x * (p3.y * p1.z - p3.z * p1.y) +
                    p3.x * (p1.y * p2.z - p1.z * p2.y)

            volume += v
        }

        return abs(volume) / 6.0
    }
}

// MARK: - Voxel Grid
class VoxelGrid {
    let voxelSize: Float
    var voxels: Set<SIMD3<Int>>

    init(voxelSize: Float = 0.005) {  // 5mm default
        self.voxelSize = voxelSize
        self.voxels = Set<SIMD3<Int>>()
    }

    /// Add point to voxel grid
    func addPoint(_ point: Float3) {
        let voxelCoord = worldToVoxel(point)
        voxels.insert(voxelCoord)
    }

    /// Add multiple points
    func addPoints(_ points: [Float3]) {
        for point in points {
            addPoint(point)
        }
    }

    /// Convert world coordinates to voxel coordinates
    func worldToVoxel(_ point: Float3) -> SIMD3<Int> {
        return SIMD3<Int>(
            Int(floor(point.x / voxelSize)),
            Int(floor(point.y / voxelSize)),
            Int(floor(point.z / voxelSize))
        )
    }

    /// Convert voxel coordinates to world coordinates
    func voxelToWorld(_ voxel: SIMD3<Int>) -> Float3 {
        return Float3(
            Float(voxel.x) * voxelSize,
            Float(voxel.y) * voxelSize,
            Float(voxel.z) * voxelSize
        )
    }

    /// Calculate total volume
    func calculateVolume() -> Float {
        let voxelVolume = voxelSize * voxelSize * voxelSize
        return Float(voxels.count) * voxelVolume
    }

    /// Get bounding box of voxel grid
    func boundingBox() -> (min: SIMD3<Int>, max: SIMD3<Int>)? {
        guard !voxels.isEmpty else { return nil }

        var minVoxel = voxels.first!
        var maxVoxel = voxels.first!

        for voxel in voxels {
            minVoxel = SIMD3<Int>(
                min(minVoxel.x, voxel.x),
                min(minVoxel.y, voxel.y),
                min(minVoxel.z, voxel.z)
            )
            maxVoxel = SIMD3<Int>(
                max(maxVoxel.x, voxel.x),
                max(maxVoxel.y, voxel.y),
                max(maxVoxel.z, voxel.z)
            )
        }

        return (minVoxel, maxVoxel)
    }

    /// Clear all voxels
    func clear() {
        voxels.removeAll()
    }
}
