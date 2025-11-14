//
//  ExportOptionsView.swift
//  SUPERWAAGE
//
//  3D Model export options UI
//

import SwiftUI
import UIKit

struct ExportOptionsView: View {
    @EnvironmentObject var scanViewModel: ScanViewModel
    @Environment(\.dismiss) var dismiss
    @Binding var isExporting: Bool

    @State private var selectedFormat: MeshExportFormat = .obj
    @State private var fileName: String = ""
    @State private var exportResult: MeshExportResult?
    @State private var errorMessage: String?

    var body: some View {
        NavigationView {
            Form {
                Section("Format auswählen") {
                    ForEach(MeshExportFormat.allCases, id: \.self) { format in
                        HStack {
                            VStack(alignment: .leading, spacing: 4) {
                                Text(format.rawValue)
                                    .font(.subheadline)
                                    .fontWeight(.medium)

                                Text(formatDescription(format))
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }

                            Spacer()

                            if selectedFormat == format {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.blue)
                            }
                        }
                        .contentShape(Rectangle())
                        .onTapGesture {
                            selectedFormat = format
                        }
                    }
                }

                Section("Dateiname") {
                    TextField("SUPERWAAGE_Scan", text: $fileName)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }

                if let result = exportResult {
                    Section("Export erfolgreich") {
                        VStack(alignment: .leading, spacing: 8) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("3D-Modell exportiert")
                                    .fontWeight(.semibold)
                            }

                            Divider()

                            DetailRow(label: "Format", value: result.format.rawValue)
                            DetailRow(label: "Dateigröße", value: formatFileSize(result.fileSize))
                            DetailRow(label: "Vertices", value: "\(result.vertexCount)")
                            DetailRow(label: "Dreiecke", value: "\(result.triangleCount)")
                            DetailRow(label: "Export-Dauer", value: String(format: "%.2f s", result.exportDuration))

                            Button(action: { shareFile(url: result.url) }) {
                                HStack {
                                    Image(systemName: "square.and.arrow.up")
                                    Text("Datei teilen")
                                        .fontWeight(.semibold)
                                }
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                            }
                        }
                    }
                }

                if let error = errorMessage {
                    Section {
                        HStack {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .foregroundColor(.red)
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        }
                    }
                }

                Section {
                    Button(action: { performExport() }) {
                        HStack {
                            Spacer()
                            if isExporting {
                                ProgressView()
                                    .progressViewStyle(.circular)
                                Text("Exportiere...")
                                    .fontWeight(.semibold)
                            } else {
                                Image(systemName: "arrow.down.doc")
                                Text("3D-Modell exportieren")
                                    .fontWeight(.semibold)
                            }
                            Spacer()
                        }
                    }
                    .disabled(isExporting || exportResult != nil)
                }
            }
            .navigationTitle("3D-Export")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            // Set default filename
            let timestamp = DateFormatter.localizedString(from: Date(), dateStyle: .short, timeStyle: .short)
            fileName = "SUPERWAAGE_\(timestamp.replacingOccurrences(of: " ", with: "_"))"
        }
    }

    // MARK: - Actions

    private func performExport() {
        isExporting = true
        errorMessage = nil

        Task {
            do {
                let result = try await scanViewModel.export3DModel(
                    format: selectedFormat,
                    fileName: fileName
                )

                await MainActor.run {
                    exportResult = result
                    isExporting = false
                }
            } catch {
                await MainActor.run {
                    errorMessage = error.localizedDescription
                    isExporting = false
                }
            }
        }
    }

    private func shareFile(url: URL) {
        let activityVC = UIActivityViewController(activityItems: [url], applicationActivities: nil)

        if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
           let window = windowScene.windows.first,
           let rootVC = window.rootViewController {
            rootVC.present(activityVC, animated: true)
        }
    }

    // MARK: - Helpers

    private func formatDescription(_ format: MeshExportFormat) -> String {
        switch format {
        case .obj:
            return "Wavefront OBJ - Kompatibel mit allen 3D-Apps"
        case .ply:
            return "Polygon File Format - Enthält Farben & Normalen"
        case .usdz:
            return "Apple AR Format - Optimal für iOS/macOS"
        }
    }

    private func formatFileSize(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}
