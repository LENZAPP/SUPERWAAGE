//
//  ContentView.swift
//  SUPERWAAGE
//
//  Main view coordinating the AR scanning and measurement display
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var scanViewModel: ScanViewModel
    @State private var showingSettings = false
    @State private var showingMaterialPicker = false
    @State private var showingHelp = false
    @State private var hasShownTapHint = false

    var body: some View {
        ZStack {
            // AR View Layer
            ARScannerView()
                .environmentObject(scanViewModel)
                .edgesIgnoringSafeArea(.all)

            // ✨ NEW: QuickUI Professional Overlays
            // Quality Badge (top-right)
            if scanViewModel.scanState == .scanning {
                StatusBadge(
                    text: "Quality: \(Int(scanViewModel.qualityScore * 100))%",
                    color: qualityColor(scanViewModel.qualityScore),
                    systemImage: "checkmark.circle.fill"
                )
            }

            // Progress Banner (bottom, above controls)
            if scanViewModel.scanState == .scanning && scanViewModel.scanProgress > 0 && scanViewModel.scanProgress < 1 {
                VStack {
                    Spacer()
                    ProgressBanner(
                        message: scanViewModel.recommendations.first ?? "Scanning...",
                        progress: scanViewModel.scanProgress
                    )
                    .padding(.bottom, 280) // Position above buttons
                }
            }

            // HUD Overlay for important messages
            if scanViewModel.scanState == .scanning, let firstRecommendation = scanViewModel.recommendations.first {
                VStack {
                    HUDOverlay(
                        message: firstRecommendation,
                        systemImage: "info.circle.fill",
                        tint: recommendationColor(firstRecommendation)
                    )
                    Spacer()
                }
            }

            // UI Overlay
            VStack {
                // Top Bar with improved visibility
                HStack {
                    // Settings Button
                    Button(action: { showingSettings.toggle() }) {
                        Image(systemName: "gear")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(Color.black.opacity(0.6))
                                    .shadow(color: .black.opacity(0.3), radius: 5)
                            )
                    }

                    Spacer()

                    // Help Button
                    Button(action: { showingHelp.toggle() }) {
                        Image(systemName: "questionmark.circle.fill")
                            .font(.title2)
                            .foregroundColor(.white)
                            .padding(12)
                            .background(
                                Circle()
                                    .fill(Color.blue.opacity(0.6))
                                    .shadow(color: .black.opacity(0.3), radius: 5)
                            )
                    }

                    Spacer()

                    // Scan Status Indicator
                    ScanStatusView()
                        .environmentObject(scanViewModel)
                }
                .padding()

                // Helpful Instructions Banner
                if scanViewModel.scanState == .idle {
                    VStack(spacing: 8) {
                        Image(systemName: "hand.tap.fill")
                            .font(.largeTitle)
                            .foregroundColor(.blue)

                        Text("Bereit zum Scannen")
                            .font(.headline)
                            .fontWeight(.bold)

                        Text("Tippe auf \"Objekt scannen\" um zu beginnen")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 16)
                            .fill(Color(.systemBackground).opacity(0.9))
                            .shadow(color: .black.opacity(0.1), radius: 10)
                    )
                    .padding(.horizontal)
                    .transition(.move(edge: .top).combined(with: .opacity))
                }

                // Scan Metrics Overlay (AI/LiDAR Performance Monitoring)
                if scanViewModel.scanState == .scanning {
                    ScanMetricsOverlay(viewModel: scanViewModel)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }

                Spacer()

                // Interactive Scan Instructions
                if scanViewModel.scanState == .scanning {
                    VStack(spacing: 12) {
                        // Tap Instruction with Animation
                        if !scanViewModel.isObjectSelected {
                            HStack(spacing: 8) {
                                Image(systemName: "hand.tap.fill")
                                    .font(.title3)
                                    .foregroundColor(.blue)

                                Text("Tippe auf ein Objekt zum Auswählen")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.blue.opacity(0.2))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color.blue, lineWidth: 2)
                                    )
                            )
                            .transition(.scale.combined(with: .opacity))
                        }

                        // Object Selected Confirmation
                        if scanViewModel.isObjectSelected {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .font(.title3)
                                    .foregroundColor(.green)

                                Text("Objekt ausgewählt!")
                                    .font(.subheadline)
                                    .fontWeight(.semibold)
                            }
                            .padding(.horizontal, 16)
                            .padding(.vertical, 10)
                            .background(
                                Capsule()
                                    .fill(Color.green.opacity(0.2))
                                    .overlay(
                                        Capsule()
                                            .strokeBorder(Color.green, lineWidth: 2)
                                    )
                            )
                            .transition(.scale.combined(with: .opacity))
                        }

                        // Crosshair
                        Image(systemName: scanViewModel.isObjectSelected ? "checkmark.circle" : "scope")
                            .font(.system(size: 44))
                            .foregroundColor(scanViewModel.isObjectSelected ? .green.opacity(0.7) : .blue.opacity(0.7))
                            .animation(.easeInOut(duration: 0.3), value: scanViewModel.isObjectSelected)
                    }
                }

                Spacer()

                // Bottom Controls and Results (Scrollable for accessibility)
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(spacing: 16) {
                        // Scan Progress View (During Scanning)
                        if scanViewModel.scanState == .scanning {
                            ScanProgressView(
                                progress: scanViewModel.scanProgress,
                                qualityScore: scanViewModel.qualityScore,
                                pointCount: scanViewModel.pointCount,
                                confidence: Double(scanViewModel.averageConfidence),
                                coverageScore: Double(scanViewModel.coverageScore),
                                recommendations: scanViewModel.recommendations
                            )
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Measurement Results Card (After Scanning)
                        if scanViewModel.scanState == .completed {
                            MeasurementResultsCard()
                                .environmentObject(scanViewModel)
                                .transition(.move(edge: .bottom).combined(with: .opacity))
                        }

                        // Control Buttons - Enhanced with better UX
                        VStack(spacing: 12) {
                            // Primary Action Button
                            if scanViewModel.scanState == .idle || scanViewModel.scanState == .completed {
                                Button(action: {
                                    withAnimation {
                                        scanViewModel.startScanning()
                                    }
                                }) {
                                    HStack(spacing: 12) {
                                        Image(systemName: scanViewModel.scanState == .idle ? "camera.fill" : "arrow.triangle.2.circlepath.camera.fill")
                                            .font(.title3)

                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(scanViewModel.scanState == .idle ? "Objekt scannen" : "Neuen Scan starten")
                                                .fontWeight(.bold)
                                                .font(.headline)

                                            Text(scanViewModel.scanState == .idle ? "LiDAR aktivieren" : "Vorherigen Scan verwerfen")
                                                .font(.caption)
                                                .opacity(0.9)
                                        }

                                        Spacer()

                                        Image(systemName: "chevron.right")
                                            .font(.caption)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding()
                                    .background(
                                        LinearGradient(
                                            colors: [Color.blue, Color.blue.opacity(0.8)],
                                            startPoint: .leading,
                                            endPoint: .trailing
                                        )
                                    )
                                    .foregroundColor(.white)
                                    .cornerRadius(16)
                                    .shadow(color: Color.blue.opacity(0.3), radius: 8, y: 4)
                                }
                            }

                            // Scanning State Buttons
                            if scanViewModel.scanState == .scanning {
                                HStack(spacing: 12) {
                                    // Complete Scan Button
                                    Button(action: {
                                        withAnimation {
                                            scanViewModel.completeScan()
                                        }
                                    }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "checkmark.circle.fill")
                                                .font(.title3)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Fertig")
                                                    .fontWeight(.bold)

                                                Text("Scan beenden")
                                                    .font(.caption2)
                                                    .opacity(0.9)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(
                                            LinearGradient(
                                                colors: [Color.green, Color.green.opacity(0.8)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .foregroundColor(.white)
                                        .cornerRadius(16)
                                        .shadow(color: Color.green.opacity(0.3), radius: 8, y: 4)
                                    }

                                    // Cancel Button
                                    Button(action: {
                                        withAnimation {
                                            scanViewModel.reset()
                                        }
                                    }) {
                                        VStack(spacing: 4) {
                                            Image(systemName: "xmark.circle.fill")
                                                .font(.title2)

                                            Text("Abbrechen")
                                                .font(.caption2)
                                                .fontWeight(.semibold)
                                        }
                                        .frame(width: 90)
                                        .padding(.vertical, 12)
                                        .background(Color.red.opacity(0.15))
                                        .foregroundColor(.red)
                                        .cornerRadius(16)
                                        .overlay(
                                            RoundedRectangle(cornerRadius: 16)
                                                .strokeBorder(Color.red.opacity(0.3), lineWidth: 2)
                                        )
                                    }
                                }
                            }

                            // Completed State Buttons
                            if scanViewModel.scanState == .completed {
                                HStack(spacing: 12) {
                                    // Material Picker
                                    Button(action: { showingMaterialPicker.toggle() }) {
                                        HStack(spacing: 8) {
                                            Image(systemName: "cube.fill")
                                                .font(.title3)

                                            VStack(alignment: .leading, spacing: 2) {
                                                Text("Material ändern")
                                                    .fontWeight(.bold)

                                                Text(scanViewModel.selectedMaterial.name)
                                                    .font(.caption2)
                                                    .opacity(0.9)
                                            }
                                        }
                                        .frame(maxWidth: .infinity)
                                        .padding()
                                        .background(
                                            LinearGradient(
                                                colors: [Color.orange, Color.orange.opacity(0.8)],
                                                startPoint: .leading,
                                                endPoint: .trailing
                                            )
                                        )
                                        .foregroundColor(.white)
                                        .cornerRadius(16)
                                        .shadow(color: Color.orange.opacity(0.3), radius: 8, y: 4)
                                    }
                                }
                            }
                        }
                    .padding(.horizontal)
                    .padding(.bottom, 60) // Extra bottom padding for buttons visibility and safe area
                    }
                }
            }
        }
        .sheet(isPresented: $showingSettings) {
            SettingsView()
        }
        .sheet(isPresented: $showingMaterialPicker) {
            MaterialPickerView()
                .environmentObject(scanViewModel)
        }
        .sheet(isPresented: $showingHelp) {
            HelpView()
        }
        .animation(.easeInOut, value: scanViewModel.scanState)
        .animation(.easeInOut, value: scanViewModel.isObjectSelected)
    }

    // ✨ NEW: Helper functions for QuickUI
    private func qualityColor(_ quality: Double) -> Color {
        if quality >= 0.75 { return .green }
        if quality >= 0.5 { return .orange }
        return .red
    }

    private func recommendationColor(_ recommendation: String) -> Color {
        let lowercased = recommendation.lowercased()
        if lowercased.contains("good") || lowercased.contains("gut") {
            return .green
        } else if lowercased.contains("improve") || lowercased.contains("verbessern") {
            return .orange
        }
        return .blue
    }
}

