//
//  SettingsView.swift
//  SUPERWAAGE
//
//  App settings and configuration
//

import SwiftUI
import ARKit

struct SettingsView: View {
    @Environment(\.dismiss) var dismiss
    @AppStorage("measurementUnit") private var measurementUnit = "metric"
    @AppStorage("showDebugInfo") private var showDebugInfo = false
    @AppStorage("enableHaptics") private var enableHaptics = true
    @AppStorage("scanQuality") private var scanQuality = "high"
    @StateObject private var calibrationManager = CalibrationManager.shared
    @State private var showingQuickCalibration = false

    var body: some View {
        NavigationView {
            Form {
                // Measurement Settings
                Section("Messeinstellungen") {
                    Picker("Einheitensystem", selection: $measurementUnit) {
                        Text("Metrisch (cm, g)").tag("metric")
                        Text("Imperial (in, oz)").tag("imperial")
                    }

                    Picker("Scan-Qualität", selection: $scanQuality) {
                        Text("Niedrig (schneller)").tag("low")
                        Text("Mittel").tag("medium")
                        Text("Hoch (genauer)").tag("high")
                    }
                }

                // ✨ NEW: Calibration Section
                Section {
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Label("Kalibrierung", systemImage: "target")
                                .font(.headline)
                            Spacer()
                            Image(systemName: calibrationManager.isCalibrated ? "checkmark.circle.fill" : "exclamationmark.circle")
                                .foregroundColor(calibrationManager.isCalibrated ? .green : .orange)
                        }

                        VStack(alignment: .leading, spacing: 6) {
                            InfoRow(
                                label: "Status",
                                value: calibrationManager.isCalibrated ? "Kalibriert" : "Nicht kalibriert"
                            )

                            if calibrationManager.isCalibrated {
                                InfoRow(
                                    label: "Genauigkeit",
                                    value: String(format: "%.1f%%", calibrationManager.calibrationAccuracy)
                                )
                                if let factor = calibrationManager.calibrationFactor {
                                    InfoRow(
                                        label: "Faktor",
                                        value: String(format: "%.4f", factor)
                                    )
                                }
                                if let date = calibrationManager.lastCalibrationDate {
                                    InfoRow(
                                        label: "Datum",
                                        value: date.formatted(date: .abbreviated, time: .omitted)
                                    )
                                }
                            }
                        }

                        // Quick Calibration
                        Button(action: {
                            showingQuickCalibration = true
                        }) {
                            HStack {
                                Label(
                                    calibrationManager.isCalibrated ? "Neu kalibrieren (10 Sek.)" : "Kalibrieren (10 Sek.)",
                                    systemImage: "target"
                                )
                                Spacer()
                                Image(systemName: "sparkles")
                                    .font(.caption)
                                    .foregroundColor(.yellow)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                        }
                        .buttonStyle(.borderedProminent)

                        if calibrationManager.isCalibrated {
                            Button(role: .destructive) {
                                calibrationManager.resetCalibration()
                            } label: {
                                Label("Kalibrierung zurücksetzen", systemImage: "arrow.counterclockwise")
                                    .frame(maxWidth: .infinity)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 8)
                } header: {
                    Text("Kalibrierung")
                } footer: {
                    Text("Quick Calibration: Automatische Erkennung mit 1-Euro-Münze, Bankkarte oder 5-cm-Würfel. Verbessert Messgenauigkeit durch Multi-Angle-Kalibrierung und Depth-Bias-Korrektur.")
                        .font(.caption)
                }

                // App Behavior
                Section("App-Verhalten") {
                    Toggle("Haptisches Feedback", isOn: $enableHaptics)
                    Toggle("Debug-Informationen", isOn: $showDebugInfo)
                }

                // ✨ NEW: Hardware Connections
                Section("Hardware") {
                    NavigationLink {
                        BLEPairingView()
                    } label: {
                        Label("Waage verbinden", systemImage: "scalemass.fill")
                    }
                }

                // About Section
                Section("Über SUPERWAAGE") {
                    HStack {
                        Text("Version")
                        Spacer()
                        Text("1.0.0")
                            .foregroundColor(.secondary)
                    }

                    HStack {
                        Text("Build")
                        Spacer()
                        Text("2025.01")
                            .foregroundColor(.secondary)
                    }
                }

                // Device Info
                Section("Geräte-Informationen") {
                    InfoRow(label: "LiDAR verfügbar", value: deviceHasLiDAR ? "Ja ✓" : "Nein ✗")
                    InfoRow(label: "ARKit Version", value: "6.0+")
                }

                // Tips
                Section("Tipps für beste Ergebnisse") {
                    VStack(alignment: .leading, spacing: 12) {
                        TipRow(
                            icon: "lightbulb.fill",
                            text: "Scannen Sie bei gutem Licht für optimale Genauigkeit"
                        )
                        TipRow(
                            icon: "move.3d",
                            text: "Bewegen Sie die Kamera langsam um das Objekt herum"
                        )
                        TipRow(
                            icon: "cube.fill",
                            text: "Objekte sollten mindestens 5cm groß sein"
                        )
                        TipRow(
                            icon: "hand.raised.fill",
                            text: "Halten Sie 20-50cm Abstand zum Objekt"
                        )
                    }
                    .padding(.vertical, 8)
                }
            }
            .navigationTitle("Einstellungen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
            .fullScreenCover(isPresented: $showingQuickCalibration) {
                QuickCalibrationFlow()
            }
        }
    }

    private var deviceHasLiDAR: Bool {
        ARWorldTrackingConfiguration.supportsSceneReconstruction(.mesh)
    }
}

struct InfoRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundColor(.secondary)
        }
    }
}

struct TipRow: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: icon)
                .foregroundColor(.blue)
                .frame(width: 24)

            Text(text)
                .font(.subheadline)
                .foregroundColor(.secondary)
        }
    }
}

#Preview {
    SettingsView()
}
