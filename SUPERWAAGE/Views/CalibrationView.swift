//
//  CalibrationView.swift
//  SUPERWAAGE
//
//  Calibration workflow using 1 Euro coin scan
//

import SwiftUI

struct CalibrationView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var scanViewModel = ScanViewModel()
    @StateObject private var calibrationManager = CalibrationManager.shared

    @State private var calibrationStep: CalibrationStep = .instructions
    @State private var showingSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""

    enum CalibrationStep {
        case instructions
        case scanning
        case processing
        case completed
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background color
                Color.black.edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    switch calibrationStep {
                    case .instructions:
                        instructionsView
                    case .scanning:
                        scanningView
                    case .processing:
                        processingView
                    case .completed:
                        completedView
                    }
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("Abbrechen") {
                        dismiss()
                    }
                    .foregroundColor(.white)
                }
            }
            .alert("Kalibrierung erfolgreich!", isPresented: $showingSuccess) {
                Button("OK") {
                    dismiss()
                }
            } message: {
                Text("Die App wurde erfolgreich mit der 1 Euro Münze kalibriert.\n\nGenauigkeit: \(String(format: "%.1f%%", calibrationManager.calibrationAccuracy))")
            }
            .alert("Kalibrierung fehlgeschlagen", isPresented: $showingError) {
                Button("Erneut versuchen") {
                    calibrationStep = .instructions
                }
                Button("Abbrechen", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Instructions View
    private var instructionsView: some View {
        VStack(spacing: 24) {
            Spacer()

            // Icon
            Image(systemName: "eurosign.circle.fill")
                .font(.system(size: 100))
                .foregroundColor(.yellow)

            // Title
            Text("Kalibrierung")
                .font(.largeTitle)
                .fontWeight(.bold)
                .foregroundColor(.white)

            // Instructions
            VStack(alignment: .leading, spacing: 16) {
                InstructionRow(
                    number: "1",
                    text: "Legen Sie eine 1 Euro Münze auf eine flache Oberfläche"
                )
                InstructionRow(
                    number: "2",
                    text: "Tippen Sie auf die Münze, um sie auszuwählen"
                )
                InstructionRow(
                    number: "3",
                    text: "Scannen Sie die Münze von allen Seiten"
                )
                InstructionRow(
                    number: "4",
                    text: "Warten Sie auf die Verarbeitung"
                )
            }
            .padding(.horizontal, 32)

            // Coin specs
            VStack(spacing: 8) {
                Text("1 Euro Münze Spezifikationen:")
                    .font(.headline)
                    .foregroundColor(.white.opacity(0.8))

                HStack(spacing: 24) {
                    VStack {
                        Text("Ø 23,25mm")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    VStack {
                        Text("⬍ 2,20mm")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                    VStack {
                        Text("≈ 0,93ml")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.top, 16)

            Spacer()

            // Start Button
            Button(action: {
                startCalibration()
            }) {
                Text("Kalibrierung starten")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.yellow)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Scanning View
    private var scanningView: some View {
        ZStack {
            // AR Scanner
            ARScannerView()
                .environmentObject(scanViewModel)
                .edgesIgnoringSafeArea(.all)

            // Overlay UI
            VStack {
                // Top info
                VStack(spacing: 8) {
                    Text("Münze scannen")
                        .font(.title2)
                        .fontWeight(.bold)
                        .foregroundColor(.white)
                        .shadow(radius: 4)

                    if !scanViewModel.isObjectSelected {
                        Text("Tippen Sie auf die 1 Euro Münze")
                            .font(.subheadline)
                            .foregroundColor(.yellow)
                            .padding(.horizontal, 16)
                            .padding(.vertical, 8)
                            .background(Color.black.opacity(0.7))
                            .cornerRadius(8)
                    } else {
                        HStack(spacing: 16) {
                            Image(systemName: "checkmark.circle.fill")
                                .foregroundColor(.green)
                            Text("\(scanViewModel.pointCount) Punkte")
                                .font(.subheadline)
                                .foregroundColor(.white)
                        }
                        .padding(.horizontal, 16)
                        .padding(.vertical, 8)
                        .background(Color.black.opacity(0.7))
                        .cornerRadius(8)
                    }
                }
                .padding(.top, 60)

                Spacer()

                // Bottom controls
                VStack(spacing: 16) {
                    // Complete button
                    if scanViewModel.isObjectSelected && scanViewModel.pointCount > 500 {
                        Button(action: {
                            completeCalibrationScan()
                        }) {
                            Text("Scan abschließen")
                                .font(.headline)
                                .foregroundColor(.black)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.yellow)
                                .cornerRadius(12)
                        }
                        .padding(.horizontal, 32)
                    }

                    // Cancel
                    Button(action: {
                        scanViewModel.reset()
                        calibrationStep = .instructions
                    }) {
                        Text("Abbrechen")
                            .foregroundColor(.white)
                            .padding()
                    }
                }
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Processing View
    private var processingView: some View {
        VStack(spacing: 24) {
            Spacer()

            ProgressView()
                .scaleEffect(2)
                .tint(.yellow)

            Text("Münze wird verarbeitet...")
                .font(.title2)
                .fontWeight(.semibold)
                .foregroundColor(.white)

            Text("Bitte warten")
                .font(.subheadline)
                .foregroundColor(.white.opacity(0.7))

            Spacer()
        }
    }

    // MARK: - Completed View
    private var completedView: some View {
        VStack(spacing: 24) {
            Spacer()

            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 100))
                .foregroundColor(.green)

            Text("Kalibrierung erfolgreich!")
                .font(.title)
                .fontWeight(.bold)
                .foregroundColor(.white)

            VStack(spacing: 12) {
                InfoRow(
                    label: "Genauigkeit",
                    value: String(format: "%.1f%%", calibrationManager.calibrationAccuracy)
                )
                .foregroundColor(.white)

                if let factor = calibrationManager.calibrationFactor {
                    InfoRow(
                        label: "Kalibrierfaktor",
                        value: String(format: "%.4f", factor)
                    )
                    .foregroundColor(.white)
                }
            }
            .padding()
            .background(Color.white.opacity(0.1))
            .cornerRadius(12)
            .padding(.horizontal, 32)

            Spacer()

            Button(action: {
                dismiss()
            }) {
                Text("Fertig")
                    .font(.headline)
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(Color.yellow)
                    .cornerRadius(12)
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 32)
        }
    }

    // MARK: - Helper Methods

    private func startCalibration() {
        calibrationStep = .scanning
        scanViewModel.startScanning()
    }

    private func completeCalibrationScan() {
        calibrationStep = .processing
        scanViewModel.completeScan()

        // Wait for scan processing to complete
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            processCalibrationResults()
        }
    }

    private func processCalibrationResults() {
        // Get scanned measurements
        let volume = scanViewModel.volumeML
        let dimensions = scanViewModel.dimensions

        // Perform volume-based calibration with Euro coin
        let result = calibrationManager.calibrateWithVolume(
            with: .euroCoin1,
            scannedVolume: volume,
            scannedDimensions: dimensions
        )

        if result.success {
            calibrationStep = .completed
            showingSuccess = true
        } else {
            errorMessage = result.message + "\n\nTipps:\n• Scannen Sie bei gutem Licht\n• Erfassen Sie die Münze von allen Seiten\n• Halten Sie 20-30cm Abstand"
            showingError = true
        }

        scanViewModel.reset()
    }
}

// MARK: - Instruction Row
struct InstructionRow: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 16) {
            Text(number)
                .font(.title2)
                .fontWeight(.bold)
                .foregroundColor(.yellow)
                .frame(width: 32, height: 32)
                .background(Color.white.opacity(0.1))
                .clipShape(Circle())

            Text(text)
                .font(.body)
                .foregroundColor(.white)

            Spacer()
        }
    }
}

#Preview {
    CalibrationView()
}
