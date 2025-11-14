//
//  ARMeshGeometry+Extensions.swift
//  SUPERWAAGE
//
//  Advanced 3D mesh generation from LiDAR data
//  Adapted from ExampleOfiOSLiDAR-main
//

import ARKit
import RealityKit
import MetalKit
import ModelIO

extension ARMeshGeometry {

    // MARK: - Vertex Access

    /// Get vertex at specific index
    func vertex(at index: UInt32) -> SIMD3<Float> {
        assert(vertices.format == MTLVertexFormat.float3, "Expected three floats per vertex.")
        let vertexPointer = vertices.buffer.contents()
            .advanced(by: vertices.offset + (vertices.stride * Int(index)))
        return vertexPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
    }

    /// Get normal at specific index
    func normal(at index: UInt32) -> SIMD3<Float> {
        assert(normals.format == MTLVertexFormat.float3, "Expected three floats per normal.")
        let normalPointer = normals.buffer.contents()
            .advanced(by: normals.offset + (normals.stride * Int(index)))
        return normalPointer.assumingMemoryBound(to: SIMD3<Float>.self).pointee
    }

    // MARK: - MDLMesh Conversion (For Export)

    /// Convert ARMeshGeometry to MDLMesh for export
    /// - Parameters:
    ///   - device: Metal device
    ///   - camera: AR camera for coordinate transformation
    ///   - modelMatrix: Anchor's transform matrix
    /// - Returns: MDLMesh ready for export
    func toMDLMesh(device: MTLDevice, camera: ARCamera, modelMatrix: simd_float4x4) -> MDLMesh {

        // Convert vertices from local to world coordinates
        let verticesPointer = vertices.buffer.contents()

        for vertexIndex in 0..<vertices.count {
            let vertex = self.vertex(at: UInt32(vertexIndex))

            // Create transform matrix for vertex
            var vertexLocalTransform = matrix_identity_float4x4
            vertexLocalTransform.columns.3 = SIMD4<Float>(x: vertex.x, y: vertex.y, z: vertex.z, w: 1)

            // Transform to world space
            let vertexWorldPosition = (modelMatrix * vertexLocalTransform).columns.3

            // Store transformed coordinates
            let vertexOffset = vertices.offset + vertices.stride * vertexIndex
            let componentStride = vertices.stride / 3

            verticesPointer.storeBytes(of: vertexWorldPosition.x, toByteOffset: vertexOffset, as: Float.self)
            verticesPointer.storeBytes(of: vertexWorldPosition.y, toByteOffset: vertexOffset + componentStride, as: Float.self)
            verticesPointer.storeBytes(of: vertexWorldPosition.z, toByteOffset: vertexOffset + (2 * componentStride), as: Float.self)
        }

        // Create Metal buffer allocator
        let allocator = MTKMeshBufferAllocator(device: device)

        // Create vertex buffer
        let vertexData = Data(bytes: vertices.buffer.contents(), count: vertices.stride * vertices.count)
        let vertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)

        // Create index buffer
        let indexData = Data(bytes: faces.buffer.contents(),
                            count: faces.bytesPerIndex * faces.count * faces.indexCountPerPrimitive)
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)

        // Create submesh
        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: faces.count * faces.indexCountPerPrimitive,
            indexType: .uInt32,
            geometryType: .triangles,
            material: nil
        )

        // Create vertex descriptor
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: vertices.stride)

        // Create MDLMesh
        let mesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: vertices.count,
            descriptor: vertexDescriptor,
            submeshes: [submesh]
        )

        return mesh
    }

    // MARK: - Enhanced MDLMesh with Normals & Colors

    /// Convert to MDLMesh with normals and vertex colors
    func toEnhancedMDLMesh(device: MTLDevice, camera: ARCamera, modelMatrix: simd_float4x4) -> MDLMesh {

        let allocator = MTKMeshBufferAllocator(device: device)

        // Vertex data with normals
        struct VertexWithNormal {
            var position: SIMD3<Float>
            var normal: SIMD3<Float>
        }

        var verticesWithNormals: [VertexWithNormal] = []

        for vertexIndex in 0..<vertices.count {
            let localVertex = vertex(at: UInt32(vertexIndex))
            let localNormal = normal(at: UInt32(vertexIndex))

            // Transform to world space
            var vertexTransform = matrix_identity_float4x4
            vertexTransform.columns.3 = SIMD4<Float>(localVertex.x, localVertex.y, localVertex.z, 1)
            let worldPosition = (modelMatrix * vertexTransform).columns.3

            // Transform normal (no translation)
            let normalTransform = SIMD4<Float>(localNormal.x, localNormal.y, localNormal.z, 0)
            let worldNormal = (modelMatrix * normalTransform)

            verticesWithNormals.append(VertexWithNormal(
                position: SIMD3<Float>(worldPosition.x, worldPosition.y, worldPosition.z),
                normal: normalize(SIMD3<Float>(worldNormal.x, worldNormal.y, worldNormal.z))
            ))
        }

        // Create buffers
        let vertexData = Data(bytes: &verticesWithNormals,
                             count: MemoryLayout<VertexWithNormal>.stride * verticesWithNormals.count)
        let vertexBuffer = allocator.newBuffer(with: vertexData, type: .vertex)

        let indexData = Data(bytes: faces.buffer.contents(),
                            count: faces.bytesPerIndex * faces.count * faces.indexCountPerPrimitive)
        let indexBuffer = allocator.newBuffer(with: indexData, type: .index)

        // Submesh
        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: faces.count * faces.indexCountPerPrimitive,
            indexType: .uInt32,
            geometryType: .triangles,
            material: nil
        )

        // Vertex descriptor with normals
        let vertexDescriptor = MDLVertexDescriptor()
        vertexDescriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )
        vertexDescriptor.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: .float3,
            offset: MemoryLayout<SIMD3<Float>>.stride,
            bufferIndex: 0
        )
        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: MemoryLayout<VertexWithNormal>.stride)

        let mesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: vertices.count,
            descriptor: vertexDescriptor,
            submeshes: [submesh]
        )

        return mesh
    }

    // MARK: - Extract Point Cloud

    /// Extract point cloud from mesh
    func extractPointCloud(modelMatrix: simd_float4x4) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []

        for vertexIndex in 0..<vertices.count {
            let localVertex = vertex(at: UInt32(vertexIndex))

            // Transform to world space
            var vertexTransform = matrix_identity_float4x4
            vertexTransform.columns.3 = SIMD4<Float>(localVertex.x, localVertex.y, localVertex.z, 1)
            let worldPosition = (modelMatrix * vertexTransform).columns.3

            points.append(SIMD3<Float>(worldPosition.x, worldPosition.y, worldPosition.z))
        }

        return points
    }

    // MARK: - Mesh Statistics

    /// Get mesh quality metrics
    func getMeshStatistics() -> MeshStatistics {
        return MeshStatistics(
            vertexCount: vertices.count,
            faceCount: faces.count,
            triangleCount: faces.count, // Each face is a triangle
            hasNormals: normals.count > 0
        )
    }
}

// MARK: - Mesh Statistics
struct MeshStatistics {
    let vertexCount: Int
    let faceCount: Int
    let triangleCount: Int
    let hasNormals: Bool

    var isHighQuality: Bool {
        return vertexCount > 1000 && hasNormals
    }

    var qualityDescription: String {
        switch vertexCount {
        case 0..<100: return "Sehr niedrig"
        case 100..<500: return "Niedrig"
        case 500..<2000: return "Mittel"
        case 2000..<10000: return "Gut"
        default: return "Sehr gut"
        }
    }
}
