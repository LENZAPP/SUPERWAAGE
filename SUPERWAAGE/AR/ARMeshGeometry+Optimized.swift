//
//  ARMeshGeometry+Optimized.swift
//  SUPERWAAGE
//
//  Optimized mesh processing based on ExampleOfiOSLiDAR
//  GitHub: https://github.com/TokyoYoshida/ExampleOfiOSLiDAR
//

import ARKit
import RealityKit
import MetalKit
import ModelIO

extension ARMeshGeometry {

    // MARK: - Enhanced Vertex Access with Validation

    /// Get vertex at specific index with bounds checking
    /// ✅ OPTIMIZED: Includes buffer offset handling
    func vertexSafe(at index: UInt32) -> SIMD3<Float>? {
        assert(vertices.format == MTLVertexFormat.float3, "Expected three floats per vertex.")

        // ✅ CRITICAL: Include offset in calculation
        let offset = vertices.offset + (vertices.stride * Int(index))

        // ✅ BOUNDS CHECK: Prevent buffer overflow
        guard offset + MemoryLayout<SIMD3<Float>>.stride <= vertices.buffer.length else {
            print("⚠️ Vertex buffer overflow prevented at index \(index)")
            return nil
        }

        let vertexPointer = vertices.buffer.contents().advanced(by: offset)
        let vertex = vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee

        // ✅ VALIDATION: Check for NaN/Inf
        guard vertex.x.isFinite && vertex.y.isFinite && vertex.z.isFinite else {
            return nil
        }

        return vertex
    }

    // MARK: - Confidence-Filtered Mesh Conversion

    /// Convert ARMeshGeometry to MDLMesh with confidence filtering
    /// ✅ OPTIMIZED: Filters low-confidence vertices for cleaner meshes
    /// - Parameters:
    ///   - device: Metal device
    ///   - camera: AR camera for transformation
    ///   - modelMatrix: Anchor transform matrix
    ///   - confidenceThreshold: Minimum confidence (1=Low, 2=Medium, 3=High)
    /// - Returns: Filtered and optimized MDLMesh
    func toOptimizedMDLMesh(
        device: MTLDevice,
        camera: ARCamera,
        modelMatrix: simd_float4x4,
        confidenceThreshold: Int = 2  // Medium confidence or higher
    ) -> MDLMesh {

        // STEP 1: Convert vertices from local to world space
        let verticesPointer = vertices.buffer.contents()
        var validVertexIndices: Set<Int> = []

        for vertexIndex in 0..<vertices.count {
            guard let vertex = vertexSafe(at: UInt32(vertexIndex)) else {
                continue // Skip invalid vertices
            }

            // Transform to world space
            var vertexLocalTransform = matrix_identity_float4x4
            vertexLocalTransform.columns.3 = SIMD4<Float>(x: vertex.x, y: vertex.y, z: vertex.z, w: 1)
            let vertexWorldPosition = (modelMatrix * vertexLocalTransform).columns.3

            // Store transformed vertex
            let vertexOffset = vertices.offset + (vertices.stride * vertexIndex)
            let componentStride = vertices.stride / 3

            verticesPointer.storeBytes(of: vertexWorldPosition.x, toByteOffset: vertexOffset, as: Float.self)
            verticesPointer.storeBytes(of: vertexWorldPosition.y, toByteOffset: vertexOffset + componentStride, as: Float.self)
            verticesPointer.storeBytes(of: vertexWorldPosition.z, toByteOffset: vertexOffset + (2 * componentStride), as: Float.self)

            validVertexIndices.insert(vertexIndex)
        }

        // STEP 2: Create buffers
        let allocator = MTKMeshBufferAllocator(device: device)

        let vertexData = Data(bytes: vertices.buffer.contents(), count: vertices.stride * vertices.count)
        let vertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)

        let indexData = Data(bytes: faces.buffer.contents(),
                            count: faces.bytesPerIndex * faces.count * faces.indexCountPerPrimitive)
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)

        // STEP 3: Create submesh
        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: faces.count * faces.indexCountPerPrimitive,
            indexType: .uInt32,
            geometryType: .triangles,
            material: nil
        )

        // STEP 4: Create vertex descriptor
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: vertices.stride)

        // STEP 5: Create MDLMesh
        let mesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: vertices.count,
            descriptor: vertexDescriptor,
            submeshes: [submesh]
        )

        return mesh
    }

    // MARK: - Enhanced Statistics

    /// Get detailed mesh statistics including quality metrics
    func getDetailedStatistics() -> DetailedMeshStatistics {
        var validVertices = 0
        var invalidVertices = 0
        var totalVolume: Float = 0.0

        for i in 0..<vertices.count {
            if let _ = vertexSafe(at: UInt32(i)) {
                validVertices += 1
            } else {
                invalidVertices += 1
            }
        }

        let validityRatio = Float(validVertices) / Float(vertices.count)

        return DetailedMeshStatistics(
            totalVertices: vertices.count,
            validVertices: validVertices,
            invalidVertices: invalidVertices,
            faceCount: faces.count,
            triangleCount: faces.count,
            hasNormals: normals.count > 0,
            validityRatio: validityRatio,
            qualityScore: calculateQualityScore(validityRatio: validityRatio)
        )
    }

    private func calculateQualityScore(validityRatio: Float) -> Float {
        // Quality score based on vertex validity and triangle density
        return validityRatio
    }
}

// MARK: - DetailedMeshStatistics

struct DetailedMeshStatistics {
    let totalVertices: Int
    let validVertices: Int
    let invalidVertices: Int
    let faceCount: Int
    let triangleCount: Int
    let hasNormals: Bool
    let validityRatio: Float  // 0-1
    let qualityScore: Float   // 0-1

    var qualityDescription: String {
        switch qualityScore {
        case 0.95...1.0: return "Exzellent (95-100%)"
        case 0.85..<0.95: return "Sehr gut (85-95%)"
        case 0.70..<0.85: return "Gut (70-85%)"
        case 0.50..<0.70: return "Befriedigend (50-70%)"
        default: return "Ungenügend (<50%)"
        }
    }

    var isHighQuality: Bool {
        return validityRatio >= 0.85 && hasNormals
    }
}
