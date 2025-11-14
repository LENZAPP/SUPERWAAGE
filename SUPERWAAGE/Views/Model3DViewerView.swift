//
//  Model3DViewerView.swift
//  SUPERWAAGE
//
//  Interactive 3D Model Viewer with 360° rotation
//  Allows user to view scanned object from all angles
//

import SwiftUI
import SceneKit
import ARKit

struct Model3DViewerView: View {
    @Environment(\.dismiss) var dismiss
    @EnvironmentObject var scanViewModel: ScanViewModel
    @State private var rotationAngleX: CGFloat = 0
    @State private var rotationAngleY: CGFloat = 0
    @State private var lastRotationX: CGFloat = 0
    @State private var lastRotationY: CGFloat = 0
    @State private var scale: CGFloat = 1.0
    @State private var showingExportOptions = false

    var body: some View {
        NavigationView {
            ZStack {
                Color.black.edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    // 3D Scene View
                    SceneKitView(
                        meshAnchors: scanViewModel.meshAnchors,
                        rotationX: rotationAngleX,
                        rotationY: rotationAngleY,
                        scale: scale
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                rotationAngleY = lastRotationY + value.translation.width * 0.01
                                rotationAngleX = lastRotationX + value.translation.height * 0.01
                            }
                            .onEnded { _ in
                                lastRotationY = rotationAngleY
                                lastRotationX = rotationAngleX
                            }
                    )
                    .gesture(
                        MagnificationGesture()
                            .onChanged { value in
                                scale = value
                            }
                    )
                    .onTapGesture(count: 2) {
                        // Reset view
                        withAnimation {
                            rotationAngleX = 0
                            rotationAngleY = 0
                            lastRotationX = 0
                            lastRotationY = 0
                            scale = 1.0
                        }
                    }

                    // Control Panel
                    VStack(spacing: 16) {
                        // Instructions
                        HStack(spacing: 20) {
                            InstructionLabel(icon: "hand.draw", text: "Ziehen zum Drehen")
                            InstructionLabel(icon: "arrow.up.left.and.arrow.down.right", text: "Pinch zum Zoomen")
                            InstructionLabel(icon: "arrow.counterclockwise", text: "2x Tap zum Reset")
                        }
                        .padding(.horizontal)

                        Divider()
                            .background(Color.white.opacity(0.3))

                        // Model Info
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Volumen")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                Text(scanViewModel.formattedVolume)
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Punkte")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                Text("\(scanViewModel.pointCount)")
                                    .font(.headline)
                                    .foregroundColor(.white)
                            }

                            Spacer()

                            VStack(alignment: .trailing, spacing: 4) {
                                Text("Qualität")
                                    .font(.caption)
                                    .foregroundColor(.white.opacity(0.7))
                                Text(scanViewModel.qualityRating)
                                    .font(.headline)
                                    .foregroundColor(qualityColor)
                            }
                        }
                        .padding(.horizontal)

                        // Export Button
                        Button(action: { showingExportOptions = true }) {
                            HStack {
                                Image(systemName: "square.and.arrow.up")
                                Text("3D-Modell exportieren")
                                    .fontWeight(.semibold)
                            }
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.blue)
                            .foregroundColor(.white)
                            .cornerRadius(12)
                        }
                        .padding(.horizontal)
                    }
                    .padding(.vertical, 20)
                    .background(
                        LinearGradient(
                            gradient: Gradient(colors: [Color.black.opacity(0.9), Color.black.opacity(0.7)]),
                            startPoint: .bottom,
                            endPoint: .top
                        )
                    )
                }
            }
            .navigationTitle("3D Modell")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .sheet(isPresented: $showingExportOptions) {
                ExportOptionsView(isExporting: .constant(false))
                    .environmentObject(scanViewModel)
            }
        }
    }

    private var qualityColor: Color {
        switch scanViewModel.qualityScore {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .orange
        default: return .red
        }
    }
}

// MARK: - Instruction Label
struct InstructionLabel: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
            Text(text)
                .font(.caption2)
        }
        .foregroundColor(.white.opacity(0.7))
    }
}

// MARK: - SceneKit View
struct SceneKitView: UIViewRepresentable {
    let meshAnchors: [ARMeshAnchor]
    let rotationX: CGFloat
    let rotationY: CGFloat
    let scale: CGFloat

    func makeUIView(context: Context) -> SCNView {
        let sceneView = SCNView()
        sceneView.scene = createScene()
        sceneView.allowsCameraControl = false
        sceneView.autoenablesDefaultLighting = false  // Use custom lighting
        sceneView.backgroundColor = UIColor(white: 0.05, alpha: 1.0)  // Dark grey

        // Enable advanced rendering features
        sceneView.rendersContinuously = true
        sceneView.antialiasingMode = .multisampling4X

        // Camera setup with better parameters
        let cameraNode = SCNNode()
        let camera = SCNCamera()
        camera.wantsHDR = true
        camera.wantsExposureAdaptation = true
        camera.exposureOffset = 0.5
        camera.minimumExposure = -1
        camera.maximumExposure = 3
        camera.bloomIntensity = 0.3
        cameraNode.camera = camera
        cameraNode.position = SCNVector3(0, 0, 3)
        sceneView.scene?.rootNode.addChildNode(cameraNode)
        sceneView.pointOfView = cameraNode

        return sceneView
    }

