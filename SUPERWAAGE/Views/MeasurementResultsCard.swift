//
//  MeasurementResultsCard.swift
//  SUPERWAAGE
//
//  Enhanced measurement results display with accuracy metrics
//  Apple Senior Developer level UI implementation
//

import SwiftUI

struct MeasurementResultsCard: View {
    @EnvironmentObject var scanViewModel: ScanViewModel
    @State private var showingDetails = false
    @State private var showingExportOptions = false
    @State private var isExporting = false
    @State private var showing3DViewer = false

    // Safe percentage formatting helpers
    private var safeConfidencePercent: Int {
        let confidence = scanViewModel.confidence
        guard confidence.isFinite else { return 0 }
        return Int((confidence * 100).rounded())
    }

    private var safeCoveragePercent: Int {
        let coverage = scanViewModel.coverageScore
        guard coverage.isFinite else { return 0 }
        return Int((coverage * 100).rounded())
    }

    var body: some View {
        VStack(spacing: 20) {
            // Header with Success Icon
            HStack(spacing: 12) {
                Image(systemName: "checkmark.seal.fill")
                    .font(.title)
                    .foregroundColor(.green)

                VStack(alignment: .leading, spacing: 4) {
                    Text("Scan erfolgreich!")
                        .font(.title2)
                        .fontWeight(.bold)

                    HStack(spacing: 6) {
                        Image(systemName: qualityIcon)
                            .font(.caption)
                        Text(scanViewModel.qualityRating)
                            .font(.caption)
                            .fontWeight(.medium)
                    }
                    .foregroundColor(qualityColor)
                }

                Spacer()
            }

            Divider()

            // Main Results - Volume & Weight (Most Important)
            VStack(spacing: 16) {
                // Volume - Primary Result
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "cube.fill")
                            .font(.title2)
                            .foregroundColor(.purple)

                        Text("Volumen")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Spacer()
                    }

                    HStack {
                        Text(scanViewModel.formattedVolume)
                            .font(.system(size: 36, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Spacer()
                    }

                    // Error Margin - Compact Display
                    if scanViewModel.errorMarginPercent > 0 {
                        HStack(spacing: 6) {
                            Image(systemName: "plusminus.circle.fill")
                                .font(.caption)
                                .foregroundColor(errorMarginColor)

                            Text("Genauigkeit: \(scanViewModel.errorMarginDescription)")
                                .font(.caption)
                                .foregroundColor(.secondary)

                            Spacer()
                        }
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.purple.opacity(0.08))
                )

                // Weight - Secondary Result
                VStack(spacing: 8) {
                    HStack {
                        Image(systemName: "scalemass.fill")
                            .font(.title2)
                            .foregroundColor(.orange)

                        Text("Geschätztes Gewicht")
                            .font(.headline)
                            .foregroundColor(.secondary)

                        Spacer()
                    }

                    HStack(alignment: .firstTextBaseline, spacing: 4) {
                        Text(scanViewModel.formattedWeight)
                            .font(.system(size: 32, weight: .bold, design: .rounded))
                            .foregroundColor(.primary)

                        Text(scanViewModel.selectedMaterial.name)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(
                                Capsule()
                                    .fill(Color.orange.opacity(0.15))
                            )

                        Spacer()
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.orange.opacity(0.08))
                )
            }

            Divider()

            // Compact Dimensions Row
            HStack(spacing: 8) {
                CompactDimensionItem(
                    label: "L",
                    value: scanViewModel.dimensions.x,
                    color: .red
                )
                CompactDimensionItem(
                    label: "B",
                    value: scanViewModel.dimensions.y,
                    color: .green
                )
                CompactDimensionItem(
                    label: "H",
                    value: scanViewModel.dimensions.z,
                    color: .blue
                )
            }

            // Optional: Vintage Scale Display (Collapsible)
            if showingDetails {
                Divider()

                VStack(spacing: 8) {
                    Text("Vintage Waagenanzeige")
                        .font(.subheadline)
                        .foregroundColor(.secondary)

                    // ✅ CRASH FIX: Validate weight before passing to scale view
                    let safeWeight = scanViewModel.weight_g.isFinite ? min(scanViewModel.weight_g, 1000) : 0
                    BerkelScaleView(weight: safeWeight)
                        .frame(height: 180)
                        .padding(.vertical, 8)
                }
                .frame(maxWidth: .infinity)
            }

            // Scan Quality Indicators (Compact)
            if !showingDetails {
                HStack(spacing: 12) {
                    // Confidence
                    HStack(spacing: 6) {
                        Image(systemName: "checkmark.seal.fill")
                            .foregroundColor(.green)
                            .font(.caption2)
                        Text("\(safeConfidencePercent)%")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.green.opacity(0.1))
                    )

                    // Coverage
                    HStack(spacing: 6) {
                        Image(systemName: "viewfinder")
                            .foregroundColor(.blue)
                            .font(.caption2)
                        Text("\(safeCoveragePercent)%")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.blue.opacity(0.1))
                    )

                    // Point Count
                    HStack(spacing: 6) {
                        Image(systemName: "point.3.connected.trianglepath.dotted")
                            .foregroundColor(.purple)
                            .font(.caption2)
                        Text("\(scanViewModel.pointCount)")
                            .font(.caption2)
                            .fontWeight(.semibold)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.purple.opacity(0.1))
                    )
                }
            }

            // Recommendations (if any)
            if !scanViewModel.recommendations.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Hinweise")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.secondary)

                    ForEach(scanViewModel.recommendations.prefix(3), id: \.self) { recommendation in
                        HStack(alignment: .top, spacing: 6) {
                            Image(systemName: iconForRecommendation(recommendation))
                                .foregroundColor(colorForRecommendation(recommendation))
                                .font(.caption2)
                                .frame(width: 16)

                            Text(cleanRecommendation(recommendation))
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }

            // Calibration Status
            if scanViewModel.isCalibrated {
                HStack {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.green)
                        .font(.caption)
                    Text("Kalibriert - Erhöhte Genauigkeit")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }

            // 3D Model Viewer & Export Buttons
            if scanViewModel.can3DExport {
                Divider()

                HStack(spacing: 12) {
                    // View 3D Model Button
                    Button(action: { showing3DViewer = true }) {
                        HStack {
                            Image(systemName: "viewfinder.circle.fill")
                                .foregroundColor(.blue)
                            Text("3D ansehen")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(8)
                    }

                    // Export Button
                    Button(action: { export3DModel() }) {
                        HStack {
                            Image(systemName: "square.and.arrow.up")
                                .foregroundColor(.green)
                            Text("Exportieren")
                                .font(.subheadline)
                                .fontWeight(.semibold)
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 8)
                        .background(Color.green.opacity(0.1))
                        .cornerRadius(8)
                    }
                }
            }

            // Details Button
            Button(action: { showingDetails.toggle() }) {
                HStack {
                    Image(systemName: showingDetails ? "chevron.up" : "chevron.down")
                    Text(showingDetails ? "Weniger Details" : "Mehr Details")
                        .font(.caption)
                }
                .foregroundColor(.blue)
            }
        }
        .padding()
        .background(
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(.systemBackground))
                .shadow(color: Color.black.opacity(0.1), radius: 10, x: 0, y: 5)
        )
        .padding(.horizontal)
        .sheet(isPresented: $showingDetails) {
            DetailedResultsView()
                .environmentObject(scanViewModel)
        }
        .sheet(isPresented: $showingExportOptions) {
            ExportOptionsView(isExporting: $isExporting)
                .environmentObject(scanViewModel)
        }
        .fullScreenCover(isPresented: $showing3DViewer) {
            Model3DViewerView()
                .environmentObject(scanViewModel)
        }
    }

    // MARK: - Actions

    private func export3DModel() {
        showingExportOptions = true
    }

    // MARK: - Computed Properties

    private var qualityIcon: String {
        switch scanViewModel.qualityScore {
        case 0.9...1.0: return "star.fill"
        case 0.7..<0.9: return "checkmark.circle.fill"
        case 0.5..<0.7: return "exclamationmark.circle.fill"
        default: return "xmark.circle.fill"
        }
    }

    private var qualityColor: Color {
        switch scanViewModel.qualityScore {
        case 0.9...1.0: return .green
        case 0.7..<0.9: return .blue
        case 0.5..<0.7: return .orange
        default: return .red
        }
    }

    private var errorMarginColor: Color {
        switch scanViewModel.errorMarginPercent {
        case 0..<5: return .green
        case 5..<10: return .blue
        case 10..<15: return .orange
        default: return .red
        }
    }

    // MARK: - Formatting Helpers

    private func formatMainWeight() -> String {
        let weight = scanViewModel.weight_g
        if weight < 1000 {
            return String(format: "%.1f", weight)
        } else {
            return String(format: "%.2f", weight / 1000.0)
        }
    }

    private func weightUnit() -> String {
        return scanViewModel.weight_g < 1000 ? "g" : "kg"
    }

    private func iconForRecommendation(_ recommendation: String) -> String {
        if recommendation.contains("⚠️") {
            return "exclamationmark.triangle.fill"
        } else if recommendation.contains("💡") {
            return "lightbulb.fill"
        } else if recommendation.contains("🎯") {
            return "target"
        } else if recommendation.contains("✅") {
            return "checkmark.circle.fill"
        } else if recommendation.contains("📍") {
            return "location.fill"
        } else {
            return "info.circle.fill"
        }
    }

    private func colorForRecommendation(_ recommendation: String) -> Color {
        if recommendation.contains("⚠️") {
            return .red
        } else if recommendation.contains("💡") {
            return .blue
        } else if recommendation.contains("🎯") {
            return .purple
        } else if recommendation.contains("✅") {
            return .green
        } else if recommendation.contains("📍") {
            return .orange
        } else {
            return .gray
        }
    }

    private func cleanRecommendation(_ recommendation: String) -> String {
        // Remove emojis from recommendation text
        return recommendation
            .replacingOccurrences(of: "⚠️ ", with: "")
            .replacingOccurrences(of: "💡 ", with: "")
            .replacingOccurrences(of: "🎯 ", with: "")
            .replacingOccurrences(of: "✅ ", with: "")
            .replacingOccurrences(of: "📍 ", with: "")
    }
}