// MARK: - Help View
struct HelpView: View {
    @Environment(\.dismiss) var dismiss

    var body: some View {
        NavigationView {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    // Quick Start Guide
                    HelpSection(
                        icon: "play.circle.fill",
                        iconColor: .blue,
                        title: "Schnellstart",
                        steps: [
                            "Tippe auf \"Objekt scannen\" um die Kamera zu aktivieren",
                            "Tippe auf das Objekt das du messen möchtest",
                            "Bewege dein iPhone langsam um das Objekt herum",
                            "Tippe auf \"Fertig\" wenn das Objekt vollständig gescannt ist",
                            "Wähle das Material für präzise Gewichtsberechnung"
                        ]
                    )

                    Divider()

                    // Tap to Select
                    HelpSection(
                        icon: "hand.tap.fill",
                        iconColor: .green,
                        title: "Tap-to-Select",
                        steps: [
                            "Während des Scannens kannst du auf ein Objekt tippen",
                            "Das Objekt wird automatisch erkannt und ausgewählt",
                            "Eine 3D-Bounding-Box erscheint um das Objekt",
                            "Messungen werden in Echtzeit angezeigt"
                        ]
                    )

                    Divider()

                    // Tips for Best Results
                    HelpSection(
                        icon: "lightbulb.fill",
                        iconColor: .orange,
                        title: "Tipps für beste Ergebnisse",
                        steps: [
                            "Gute Beleuchtung verbessert die Scan-Qualität",
                            "Halte das iPhone stabil und bewege es langsam",
                            "Scanne das Objekt aus mehreren Winkeln",
                            "Verwende die Kalibrierung mit einer Münze für höhere Präzision",
                            "Vermeide reflektierende oder transparente Oberflächen"
                        ]
                    )

                    Divider()

                    // Calibration
                    HelpSection(
                        icon: "target",
                        iconColor: .purple,
                        title: "Kalibrierung (Optional)",
                        steps: [
                            "Öffne Einstellungen und wähle \"Kalibrierung\"",
                            "Platziere eine 1€ Münze oder EC-Karte",
                            "Scanne das Referenzobjekt",
                            "Die Kalibrierung verbessert die Messgenauigkeit um bis zu 30%"
                        ]
                    )

                    Divider()

                    // Supported Devices
                    VStack(alignment: .leading, spacing: 8) {
                        Label("Unterstützte Geräte", systemImage: "iphone")
                            .font(.headline)
                            .foregroundColor(.primary)

                        Text("Diese App benötigt ein iPhone mit LiDAR-Sensor:")
                            .font(.subheadline)
                            .foregroundColor(.secondary)

                        VStack(alignment: .leading, spacing: 4) {
                            Text("• iPhone 12 Pro / Pro Max")
                            Text("• iPhone 13 Pro / Pro Max")
                            Text("• iPhone 14 Pro / Pro Max")
                            Text("• iPhone 15 Pro / Pro Max")
                            Text("• iPad Pro (2020 oder neuer)")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .padding(.leading)
                    }
                }
                .padding()
            }
            .navigationTitle("Hilfe & Anleitung")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                    .fontWeight(.semibold)
                }
            }
        }
    }
}

// MARK: - Help Section
struct HelpSection: View {
    let icon: String
    let iconColor: Color
    let title: String
    let steps: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label(title, systemImage: icon)
                .font(.headline)
                .foregroundColor(iconColor)

            VStack(alignment: .leading, spacing: 8) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    HStack(alignment: .top, spacing: 12) {
                        Text("\(index + 1)")
                            .font(.caption)
                            .fontWeight(.bold)
                            .foregroundColor(.white)
                            .frame(width: 24, height: 24)
                            .background(Circle().fill(iconColor.opacity(0.8)))

                        Text(step)
                            .font(.subheadline)
                            .foregroundColor(.primary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(ScanViewModel())
}