    func updateUIView(_ sceneView: SCNView, context: Context) {
        guard let scene = sceneView.scene else { return }

        // Update rotation
        if let modelNode = scene.rootNode.childNode(withName: "model", recursively: false) {
            modelNode.eulerAngles = SCNVector3(Float(rotationX), Float(rotationY), 0)
            modelNode.scale = SCNVector3(scale, scale, scale)
        }
    }

    private func createScene() -> SCNScene {
        let scene = SCNScene()

        // Create unified mesh from all anchors
        let modelNode = SCNNode()
        modelNode.name = "model"

        // Combine all meshes into one unified geometry
        if let unifiedGeometry = createUnifiedGeometry(from: meshAnchors) {
            modelNode.geometry = unifiedGeometry

            // PBR Material - Photorealistic
            let material = SCNMaterial()

            // Base color with gradient effect
            material.diffuse.contents = UIColor(red: 0.4, green: 0.6, blue: 0.9, alpha: 1.0)

            // Physically Based Rendering properties
            material.lightingModel = .physicallyBased
            material.roughness.contents = 0.3  // Slightly glossy
            material.metalness.contents = 0.1  // Slight metallic sheen
            material.clearCoat.contents = 0.5  // Clear coat layer
            material.clearCoatRoughness.contents = 0.1

            // Normal mapping for detail (procedural)
            material.normal.intensity = 0.5

            // Emission for slight glow
            material.emission.contents = UIColor(white: 0.05, alpha: 1.0)

            // Ambient occlusion
            material.ambientOcclusion.intensity = 0.5

            // Transparency
            material.transparencyMode = .default
            material.transparency = 0.95

            // Double-sided rendering
            material.isDoubleSided = true

            unifiedGeometry.materials = [material]
        }

        // Add professional lighting setup
        setupProfessionalLighting(scene: scene)

        // Add environment
        setupEnvironment(scene: scene)

        // Center model
        centerModel(modelNode)
        scene.rootNode.addChildNode(modelNode)

        return scene
    }

    /// Professional 3-point lighting setup
    private func setupProfessionalLighting(scene: SCNScene) {
        // Key Light (Main light source)
        let keyLight = SCNLight()
        keyLight.type = .directional
        keyLight.color = UIColor(white: 1.0, alpha: 1.0)
        keyLight.intensity = 1500
        keyLight.castsShadow = true
        keyLight.shadowMode = .deferred
        keyLight.shadowRadius = 3
        keyLight.shadowSampleCount = 16
        keyLight.shadowMapSize = CGSize(width: 2048, height: 2048)

        let keyLightNode = SCNNode()
        keyLightNode.light = keyLight
        keyLightNode.position = SCNVector3(2, 3, 3)
        keyLightNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(keyLightNode)

        // Fill Light (Soften shadows)
        let fillLight = SCNLight()
        fillLight.type = .omni
        fillLight.color = UIColor(white: 0.8, alpha: 1.0)
        fillLight.intensity = 500
        fillLight.attenuationStartDistance = 1
        fillLight.attenuationEndDistance = 10

        let fillLightNode = SCNNode()
        fillLightNode.light = fillLight
        fillLightNode.position = SCNVector3(-2, 1, 2)
        scene.rootNode.addChildNode(fillLightNode)

        // Back Light (Rim lighting)
        let backLight = SCNLight()
        backLight.type = .spot
        backLight.color = UIColor(red: 0.6, green: 0.8, blue: 1.0, alpha: 1.0)
        backLight.intensity = 800
        backLight.spotInnerAngle = 30
        backLight.spotOuterAngle = 80

        let backLightNode = SCNNode()
        backLightNode.light = backLight
        backLightNode.position = SCNVector3(0, 2, -3)
        backLightNode.look(at: SCNVector3(0, 0, 0))
        scene.rootNode.addChildNode(backLightNode)

        // Ambient light for general illumination
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.color = UIColor(white: 0.3, alpha: 1.0)
        ambientLight.intensity = 200

        let ambientLightNode = SCNNode()
        ambientLightNode.light = ambientLight
        scene.rootNode.addChildNode(ambientLightNode)
    }

    /// Setup environment for reflections and atmosphere
    private func setupEnvironment(scene: SCNScene) {
        // Create environment sphere for reflections
        let environmentNode = SCNNode()

        // Background gradient (dark to light blue)
        scene.background.contents = [
            UIColor(red: 0.1, green: 0.1, blue: 0.2, alpha: 1.0),  // Top
            UIColor(red: 0.05, green: 0.05, blue: 0.1, alpha: 1.0), // Bottom
        ]

        // Light probe for ambient reflections
        if let lightProbe = createLightProbe() {
            environmentNode.light = lightProbe
            scene.rootNode.addChildNode(environmentNode)
        }
    }

