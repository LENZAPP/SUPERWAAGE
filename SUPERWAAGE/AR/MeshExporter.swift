//
//  MeshExporter.swift
//  SUPERWAAGE
//
//  Professional 3D mesh export system
//  Supports OBJ, PLY, and USDZ formats
//  Now includes generic mesh export for TSDF/MarchingCubes output
//

import Foundation
import ARKit
import RealityKit
import SceneKit
import MetalKit
import ModelIO
import UIKit
import simd

// MARK: - Export Format
enum MeshExportFormat: String, CaseIterable {
    case obj = "OBJ (Wavefront)"
    case ply = "PLY (Polygon File)"
    case usdz = "USDZ (Apple AR)"

    var fileExtension: String {
        switch self {
        case .obj: return "obj"
        case .ply: return "ply"
        case .usdz: return "usdz"
        }
    }

    var uti: String {
        switch self {
        case .obj: return "public.geometry-definition-format"
        case .ply: return "public.polygon-file-format"
        case .usdz: return "com.pixar.universal-scene-description-mobile"
        }
    }
}

// MARK: - Export Result
struct MeshExportResult {
    let url: URL
    let format: MeshExportFormat
    let fileSize: Int64
    let vertexCount: Int
    let triangleCount: Int
    let exportDuration: TimeInterval
}

// MARK: - Mesh Exporter
class MeshExporter {

    // MARK: - Export Methods

    /// Export mesh anchors to file
    static func exportMeshAnchors(
        _ meshAnchors: [ARMeshAnchor],
        camera: ARCamera,
        format: MeshExportFormat = .obj,
        fileName: String? = nil
    ) throws -> MeshExportResult {

        let startTime = Date()
        guard let device = MTLCreateSystemDefaultDevice() else {
            throw ExportError.metalDeviceNotFound
        }

        // Convert to MDLAsset
        let asset = convertToAsset(meshAnchors: meshAnchors, device: device, camera: camera)

        // Generate filename
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let defaultName = "SUPERWAAGE_Scan_\(timestamp)"
        let filename = fileName ?? defaultName

        // Export to file
        let url = try export(asset: asset, filename: filename, format: format)

        // Calculate statistics
        let fileSize = try FileManager.default.attributesOfItem(atPath: url.path)[.size] as? Int64 ?? 0
        let vertexCount = meshAnchors.reduce(0) { $0 + $1.geometry.vertices.count }
        let triangleCount = meshAnchors.reduce(0) { $0 + $1.geometry.faces.count }
        let duration = Date().timeIntervalSince(startTime)

        return MeshExportResult(
            url: url,
            format: format,
            fileSize: fileSize,
            vertexCount: vertexCount,
            triangleCount: triangleCount,
            exportDuration: duration
        )
    }

    // MARK: - Private Helpers

    private static func convertToAsset(
        meshAnchors: [ARMeshAnchor],
        device: MTLDevice,
        camera: ARCamera
    ) -> MDLAsset {

        let asset = MDLAsset()

        // Combine all mesh anchors into a single unified mesh
        if let unifiedMesh = createUnifiedMDLMesh(from: meshAnchors, device: device) {
            unifiedMesh.name = "SUPERWAAGE_UnifiedMesh"
            asset.add(unifiedMesh)
        } else {
            // Fallback: Add meshes separately if unified creation fails
            for (index, anchor) in meshAnchors.enumerated() {
                let mdlMesh = anchor.geometry.toEnhancedMDLMesh(
                    device: device,
                    camera: camera,
                    modelMatrix: anchor.transform
                )

                mdlMesh.name = "MeshAnchor_\(index)"
                asset.add(mdlMesh)
            }
        }

        return asset
    }