// MARK: - Dimension Item
struct DimensionItem: View {
    let label: String
    let value: Float
    let color: Color
    let icon: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)

            Text(label)
                .font(.caption2)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Text(String(format: "%.1f", value))
                .font(.title3)
                .fontWeight(.semibold)
                .foregroundColor(color)

            Text("cm")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.1))
        )
    }
}

// MARK: - Measurement Row
struct MeasurementRow: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack {
            Image(systemName: icon)
                .foregroundColor(color)
                .frame(width: 30)

            Text(label)
                .font(.subheadline)
                .foregroundColor(.secondary)

            Spacer()

            Text(value)
                .font(.subheadline)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Detailed Results View
struct DetailedResultsView: View {
    @EnvironmentObject var scanViewModel: ScanViewModel
    @Environment(\.dismiss) var dismiss

    // Safe percentage formatting helpers
    private var safeConfidencePercent: Int {
        let confidence = scanViewModel.confidence
        guard confidence.isFinite else { return 0 }
        return Int((confidence * 100).rounded())
    }

    private var safeCoveragePercent: Int {
        let coverage = scanViewModel.coverageScore
        guard coverage.isFinite else { return 0 }
        return Int((coverage * 100).rounded())
    }

    var body: some View {
        NavigationView {
            List {
                Section("Messung") {
                    DetailRow(label: "Volumen", value: scanViewModel.formattedVolume)
                    DetailRow(label: "Gewicht", value: scanViewModel.formattedWeight)
                    DetailRow(label: "Dimensionen", value: scanViewModel.formattedDimensions)
                    DetailRow(label: "Scandauer", value: String(format: "%.1f s", scanViewModel.scanDuration))
                }

                Section("Qualität") {
                    DetailRow(label: "Gesamt-Qualität", value: scanViewModel.qualityRating)
                    DetailRow(label: "Vertrauen", value: "\(safeConfidencePercent)%")
                    DetailRow(label: "Abdeckung", value: "\(safeCoveragePercent)%")
                    DetailRow(label: "Datenpunkte", value: "\(scanViewModel.pointCount)")
                    DetailRow(label: "Ø Genauigkeit", value: String(format: "%.1f%%", scanViewModel.averageConfidence * 100))

                    if scanViewModel.errorMarginPercent > 0 {
                        DetailRow(label: "Fehlertoleranz", value: scanViewModel.errorMarginDescription)
                    }
                }

                Section("Material") {
                    DetailRow(label: "Name", value: scanViewModel.selectedMaterial.name)
                    DetailRow(label: "Kategorie", value: scanViewModel.selectedMaterial.category.rawValue)
                    DetailRow(label: "Dichte", value: String(format: "%.2f g/cm³", scanViewModel.selectedMaterial.density))
                }

                if !scanViewModel.recommendations.isEmpty {
                    Section("Empfehlungen") {
                        ForEach(scanViewModel.recommendations, id: \.self) { recommendation in
                            Text(cleanRecommendation(recommendation))
                                .font(.caption)
                        }
                    }
                }
            }
            .navigationTitle("Details")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
    }

    private func cleanRecommendation(_ recommendation: String) -> String {
        return recommendation
            .replacingOccurrences(of: "⚠️ ", with: "")
            .replacingOccurrences(of: "💡 ", with: "")
            .replacingOccurrences(of: "🎯 ", with: "")
            .replacingOccurrences(of: "✅ ", with: "")
            .replacingOccurrences(of: "📍 ", with: "")
    }
}

struct DetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundColor(.secondary)
            Spacer()
            Text(value)
                .fontWeight(.semibold)
        }
    }
}

// MARK: - Compact Dimension Item
struct CompactDimensionItem: View {
    let label: String
    let value: Float
    let color: Color

    var body: some View {
        VStack(spacing: 4) {
            Text(label)
                .font(.caption2)
                .fontWeight(.semibold)
                .foregroundColor(color)

            // ✅ CRASH FIX: Guard against NaN/Infinite dimension values
            Text(value.isFinite ? String(format: "%.1f", value) : "--")
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.primary)

            Text("cm")
                .font(.caption2)
                .foregroundColor(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(color.opacity(0.1))
        )
    }
}