    /// Create light probe for realistic reflections
    private func createLightProbe() -> SCNLight? {
        let probe = SCNLight()
        probe.type = .probe
        probe.probeType = .irradiance
        probe.probeUpdateType = .realtime
        probe.probeExtents = SIMD3<Float>(10, 10, 10)

        return probe
    }

    /// Combine all mesh anchors into a single unified geometry
    private func createUnifiedGeometry(from anchors: [ARMeshAnchor]) -> SCNGeometry? {
        guard !anchors.isEmpty else { return nil }

        var allVertices: [SCNVector3] = []
        var allNormals: [SCNVector3] = []
        var allIndices: [Int32] = []
        var currentVertexOffset: Int32 = 0

        for anchor in anchors {
            let geometry = anchor.geometry
            let vertices = geometry.vertices
            let normals = geometry.normals
            let faces = geometry.faces
            let transform = anchor.transform

            // Transform vertices to world space
            for i in 0..<vertices.count {
                let vertex = vertices.buffer.contents()
                    .advanced(by: i * vertices.stride)
                    .assumingMemoryBound(to: SIMD3<Float>.self).pointee

                // Apply anchor transform to vertex
                let worldVertex = transform * SIMD4<Float>(vertex.x, vertex.y, vertex.z, 1.0)
                allVertices.append(SCNVector3(worldVertex.x, worldVertex.y, worldVertex.z))
            }

            // Transform normals to world space
            for i in 0..<normals.count {
                let normal = normals.buffer.contents()
                    .advanced(by: i * normals.stride)
                    .assumingMemoryBound(to: SIMD3<Float>.self).pointee

                // Apply anchor rotation to normal (w=0 for directions)
                let worldNormal = transform * SIMD4<Float>(normal.x, normal.y, normal.z, 0.0)
                let normalized = simd_normalize(SIMD3<Float>(worldNormal.x, worldNormal.y, worldNormal.z))
                allNormals.append(SCNVector3(normalized.x, normalized.y, normalized.z))
            }

            // Add face indices with offset
            for i in 0..<faces.count * 3 {
                let index = faces.buffer.contents()
                    .advanced(by: i * MemoryLayout<Int32>.size)
                    .assumingMemoryBound(to: Int32.self).pointee
                allIndices.append(index + currentVertexOffset)
            }

            currentVertexOffset += Int32(vertices.count)
        }

        guard !allVertices.isEmpty && !allIndices.isEmpty else { return nil }

        // Create geometry sources
        let vertexSource = SCNGeometrySource(vertices: allVertices)
        let normalSource = SCNGeometrySource(normals: allNormals)

        // Create geometry element
        let indexData = Data(bytes: allIndices, count: allIndices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(
            data: indexData,
            primitiveType: .triangles,
            primitiveCount: allIndices.count / 3,
            bytesPerIndex: MemoryLayout<Int32>.size
        )

        return SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
    }

    private func createGeometry(from anchor: ARMeshAnchor) -> SCNGeometry? {
        let geometry = anchor.geometry
        let vertices = geometry.vertices
        let normals = geometry.normals
        let faces = geometry.faces

        // Extract vertex data
        var vertexData: [SCNVector3] = []
        for i in 0..<vertices.count {
            let vertex = vertices.buffer.contents().advanced(by: i * vertices.stride).assumingMemoryBound(to: SIMD3<Float>.self).pointee
            vertexData.append(SCNVector3(vertex.x, vertex.y, vertex.z))
        }

        // Extract normal data
        var normalData: [SCNVector3] = []
        for i in 0..<normals.count {
            let normal = normals.buffer.contents().advanced(by: i * normals.stride).assumingMemoryBound(to: SIMD3<Float>.self).pointee
            normalData.append(SCNVector3(normal.x, normal.y, normal.z))
        }

        // Extract face indices
        var indices: [Int32] = []
        for i in 0..<faces.count * 3 {
            let index = faces.buffer.contents().advanced(by: i * MemoryLayout<Int32>.size).assumingMemoryBound(to: Int32.self).pointee
            indices.append(index)
        }

        // Create geometry sources
        let vertexSource = SCNGeometrySource(vertices: vertexData)
        let normalSource = SCNGeometrySource(normals: normalData)

        // Create geometry element
        let indexData = Data(bytes: indices, count: indices.count * MemoryLayout<Int32>.size)
        let element = SCNGeometryElement(data: indexData, primitiveType: .triangles, primitiveCount: faces.count, bytesPerIndex: MemoryLayout<Int32>.size)

        return SCNGeometry(sources: [vertexSource, normalSource], elements: [element])
    }

    private func centerModel(_ node: SCNNode) {
        let (min, max) = node.boundingBox
        let center = SCNVector3(
            (min.x + max.x) / 2,
            (min.y + max.y) / 2,
            (min.z + max.z) / 2
        )
        node.pivot = SCNMatrix4MakeTranslation(center.x, center.y, center.z)
    }
}

#Preview {
    Model3DViewerView()
        .environmentObject(ScanViewModel())
}