    /// Create a single unified MDLMesh from all anchors with world-space transforms applied
    private static func createUnifiedMDLMesh(
        from anchors: [ARMeshAnchor],
        device: MTLDevice
    ) -> MDLMesh? {
        guard !anchors.isEmpty else { return nil }

        var allVertices: [SIMD3<Float>] = []
        var allNormals: [SIMD3<Float>] = []
        var allIndices: [UInt32] = []
        var currentVertexOffset: UInt32 = 0

        // Combine all anchors
        for anchor in anchors {
            let geometry = anchor.geometry
            let vertices = geometry.vertices
            let normals = geometry.normals
            let faces = geometry.faces
            let transform = anchor.transform

            // Transform vertices to world space
            for i in 0..<vertices.count {
                let vertex = vertices.buffer.contents()
                    .advanced(by: vertices.offset + i * vertices.stride)
                    .assumingMemoryBound(to: SIMD3<Float>.self).pointee

                let worldVertex = transform * SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1.0)
                allVertices.append(SIMD3<Float>(worldVertex.x, worldVertex.y, worldVertex.z))
            }

            // Transform normals to world space
            for i in 0..<normals.count {
                let normal = normals.buffer.contents()
                    .advanced(by: normals.offset + i * normals.stride)
                    .assumingMemoryBound(to: SIMD3<Float>.self).pointee

                let worldNormal = transform * SIMD4<Float>(normal.x, normal.y, normal.z, 0.0)
                let normalized = simd_normalize(SIMD3<Float>(worldNormal.x, worldNormal.y, worldNormal.z))
                allNormals.append(normalized)
            }

            // Add face indices with offset
            let faceBuffer = faces.buffer.contents()
            for i in 0..<faces.count {
                for j in 0..<faces.indexCountPerPrimitive {
                    let indexOffset = (i * faces.indexCountPerPrimitive + j) * faces.bytesPerIndex
                    let index: UInt32

                    if faces.bytesPerIndex == 2 {
                        index = UInt32(faceBuffer.advanced(by: indexOffset).assumingMemoryBound(to: UInt16.self).pointee)
                    } else {
                        index = faceBuffer.advanced(by: indexOffset).assumingMemoryBound(to: UInt32.self).pointee
                    }
                    allIndices.append(index + currentVertexOffset)
                }
            }

            currentVertexOffset += UInt32(vertices.count)
        }

        guard !allVertices.isEmpty && !allIndices.isEmpty else { return nil }

        // Create MDL vertex descriptor
        let vertexDescriptor = MDLVertexDescriptor()

        // Position attribute
        vertexDescriptor.attributes[0] = MDLVertexAttribute(
            name: MDLVertexAttributePosition,
            format: .float3,
            offset: 0,
            bufferIndex: 0
        )

        // Normal attribute
        vertexDescriptor.attributes[1] = MDLVertexAttribute(
            name: MDLVertexAttributeNormal,
            format: .float3,
            offset: MemoryLayout<SIMD3<Float>>.stride,
            bufferIndex: 0
        )

        vertexDescriptor.layouts[0] = MDLVertexBufferLayout(stride: 2 * MemoryLayout<SIMD3<Float>>.stride)

        // Create allocator
        let allocator = MTKMeshBufferAllocator(device: device)

        // Interleave vertices and normals
        var interleavedData: [Float] = []
        for i in 0..<allVertices.count {
            interleavedData.append(contentsOf: [allVertices[i].x, allVertices[i].y, allVertices[i].z])
            interleavedData.append(contentsOf: [allNormals[i].x, allNormals[i].y, allNormals[i].z])
        }

        // Create vertex buffer
        let vertexBuffer = allocator.newBuffer(
            with: Data(bytes: interleavedData, count: interleavedData.count * MemoryLayout<Float>.size),
            type: .vertex
        )

        // Create index buffer
        let indexBuffer = allocator.newBuffer(
            with: Data(bytes: allIndices, count: allIndices.count * MemoryLayout<UInt32>.size),
            type: .index
        )

        // Create submesh
        let submesh = MDLSubmesh(
            indexBuffer: indexBuffer,
            indexCount: allIndices.count,
            indexType: .uInt32,
            geometryType: .triangles,
            material: nil
        )

        // Create MDLMesh
        let mdlMesh = MDLMesh(
            vertexBuffer: vertexBuffer,
            vertexCount: allVertices.count,
            descriptor: vertexDescriptor,
            submeshes: [submesh]
        )

