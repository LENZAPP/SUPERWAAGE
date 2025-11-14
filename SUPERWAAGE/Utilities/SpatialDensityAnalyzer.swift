//
//  SpatialDensityAnalyzer.swift
//  SUPERWAAGE
//
//  Spatial analysis to identify under-scanned regions
//  Shows user where more scanning is needed
//

import Foundation
import simd
import RealityKit
import UIKit

// MARK: - Spatial Grid Cell
struct GridCell {
    let index: SIMD3<Int>
    let center: simd_float3
    var pointCount: Int
    var density: Float
    var needsMoreScanning: Bool
}

// MARK: - Coverage Heat Map
struct CoverageHeatMap {
    let gridSize: Int
    let cells: [GridCell]
    let overallCoverage: Float
    let underScannedCells: [GridCell]

    var needsMoreScanning: Bool {
        return overallCoverage < 0.8 || !underScannedCells.isEmpty
    }
}

// MARK: - Spatial Density Analyzer
class SpatialDensityAnalyzer {

    // MARK: - Configuration
    private let gridResolution: Int = 10  // 10x10x10 grid
    private let minPointsPerCell: Int = 20
    private let optimalPointsPerCell: Int = 100

    // MARK: - Analysis

    /// Analyze spatial distribution of points to identify gaps
    func analyzeSpatialDensity(points: [simd_float3], boundingBox: BoundingBox) -> CoverageHeatMap {

        // Create 3D grid
        var grid = createGrid(boundingBox: boundingBox)

        // Assign points to grid cells
        for point in points {
            if let cellIndex = getCellIndex(for: point, boundingBox: boundingBox) {
                if cellIndex.x >= 0 && cellIndex.x < gridResolution &&
                   cellIndex.y >= 0 && cellIndex.y < gridResolution &&
                   cellIndex.z >= 0 && cellIndex.z < gridResolution {
                    let idx = flatIndex(cellIndex)
                    grid[idx].pointCount += 1
                }
            }
        }

        // Calculate density and identify under-scanned cells
        var cells: [GridCell] = []
        var underScanned: [GridCell] = []
        var totalCellsWithPoints = 0
        var wellScannedCells = 0

        for var cell in grid {
            // Calculate density (points per unit volume)
            let cellVolume = calculateCellVolume(boundingBox: boundingBox)
            cell.density = Float(cell.pointCount) / cellVolume

            // Determine if needs more scanning
            let needsMore = cell.pointCount > 0 && cell.pointCount < minPointsPerCell
            cell.needsMoreScanning = needsMore

            if cell.pointCount > 0 {
                totalCellsWithPoints += 1

                if cell.pointCount >= optimalPointsPerCell {
                    wellScannedCells += 1
                } else if needsMore {
                    underScanned.append(cell)
                }
            }

            cells.append(cell)
        }

        // Calculate overall coverage
        let coverage = totalCellsWithPoints > 0 ?
            Float(wellScannedCells) / Float(totalCellsWithPoints) : 0.0

        return CoverageHeatMap(
            gridSize: gridResolution,
            cells: cells,
            overallCoverage: coverage,
            underScannedCells: underScanned
        )
    }

    // MARK: - Visualization

    /// Create visual indicators for under-scanned regions
    func createCoverageVisualization(heatMap: CoverageHeatMap, in scene: RealityKit.Scene) -> [ModelEntity] {
        var entities: [ModelEntity] = []

        for cell in heatMap.underScannedCells {
            // Create a semi-transparent cube at under-scanned locations
            let mesh = MeshResource.generateBox(size: 0.02) // 2cm cubes
            var material = SimpleMaterial()
            material.color = .init(tint: .red.withAlphaComponent(0.3))

            let entity = ModelEntity(mesh: mesh, materials: [material])
            entity.position = cell.center

            entities.append(entity)
        }

        return entities
    }

    /// Generate directional hints for where to scan next
    func getScanDirectionHints(heatMap: CoverageHeatMap, currentCameraPosition: simd_float3) -> [String] {
        var hints: [String] = []

        if heatMap.underScannedCells.isEmpty {
            return ["✅ Vollständige Abdeckung erreicht!"]
        }

        // Find clusters of under-scanned cells
        let clusters = clusterUnderScannedCells(heatMap.underScannedCells)

        for cluster in clusters {
            // Find center of cluster
            let clusterCenter = cluster.map { $0.center }.reduce(simd_float3.zero, +) / Float(cluster.count)

            // Determine direction relative to camera
            let direction = clusterCenter - currentCameraPosition
            let hint = describeDirection(direction)

            hints.append("📍 Scannen Sie \(hint)")
        }

        return hints
    }

    // MARK: - Grid Management

    private func createGrid(boundingBox: BoundingBox) -> [GridCell] {
        var grid: [GridCell] = []

        let cellSize = simd_float3(
            (boundingBox.max.x - boundingBox.min.x) / Float(gridResolution),
            (boundingBox.max.y - boundingBox.min.y) / Float(gridResolution),
            (boundingBox.max.z - boundingBox.min.z) / Float(gridResolution)
        )

        for x in 0..<gridResolution {
            for y in 0..<gridResolution {
                for z in 0..<gridResolution {
                    let cellIndex = SIMD3<Int>(x, y, z)

                    let center = simd_float3(
                        boundingBox.min.x + (Float(x) + 0.5) * cellSize.x,
                        boundingBox.min.y + (Float(y) + 0.5) * cellSize.y,
                        boundingBox.min.z + (Float(z) + 0.5) * cellSize.z
                    )

                    let cell = GridCell(
                        index: cellIndex,
                        center: center,
                        pointCount: 0,
                        density: 0.0,
                        needsMoreScanning: false
                    )

                    grid.append(cell)
                }
            }
        }

        return grid
    }

