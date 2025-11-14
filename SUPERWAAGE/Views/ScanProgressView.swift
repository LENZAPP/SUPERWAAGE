//
//  ScanProgressView.swift
//  SUPERWAAGE
//
//  Advanced scan progress visualization with quality indicators
//  Apple Senior Developer level UI implementation
//

import SwiftUI

struct ScanProgressView: View {

    // MARK: - Properties
    let progress: Double          // 0.0 to 1.0
    let qualityScore: Double      // 0.0 to 1.0
    let pointCount: Int
    let confidence: Double        // 0.0 to 1.0
    let coverageScore: Double     // 0.0 to 1.0
    let recommendations: [String]

    @State private var animatedProgress: Double = 0
    @State private var pulseAnimation: Bool = false

    // Safe percentage formatting helpers
    private var safeQualityPercent: Int {
        guard qualityScore.isFinite else { return 0 }
        return Int((qualityScore * 100).rounded())
    }

    private var safeProgressPercent: Int {
        guard progress.isFinite else { return 0 }
        return Int((progress * 100).rounded())
    }

    private var safeConfidencePercent: Int {
        guard confidence.isFinite else { return 0 }
        return Int((confidence * 100).rounded())
    }

    private var safeCoveragePercent: Int {
        guard coverageScore.isFinite else { return 0 }
        return Int((coverageScore * 100).rounded())
    }

    // MARK: - Body
    var body: some View {
        VStack(spacing: 16) {
            // Main Progress Ring
            ZStack {
                // Background ring
                Circle()
                    .stroke(Color.gray.opacity(0.2), lineWidth: 12)
                    .frame(width: 120, height: 120)

                // Progress ring
                Circle()
                    .trim(from: 0, to: animatedProgress)
                    .stroke(
                        progressColor,
                        style: StrokeStyle(lineWidth: 12, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: animatedProgress)

                // Center content - Show Quality Score
                VStack(spacing: 4) {
                    Text("\(safeQualityPercent)%")
                        .font(.system(size: 28, weight: .bold, design: .rounded))
                        .foregroundColor(progressColor)

                    Text("Qualität")
                        .font(.caption2)
                        .foregroundColor(.secondary)

                    Text(qualityText)
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(progressColor)
                }
            }
            .scaleEffect(pulseAnimation ? 1.05 : 1.0)
            .animation(.easeInOut(duration: 1.0).repeatForever(autoreverses: true), value: pulseAnimation)

            // Progress Bar - Separate from Quality
            VStack(spacing: 8) {
                HStack {
                    Text("Scan-Fortschritt")
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                    Text("\(safeProgressPercent)%")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.primary)
                }
                ProgressView(value: progress)
                    .tint(progress >= 0.8 ? .green : .orange)
            }
            .padding(.horizontal)

            Divider()
                .padding(.horizontal)

            // Quality Indicators
            VStack(spacing: 12) {
                // Points indicator
                QualityIndicator(
                    title: "Datenpunkte",
                    value: "\(pointCount)",
                    score: pointQualityScore,
                    icon: "point.3.connected.trianglepath.dotted"
                )

                // Confidence indicator
                QualityIndicator(
                    title: "Genauigkeit",
                    value: "\(safeConfidencePercent)%",
                    score: confidence,
                    icon: "checkmark.seal.fill"
                )

                // Coverage indicator
                QualityIndicator(
                    title: "Abdeckung",
                    value: "\(safeCoveragePercent)%",
                    score: coverageScore,
                    icon: "cube.fill"
                )

                // Overall quality
                QualityIndicator(
                    title: "Gesamtqualität",
                    value: qualityRating,
                    score: qualityScore,
                    icon: "star.fill"
                )
            }
            .padding(.horizontal)

            // Recommendations
            if !recommendations.isEmpty {
                Divider()

                VStack(alignment: .leading, spacing: 8) {
                    Text("Empfehlungen")
                        .font(.headline)
                        .foregroundColor(.primary)

                    ForEach(recommendations, id: \.self) { recommendation in
                        HStack(alignment: .top, spacing: 8) {
                            Image(systemName: iconForRecommendation(recommendation))
                                .foregroundColor(colorForRecommendation(recommendation))
                                .frame(width: 20)

                            Text(recommendation)
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                .padding()
                .background(Color.gray.opacity(0.1))
                .cornerRadius(12)
                .padding(.horizontal)
            }
        }
        .onAppear {
            animatedProgress = qualityScore
            pulseAnimation = qualityScore < 0.9
        }
        .onChange(of: qualityScore) { oldValue, newValue in
            animatedProgress = newValue
            pulseAnimation = newValue < 0.9
        }
    }

    // MARK: - Computed Properties

    private var progressColor: Color {
        switch qualityScore {
        case 0.9...1.0:
            return .green
        case 0.7..<0.9:
            return .blue
        case 0.5..<0.7:
            return .orange
        default:
            return .red
        }
    }

    private var qualityText: String {
        switch qualityScore {
        case 0.9...1.0: return "Exzellent"
        case 0.8..<0.9: return "Sehr gut"
        case 0.7..<0.8: return "Gut"
        case 0.6..<0.7: return "Befriedigend"
        case 0.5..<0.6: return "Ausreichend"
        default: return "Ungenügend"
        }
    }

    private var qualityRating: String {
        switch qualityScore {
        case 0.9...1.0: return "★★★★★"
        case 0.8..<0.9: return "★★★★☆"
        case 0.7..<0.8: return "★★★☆☆"
        case 0.6..<0.7: return "★★☆☆☆"
        case 0.5..<0.6: return "★☆☆☆☆"
        default: return "☆☆☆☆☆"
        }
    }

    private var pointQualityScore: Double {
        // 5000+ points = excellent
        return min(Double(pointCount) / 5000.0, 1.0)
    }

    // MARK: - Helper Functions

    private func iconForRecommendation(_ recommendation: String) -> String {
        if recommendation.contains("⚠️") {
            return "exclamationmark.triangle.fill"
        } else if recommendation.contains("💡") {
            return "lightbulb.fill"
        } else if recommendation.contains("🎯") {
            return "target"
        } else if recommendation.contains("✅") {
            return "checkmark.circle.fill"
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
        } else {
            return .gray
        }
    }
}

// MARK: - Quality Indicator Component
struct QualityIndicator: View {
    let title: String
    let value: String
    let score: Double
    let icon: String

    var body: some View {
        HStack {
            // Icon
            Image(systemName: icon)
                .foregroundColor(scoreColor)
                .frame(width: 24)

            // Title & Value
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.caption)
                    .foregroundColor(.secondary)

                Text(value)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }

            Spacer()

            // Progress bar
            ZStack(alignment: .leading) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.gray.opacity(0.2))
                    .frame(width: 80, height: 8)

                RoundedRectangle(cornerRadius: 4)
                    .fill(scoreColor)
                    .frame(width: 80 * score, height: 8)
                    .animation(.easeInOut(duration: 0.3), value: score)
            }
        }
        .padding(.vertical, 4)
    }

    private var scoreColor: Color {
        switch score {
        case 0.8...1.0: return .green
        case 0.6..<0.8: return .blue
        case 0.4..<0.6: return .orange
        default: return .red
        }
    }
}

