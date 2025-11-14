//
//  ScanMetricsOverlay.swift
//  SUPERWAAGE
//
//  Real-time scan metrics and performance monitoring overlay
//  Shows: Point count, FPS, Frame skip rate, Memory usage, Quality preset
//

import SwiftUI

struct ScanMetricsOverlay: View {
    @ObservedObject var viewModel: ScanViewModel

    @State private var isExpanded = false

    var body: some View {
        VStack(spacing: 0) {
            // Toggle button
            HStack {
                Spacer()
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        isExpanded.toggle()
                    }
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "chart.bar.fill")
                        Text(isExpanded ? "Metriken" : "Stats")
                            .font(.caption.bold())
                        Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                            .font(.caption2)
                    }
                    .foregroundColor(.white)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.6))
                            .overlay(
                                Capsule()
                                    .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                            )
                    )
                }
                .padding(.trailing, 16)
                .padding(.top, 16)
            }

            if isExpanded {
                VStack(spacing: 12) {
                    // Quality Preset Picker
                    QualityPresetPicker(selectedQuality: $viewModel.scanQuality)
                        .padding(.top, 8)

                    Divider()
                        .background(Color.white.opacity(0.3))

                    // Metrics Grid
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 12) {
                        // Point Count
                        MetricCard(
                            icon: "cpu",
                            title: "Punkte",
                            value: formatNumber(viewModel.totalPointsScanned),
                            subtitle: "/ \(formatNumber(viewModel.scanQuality.maxPoints))",
                            color: pointCountColor
                        )

                        // FPS
                        MetricCard(
                            icon: "gauge",
                            title: "FPS",
                            value: String(format: "%.1f", viewModel.currentFPS),
                            subtitle: "Hz",
                            color: fpsColor
                        )

                        // Frame Skip Rate
                        MetricCard(
                            icon: "skip.forward",
                            title: "Skip Rate",
                            value: String(format: "%.0f%%", skipRatePercent),
                            subtitle: "\(viewModel.totalFramesSkipped) frames",
                            color: skipRateColor
                        )

                        // Memory Usage
                        MetricCard(
                            icon: "memorychip",
                            title: "Memory",
                            value: String(format: "%.1f", viewModel.estimatedMemoryUsage),
                            subtitle: "MB",
                            color: memoryColor
                        )

                        // Frames Processed
                        MetricCard(
                            icon: "photo.stack",
                            title: "Frames",
                            value: formatNumber(viewModel.totalFramesProcessed),
                            subtitle: "verarbeitet",
                            color: .blue
                        )

                        // Tracking Quality
                        MetricCard(
                            icon: "camera.metering.matrix",
                            title: "Tracking",
                            value: viewModel.trackingQuality.description,
                            subtitle: "",
                            color: trackingColor
                        )
                    }
                }
                .padding(16)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.7))
                        .overlay(
                            RoundedRectangle(cornerRadius: 16)
                                .strokeBorder(Color.white.opacity(0.2), lineWidth: 1)
                        )
                )
                .padding(.horizontal, 16)
                .padding(.top, 8)
                .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }

    // MARK: - Computed Properties

    private var skipRatePercent: Double {
        let total = viewModel.totalFramesProcessed + viewModel.totalFramesSkipped
        guard total > 0 else { return 0 }
        return Double(viewModel.totalFramesSkipped) / Double(total) * 100
    }

    private var pointCountColor: Color {
        let ratio = Double(viewModel.totalPointsScanned) / Double(viewModel.scanQuality.maxPoints)
        if ratio < 0.5 { return .green }
        if ratio < 0.8 { return .yellow }
        return .red
    }

    private var fpsColor: Color {
        if viewModel.currentFPS >= 30 { return .green }
        if viewModel.currentFPS >= 20 { return .yellow }
        return .red
    }

    private var skipRateColor: Color {
        if skipRatePercent < 50 { return .green }
        if skipRatePercent < 70 { return .yellow }
        return .orange
    }

    private var memoryColor: Color {
        if viewModel.estimatedMemoryUsage < 30 { return .green }
        if viewModel.estimatedMemoryUsage < 50 { return .yellow }
        return .red
    }

    private var trackingColor: Color {
        switch viewModel.trackingQuality {
        case .good: return .green
        case .normal: return .yellow
        case .limited: return .red
        }
    }

    // MARK: - Helper Functions

    private func formatNumber(_ number: Int) -> String {
        if number >= 1_000_000 {
            return String(format: "%.1fM", Double(number) / 1_000_000)
        } else if number >= 1_000 {
            return String(format: "%.1fK", Double(number) / 1_000)
        } else {
            return "\(number)"
        }
    }
}

// MARK: - Quality Preset Picker

struct QualityPresetPicker: View {
    @Binding var selectedQuality: ScanViewModel.ScanQuality

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Scan-Qualität")
                .font(.caption.bold())
                .foregroundColor(.white.opacity(0.8))

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(ScanViewModel.ScanQuality.allCases, id: \.self) { quality in
                        QualityPresetButton(
                            quality: quality,
                            isSelected: selectedQuality == quality
                        ) {
                            withAnimation(.spring(response: 0.3)) {
                                selectedQuality = quality
                            }
                        }
                    }
                }
            }
        }
    }
}

struct QualityPresetButton: View {
    let quality: ScanViewModel.ScanQuality
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 4) {
                Text(quality.rawValue)
                    .font(.caption.bold())
                    .foregroundColor(isSelected ? .black : .white)

                Text(quality.description)
                    .font(.caption2)
                    .foregroundColor(isSelected ? .black.opacity(0.7) : .white.opacity(0.6))
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(width: 120, height: 60)
            .padding(.horizontal, 8)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(isSelected ? Color.white : Color.white.opacity(0.15))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 10)
                    .strokeBorder(
                        isSelected ? Color.blue : Color.white.opacity(0.3),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
    }
}

// MARK: - Metric Card

struct MetricCard: View {
    let icon: String
    let title: String
    let value: String
    let subtitle: String
    let color: Color

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: icon)
                    .font(.caption)
                    .foregroundColor(color)

                Text(title)
                    .font(.caption2)
                    .foregroundColor(.white.opacity(0.7))

                Spacer()
            }

            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(value)
                    .font(.title3.bold())
                    .foregroundColor(.white)

                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption2)
                        .foregroundColor(.white.opacity(0.6))
                }

                Spacer()
            }
        }
        .padding(10)
        .background(
            RoundedRectangle(cornerRadius: 10)
                .fill(Color.white.opacity(0.1))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .strokeBorder(color.opacity(0.3), lineWidth: 1)
                )
        )
    }
}

// MARK: - Preview

struct ScanMetricsOverlay_Previews: PreviewProvider {
    static var previews: some View {
        ZStack {
            Color.gray.ignoresSafeArea()

            ScanMetricsOverlay(viewModel: {
                let vm = ScanViewModel()
                vm.totalPointsScanned = 125_000
                vm.totalFramesProcessed = 45
                vm.totalFramesSkipped = 105
                vm.currentFPS = 28.5
                vm.estimatedMemoryUsage = 12.4
                return vm
            }())
        }
    }
}