    private func getCellIndex(for point: simd_float3, boundingBox: BoundingBox) -> SIMD3<Int>? {
        let normalized = simd_float3(
            (point.x - boundingBox.min.x) / (boundingBox.max.x - boundingBox.min.x),
            (point.y - boundingBox.min.y) / (boundingBox.max.y - boundingBox.min.y),
            (point.z - boundingBox.min.z) / (boundingBox.max.z - boundingBox.min.z)
        )

        guard normalized.x >= 0 && normalized.x <= 1 &&
              normalized.y >= 0 && normalized.y <= 1 &&
              normalized.z >= 0 && normalized.z <= 1 else {
            return nil
        }

        return SIMD3<Int>(
            Int(normalized.x * Float(gridResolution - 1)),
            Int(normalized.y * Float(gridResolution - 1)),
            Int(normalized.z * Float(gridResolution - 1))
        )
    }

    private func flatIndex(_ index: SIMD3<Int>) -> Int {
        return index.x * gridResolution * gridResolution +
               index.y * gridResolution +
               index.z
    }

    private func calculateCellVolume(boundingBox: BoundingBox) -> Float {
        let size = boundingBox.max - boundingBox.min
        let cellSize = size / Float(gridResolution)
        return cellSize.x * cellSize.y * cellSize.z
    }

    // MARK: - Clustering

    private func clusterUnderScannedCells(_ cells: [GridCell]) -> [[GridCell]] {
        guard !cells.isEmpty else { return [] }

        var clusters: [[GridCell]] = []
        var visited = Set<Int>()

        for (index, cell) in cells.enumerated() {
            if visited.contains(index) { continue }

            var cluster: [GridCell] = [cell]
            visited.insert(index)

            // Find nearby under-scanned cells
            for (otherIndex, otherCell) in cells.enumerated() {
                if visited.contains(otherIndex) { continue }

                let distance = simd_distance(cell.center, otherCell.center)
                if distance < 0.1 { // 10cm proximity
                    cluster.append(otherCell)
                    visited.insert(otherIndex)
                }
            }

            clusters.append(cluster)
        }

        // Sort by cluster size (largest first)
        return clusters.sorted { $0.count > $1.count }
    }

    // MARK: - Direction Description

    private func describeDirection(_ direction: simd_float3) -> String {
        let normalized = simd_normalize(direction)

        // Vertical component
        var description = ""
        if abs(normalized.y) > 0.5 {
            description = normalized.y > 0 ? "oben" : "unten"
        }

        // Horizontal components
        var horizontal = ""
        if abs(normalized.x) > 0.3 {
            horizontal = normalized.x > 0 ? "rechts" : "links"
        }
        if abs(normalized.z) > 0.3 {
            let depth = normalized.z > 0 ? "hinten" : "vorne"
            horizontal = horizontal.isEmpty ? depth : "\(horizontal) \(depth)"
        }

        if description.isEmpty {
            return horizontal.isEmpty ? "rund herum" : horizontal
        } else if horizontal.isEmpty {
            return description
        } else {
            return "\(description) \(horizontal)"
        }
    }
}

// MARK: - Bounding Box
struct BoundingBox: Sendable {
    let min: simd_float3
    let max: simd_float3

    nonisolated var center: simd_float3 {
        return (min + max) / 2.0
    }

    nonisolated var size: simd_float3 {
        return max - min
    }

    nonisolated func contains(_ point: SIMD3<Float>) -> Bool {
        return point.x >= min.x && point.x <= max.x &&
               point.y >= min.y && point.y <= max.y &&
               point.z >= min.z && point.z <= max.z
    }

    nonisolated static func from(points: [simd_float3]) -> BoundingBox? {
        guard !points.isEmpty else { return nil }

        let minX = points.map { $0.x }.min() ?? 0
        let maxX = points.map { $0.x }.max() ?? 0
        let minY = points.map { $0.y }.min() ?? 0
        let maxY = points.map { $0.y }.max() ?? 0
        let minZ = points.map { $0.z }.min() ?? 0
        let maxZ = points.map { $0.z }.max() ?? 0

        return BoundingBox(
            min: simd_float3(minX, minY, minZ),
            max: simd_float3(maxX, maxY, maxZ)
        )
    }
}

// MARK: - Grid Cell Extension
extension GridCell {
    var qualityLevel: CoverageQuality {
        if pointCount >= 100 {
            return .excellent
        } else if pointCount >= 50 {
            return .good
        } else if pointCount >= 20 {
            return .adequate
        } else if pointCount > 0 {
            return .poor
        } else {
            return .empty
        }
    }
}

enum CoverageQuality {
    case excellent
    case good
    case adequate
    case poor
    case empty

    var color: UIColor {
        switch self {
        case .excellent: return .green
        case .good: return .blue
        case .adequate: return .orange
        case .poor: return .red
        case .empty: return .clear
        }
    }
}
