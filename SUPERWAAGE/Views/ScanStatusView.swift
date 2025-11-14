//
//  ScanStatusView.swift
//  SUPERWAAGE
//
//  Real-time scan status indicator
//

import SwiftUI

struct ScanStatusView: View {
    @EnvironmentObject var scanViewModel: ScanViewModel

    var body: some View {
        HStack(spacing: 12) {
            // Status Icon
            statusIcon
                .font(.title3)
                .foregroundColor(.white)

            // Status Text
            VStack(alignment: .leading, spacing: 2) {
                Text(statusTitle)
                    .font(.subheadline)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                if scanViewModel.scanState == .scanning {
                    HStack(spacing: 4) {
                        Circle()
                            .fill(scanViewModel.trackingQuality.color)
                            .frame(width: 6, height: 6)
                        Text("Tracking: \(scanViewModel.trackingQuality.description)")
                            .font(.caption)
                            .foregroundColor(.white.opacity(0.9))
                    }
                }
            }

            // Progress Indicator
            if scanViewModel.scanState == .scanning {
                ProgressView(value: Double(scanViewModel.scanProgress))
                    .progressViewStyle(.linear)
                    .frame(width: 60)
                    .tint(.white)
            }

            if scanViewModel.scanState == .processing {
                ProgressView()
                    .progressViewStyle(.circular)
                    .tint(.white)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(statusColor)
        )
    }

    // MARK: - Computed Properties
    private var statusIcon: Image {
        switch scanViewModel.scanState {
        case .idle:
            return Image(systemName: "viewfinder")
        case .scanning:
            return Image(systemName: "scope")
        case .processing:
            return Image(systemName: "gearshape.2.fill")
        case .completed:
            return Image(systemName: "checkmark.circle.fill")
        case .error:
            return Image(systemName: "exclamationmark.triangle.fill")
        }
    }

    private var statusTitle: String {
        switch scanViewModel.scanState {
        case .idle:
            return "Bereit"
        case .scanning:
            return "Scannt..."
        case .processing:
            return "Verarbeitet..."
        case .completed:
            return "Abgeschlossen"
        case .error:
            return "Fehler"
        }
    }

    private var statusSubtitle: String {
        let meshCount = scanViewModel.meshAnchors.count
        return "\(meshCount) Meshes erfasst"
    }

    private var statusColor: Color {
        switch scanViewModel.scanState {
        case .idle:
            return Color.gray.opacity(0.7)
        case .scanning:
            return Color.green.opacity(0.8)
        case .processing:
            return Color.orange.opacity(0.8)
        case .completed:
            return Color.blue.opacity(0.8)
        case .error:
            return Color.red.opacity(0.8)
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        ScanStatusView()
            .environmentObject({
                let vm = ScanViewModel()
                vm.scanState = .idle
                return vm
            }())

        ScanStatusView()
            .environmentObject({
                let vm = ScanViewModel()
                vm.scanState = .scanning
                vm.scanProgress = 0.6
                return vm
            }())

        ScanStatusView()
            .environmentObject({
                let vm = ScanViewModel()
                vm.scanState = .processing
                return vm
            }())

        ScanStatusView()
            .environmentObject({
                let vm = ScanViewModel()
                vm.scanState = .completed
                return vm
            }())
    }
    .padding()
    .background(Color.gray.opacity(0.3))
}