// MARK: - Preview
struct ScanProgressView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            // Excellent scan
            ScanProgressView(
                progress: 0.95,
                qualityScore: 0.92,
                pointCount: 6500,
                confidence: 0.88,
                coverageScore: 0.90,
                recommendations: ["✅ Ausgezeichnete Scan-Qualität!"]
            )
            .previewDisplayName("Excellent")

            // Good scan with recommendations
            ScanProgressView(
                progress: 0.75,
                qualityScore: 0.68,
                pointCount: 3200,
                confidence: 0.72,
                coverageScore: 0.65,
                recommendations: [
                    "💡 Mehr Datenpunkte für bessere Genauigkeit sammeln.",
                    "💡 Näher herangehen für bessere Genauigkeit (30cm ideal)."
                ]
            )
            .previewDisplayName("Good")

            // Poor scan
            ScanProgressView(
                progress: 0.45,
                qualityScore: 0.42,
                pointCount: 850,
                confidence: 0.51,
                coverageScore: 0.38,
                recommendations: [
                    "⚠️ Zu wenig Datenpunkte! Scannen Sie das Objekt länger.",
                    "⚠️ Unvollständige Abdeckung! Scannen Sie von mehreren Winkeln.",
                    "💡 Bessere Beleuchtung verwenden für höhere Scan-Qualität."
                ]
            )
            .previewDisplayName("Poor")
        }
        .padding()
        .previewLayout(.sizeThatFits)
    }
}