        return mdlMesh
    }

    private static func export(
        asset: MDLAsset,
        filename: String,
        format: MeshExportFormat
    ) throws -> URL {

        let directory = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
        let url = directory.appendingPathComponent("\(filename).\(format.fileExtension)")

        // Export based on format
        switch format {
        case .obj:
            try asset.export(to: url)

        case .usdz:
            // USDZ export (requires conversion)
            let tempURL = directory.appendingPathComponent("\(filename)_temp.obj")
            try asset.export(to: tempURL)

            // Convert OBJ to USDZ
            try convertOBJToUSDZ(objURL: tempURL, outputURL: url)

            // Clean up temp file
            try? FileManager.default.removeItem(at: tempURL)

        case .ply:
            // PLY export (custom implementation)
            try exportToPLY(asset: asset, url: url)
        }

        return url
    }

    // MARK: - PLY Export

    private static func exportToPLY(asset: MDLAsset, url: URL) throws {
        var plyContent = ""

        // Count total vertices and faces
        var totalVertices = 0
        var totalFaces = 0

        for i in 0..<asset.count {
            guard let mesh = asset[i] as? MDLMesh else { continue }
            totalVertices += mesh.vertexCount
            if let submeshes = mesh.submeshes as? [MDLSubmesh] {
                for mdlSubmesh in submeshes {
                    totalFaces += mdlSubmesh.indexCount / 3
                }
            }
        }

        // PLY Header
        plyContent += "ply\n"
        plyContent += "format ascii 1.0\n"
        plyContent += "comment Exported from SUPERWAAGE\n"
        plyContent += "element vertex \(totalVertices)\n"
        plyContent += "property float x\n"
        plyContent += "property float y\n"
        plyContent += "property float z\n"
        plyContent += "property float nx\n"
        plyContent += "property float ny\n"
        plyContent += "property float nz\n"
        plyContent += "element face \(totalFaces)\n"
        plyContent += "property list uchar int vertex_indices\n"
        plyContent += "end_header\n"

        // Export vertices and faces
        var vertexOffset = 0

        for i in 0..<asset.count {
            guard let mesh = asset[i] as? MDLMesh else { continue }

            // Extract vertices and normals
            guard let vertexAttribute = mesh.vertexDescriptor.attributes[0] as? MDLVertexAttribute,
                  let normalAttribute = mesh.vertexDescriptor.attributes[1] as? MDLVertexAttribute,
                  let vertexBuffer = mesh.vertexBuffers.first,
                  let layout = mesh.vertexDescriptor.layouts[0] as? MDLVertexBufferLayout else {
                continue
            }

            let vertexStride = layout.stride
            let vertexData = Data(bytesNoCopy: vertexBuffer.map().bytes,
                                 count: mesh.vertexCount * vertexStride,
                                 deallocator: .none)

            // Write vertices
            for i in 0..<mesh.vertexCount {
                let offset = i * vertexStride

                // Position
                let x = vertexData.withUnsafeBytes { $0.load(fromByteOffset: offset + Int(vertexAttribute.offset), as: Float.self) }
                let y = vertexData.withUnsafeBytes { $0.load(fromByteOffset: offset + Int(vertexAttribute.offset) + 4, as: Float.self) }
                let z = vertexData.withUnsafeBytes { $0.load(fromByteOffset: offset + Int(vertexAttribute.offset) + 8, as: Float.self) }

                // Normal
                let nx = vertexData.withUnsafeBytes { $0.load(fromByteOffset: offset + Int(normalAttribute.offset), as: Float.self) }
                let ny = vertexData.withUnsafeBytes { $0.load(fromByteOffset: offset + Int(normalAttribute.offset) + 4, as: Float.self) }
                let nz = vertexData.withUnsafeBytes { $0.load(fromByteOffset: offset + Int(normalAttribute.offset) + 8, as: Float.self) }

                plyContent += "\(x) \(y) \(z) \(nx) \(ny) \(nz)\n"
            }

            // Write faces
            if let submeshes = mesh.submeshes as? [MDLSubmesh] {
                for mdlSubmesh in submeshes {

                let indexBuffer = mdlSubmesh.indexBuffer
                let indexData = Data(bytesNoCopy: indexBuffer.map().bytes,
                                    count: mdlSubmesh.indexCount * MemoryLayout<UInt32>.size,
                                    deallocator: .none)

                for i in stride(from: 0, to: mdlSubmesh.indexCount, by: 3) {
                    let i0 = indexData.withUnsafeBytes { $0.load(fromByteOffset: i * 4, as: UInt32.self) }
                    let i1 = indexData.withUnsafeBytes { $0.load(fromByteOffset: (i + 1) * 4, as: UInt32.self) }
                    let i2 = indexData.withUnsafeBytes { $0.load(fromByteOffset: (i + 2) * 4, as: UInt32.self) }

                    plyContent += "3 \(i0 + UInt32(vertexOffset)) \(i1 + UInt32(vertexOffset)) \(i2 + UInt32(vertexOffset))\n"
                }
                }
            }

            vertexOffset += mesh.vertexCount
        }

        // Write to file
        try plyContent.write(to: url, atomically: true, encoding: .utf8)
    }

    // MARK: - USDZ Conversion

    private static func convertOBJToUSDZ(objURL: URL, outputURL: URL) throws {
        // This requires usdz_converter tool or MDLAsset conversion
        // For now, we'll use a simple approach

        let asset = MDLAsset(url: objURL)
        try asset.export(to: outputURL)
    }

    // MARK: - Generic Mesh Export (for TSDF/Marching Cubes)

    /// Export raw mesh data (vertices, triangles) to PLY format
    /// Useful for exporting TSDF-extracted meshes from MarchingCubesCPU
    ///
    /// - Parameters:
    ///   - vertices: Vertex positions
    ///   - triangles: Triangle indices (triplets)
    ///   - url: Output file URL
    static func exportPLY(vertices: [SIMD3<Float>], triangles: [UInt32], url: URL) throws {
        try PointCloudUtils.writePLY(vertices: vertices, triangles: triangles, url: url)
    }

    /// Create SceneKit node from raw mesh arrays (for visualization)
    /// Useful for displaying TSDF-extracted meshes in ARSCNView
    ///
    /// - Parameters:
    ///   - vertices: Vertex positions (world space)
    ///   - normals: Normal vectors (must match vertex count)
    ///   - triangles: Triangle indices (triplets)
    ///   - material: Optional custom material (defaults to teal PBR)
    /// - Returns: SCNNode with mesh geometry, or nil if invalid data
    static func makeSCNNode(vertices: [SIMD3<Float>],
                           normals: [SIMD3<Float>],
                           triangles: [UInt32],
                           material: SCNMaterial? = nil) -> SCNNode? {

        // Validation
        guard vertices.count == normals.count,
              !vertices.isEmpty,
              triangles.count % 3 == 0,
              !triangles.isEmpty else {
            print("⚠️ MeshExporter.makeSCNNode: Invalid mesh data")
            return nil
        }

        let vcount = vertices.count

        // Create vertex data
        let vertexData = Data(bytes: vertices, count: MemoryLayout<SIMD3<Float>>.stride * vcount)
        let vertexSource = SCNGeometrySource(
            data: vertexData,
            semantic: .vertex,
            vectorCount: vcount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.stride,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        // Create normal data
        let normalData = Data(bytes: normals, count: MemoryLayout<SIMD3<Float>>.stride * vcount)
        let normalSource = SCNGeometrySource(
            data: normalData,
            semantic: .normal,
            vectorCount: vcount,
            usesFloatComponents: true,
            componentsPerVector: 3,
            bytesPerComponent: MemoryLayout<Float>.stride,
            dataOffset: 0,
            dataStride: MemoryLayout<SIMD3<Float>>.stride
        )

        // Create triangle element
        let triData = Data(bytes: triangles, count: MemoryLayout<UInt32>.stride * triangles.count)
        let element = SCNGeometryElement(
            data: triData,
            primitiveType: .triangles,
            primitiveCount: triangles.count / 3,
            bytesPerIndex: MemoryLayout<UInt32>.stride
        )

        // Create geometry
        let geometry = SCNGeometry(sources: [vertexSource, normalSource], elements: [element])

        // Apply material
        let mat = material ?? {
            let m = SCNMaterial()
            m.diffuse.contents = UIColor.systemTeal
            m.lightingModel = .physicallyBased
            m.roughness.contents = 0.4
            m.metalness.contents = 0.1
            return m
        }()

        geometry.materials = [mat]

        // Create and return node
        let node = SCNNode(geometry: geometry)
        node.name = "TSDF_ExtractedMesh"

        return node
    }

    // MARK: - Share

    /// Share exported file
    static func shareExportedFile(_ result: MeshExportResult, from viewController: UIViewController, sourceView: UIView) {
        let activityVC = UIActivityViewController(activityItems: [result.url], applicationActivities: nil)
        activityVC.popoverPresentationController?.sourceView = sourceView
        viewController.present(activityVC, animated: true)
    }
}

// MARK: - Export Error
enum ExportError: LocalizedError {
    case metalDeviceNotFound
    case noMeshAnchorsAvailable
    case exportFailed(String)

    var errorDescription: String? {
        switch self {
        case .metalDeviceNotFound:
            return "Metal device nicht verfügbar"
        case .noMeshAnchorsAvailable:
            return "Keine Mesh-Daten zum Exportieren"
        case .exportFailed(let reason):
            return "Export fehlgeschlagen: \(reason)"
        }
    }
}
