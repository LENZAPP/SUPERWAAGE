//
//  ImprovedCalibrationView.swift
//  SUPERWAAGE
//
//  Benutzerfreundliche Step-by-Step AR-Kalibrierung mit virtueller Münzen-Hülle
//

import SwiftUI
import simd

struct ImprovedCalibrationView: View {
    @Environment(\.dismiss) var dismiss
    @StateObject private var scanViewModel = ScanViewModel()
    @StateObject private var calibrationManager = CalibrationManager.shared

    @State private var currentStep: CalibrationStep = .welcome
    @State private var coinPosition: SIMD3<Float>? = nil
    @State private var isCoinPlaced = false
    @State private var isCoinAligned = false
    @State private var cameraAngle: Float = 45.0  // Camera angle from vertical
    @State private var showingSuccess = false
    @State private var showingError = false
    @State private var errorMessage = ""

    enum CalibrationStep: Int, CaseIterable {
        case welcome = 0
        case prepare = 1
        case placeVirtualCoin = 2
        case scanning = 3
        case processing = 4
        case completed = 5

        var title: String {
            switch self {
            case .welcome: return "Willkommen"
            case .prepare: return "Vorbereitung"
            case .placeVirtualCoin: return "Münze ausrichten"
            case .scanning: return "Scannen"
            case .processing: return "Verarbeitung"
            case .completed: return "Fertig!"
            }
        }

        var icon: String {
            switch self {
            case .welcome: return "hand.wave.fill"
            case .prepare: return "eurosign.circle.fill"
            case .placeVirtualCoin: return "move.3d"
            case .scanning: return "viewfinder.circle.fill"
            case .processing: return "gearshape.2.fill"
            case .completed: return "checkmark.circle.fill"
            }
        }

        var color: Color {
            switch self {
            case .welcome: return .blue
            case .prepare: return .yellow
            case .placeVirtualCoin: return .orange
            case .scanning: return .purple
            case .processing: return .cyan
            case .completed: return .green
            }
        }
    }

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color.black.edgesIgnoringSafeArea(.all)

                VStack(spacing: 0) {
                    // Progress indicator
                    progressBar

                    // Main content
                    content
                        .transition(.asymmetric(insertion: .move(edge: .trailing), removal: .move(edge: .leading)))
                }
            }
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { dismiss() }) {
                        Image(systemName: "xmark")
                            .foregroundColor(.white)
                    }
                }
                ToolbarItem(placement: .principal) {
                    Text(currentStep.title)
                        .font(.headline)
                        .foregroundColor(.white)
                }
            }
            .alert("Kalibrierung erfolgreich!", isPresented: $showingSuccess) {
                Button("Fertig") {
                    dismiss()
                }
            } message: {
                Text("Die App wurde mit \(String(format: "%.1f%%", calibrationManager.calibrationAccuracy)) Genauigkeit kalibriert!")
            }
            .alert("Fehler", isPresented: $showingError) {
                Button("Erneut versuchen") {
                    currentStep = .prepare
                }
                Button("Abbrechen", role: .cancel) {
                    dismiss()
                }
            } message: {
                Text(errorMessage)
            }
        }
    }

    // MARK: - Progress Bar

    private var progressBar: some View {
        HStack(spacing: 4) {
            ForEach(0..<CalibrationStep.allCases.count, id: \.self) { index in
                let step = CalibrationStep(rawValue: index)!
                let isActive = currentStep.rawValue >= index

                Rectangle()
                    .fill(isActive ? step.color : Color.white.opacity(0.3))
                    .frame(height: 4)
                    .animation(.easeInOut, value: currentStep)
            }
        }
        .padding(.horizontal)
        .padding(.top, 8)
    }

    // MARK: - Content

    @ViewBuilder
    private var content: some View {
        switch currentStep {
        case .welcome:
            welcomeView
        case .prepare:
            prepareView
        case .placeVirtualCoin:
            placeVirtualCoinView
        case .scanning:
            scanningView
        case .processing:
            processingView
        case .completed:
            completedView
        }
    }

    // MARK: - Step 1: Welcome

    private var welcomeView: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 40)

                // Icon
                Image(systemName: currentStep.icon)
                    .font(.system(size: 80))
                    .foregroundColor(currentStep.color)

                // Title
                VStack(spacing: 12) {
                    Text("Kalibrierung")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("Erhöhen Sie die Messgenauigkeit um bis zu 30%")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }

                // What you need
                VStack(alignment: .leading, spacing: 16) {
                    Text("Was Sie benötigen:")
                        .font(.headline)
                        .foregroundColor(.white)

                    FeatureRow(
                        icon: "eurosign.circle.fill",
                        title: "1 Euro Münze",
                        description: "Saubere Münze ohne Kratzer"
                    )

                    FeatureRow(
                        icon: "square.on.square",
                        title: "Flache Oberfläche",
                        description: "Tisch oder ebener Untergrund"
                    )

                    FeatureRow(
                        icon: "light.max",
                        title: "Gute Beleuchtung",
                        description: "Helles Tageslicht oder Lampe"
                    )

                    FeatureRow(
                        icon: "clock.fill",
                        title: "2-3 Minuten Zeit",
                        description: "Ruhige Umgebung"
                    )
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(16)
                .padding(.horizontal)

                Spacer()

                // Next button
                Button(action: { withAnimation { currentStep = .prepare } }) {
                    HStack {
                        Text("Jetzt starten")
                            .font(.headline)
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(currentStep.color)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Step 2: Prepare

    private var prepareView: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 20)

                // Icon
                Image(systemName: currentStep.icon)
                    .font(.system(size: 80))
                    .foregroundColor(currentStep.color)

                // Title
                VStack(spacing: 12) {
                    Text("Münze vorbereiten")
                        .font(.title)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("Legen Sie die 1 Euro Münze bereit")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                        .multilineTextAlignment(.center)
                }

                // Coin visualization
                VStack(spacing: 16) {
                    // Large coin circle
                    ZStack {
                        Circle()
                            .fill(
                                LinearGradient(
                                    colors: [Color.yellow, Color.orange],
                                    startPoint: .topLeading,
                                    endPoint: .bottomTrailing
                                )
                            )
                            .frame(width: 150, height: 150)
                            .shadow(radius: 10)

                        Text("€")
                            .font(.system(size: 60, weight: .bold))
                            .foregroundColor(.white)
                    }

                    // Specs
                    VStack(spacing: 8) {
                        HStack(spacing: 20) {
                            SpecBadge(icon: "arrow.left.and.right", value: "Ø 23,25 mm")
                            SpecBadge(icon: "arrow.up.and.down", value: "⬍ 2,20 mm")
                        }
                        SpecBadge(icon: "cube.fill", value: "≈ 0,93 ml")
                    }
                }

                // Instructions
                VStack(alignment: .leading, spacing: 16) {
                    StepInstruction(
                        number: "1",
                        text: "Legen Sie die Münze flach auf einen Tisch"
                    )
                    StepInstruction(
                        number: "2",
                        text: "Sorgen Sie für gute Beleuchtung"
                    )
                    StepInstruction(
                        number: "3",
                        text: "Entfernen Sie andere Objekte aus der Nähe"
                    )
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(16)
                .padding(.horizontal)

                Spacer()

                // Next button
                Button(action: { withAnimation { currentStep = .placeVirtualCoin } }) {
                    HStack {
                        Text("Weiter")
                            .font(.headline)
                        Image(systemName: "arrow.right")
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(currentStep.color)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Step 3: Place Virtual Coin

    private var placeVirtualCoinView: some View {
        ZStack {
            // AR View with improved virtual coin placement
            ImprovedCoinPlacementARView(
                coinPosition: $coinPosition,
                isPlaced: $isCoinPlaced,
                isAligned: $isCoinAligned,
                cameraAngle: $cameraAngle
            )
            .edgesIgnoringSafeArea(.all)

            // Overlay UI
            VStack {
                // Camera angle guidance (Vogelperspektive)
                VStack(spacing: 12) {
                    HStack(spacing: 12) {
                        Image(systemName: cameraAngleIcon)
                            .font(.title)
                            .foregroundColor(cameraAngleColor)

                        VStack(alignment: .leading, spacing: 4) {
                            Text(cameraAngleText)
                                .font(.headline)
                                .foregroundColor(.white)
                            Text("\(Int(cameraAngle))° von vertikal")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.7))
                        }

                        Spacer()
                    }
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(cameraAngleBackgroundColor)
                        .shadow(radius: 10)
                )
                .padding(.horizontal)
                .padding(.top, 60)

                // Main instructions
                VStack(spacing: 16) {
                    Image(systemName: currentStep.icon)
                        .font(.system(size: 40))
                        .foregroundColor(currentStep.color)

                    VStack(spacing: 8) {
                        if !isCoinPlaced {
                            Text("Schauen Sie von oben")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)

                            Text("Dann auf den Tisch tippen")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        } else if !isCoinAligned {
                            Text("Münze mit Finger verschieben")
                                .font(.title3)
                                .fontWeight(.semibold)
                                .foregroundColor(.white)

                            Text("Genau über die echte Münze platzieren")
                                .font(.caption)
                                .foregroundColor(.white.opacity(0.8))
                        } else {
                            HStack(spacing: 8) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("Perfekt ausgerichtet!")
                                    .foregroundColor(.white)
                            }
                            .font(.headline)
                        }
                    }
                    .multilineTextAlignment(.center)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.7))
                        .shadow(radius: 10)
                )
                .padding(.horizontal)

                Spacer()

                // Alignment indicator
                if isCoinPlaced {
                    HStack(spacing: 16) {
                        VStack {
                            Image(systemName: isCoinPlaced ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isCoinPlaced ? .green : .white.opacity(0.5))
                            Text("Platziert")
                                .font(.caption)
                                .foregroundColor(.white)
                        }

                        Image(systemName: "arrow.right")
                            .foregroundColor(.white.opacity(0.5))

                        VStack {
                            Image(systemName: isCoinAligned ? "checkmark.circle.fill" : "circle")
                                .foregroundColor(isCoinAligned ? .green : .white.opacity(0.5))
                            Text("Ausgerichtet")
                                .font(.caption)
                                .foregroundColor(.white)
                        }
                    }
                    .padding()
                    .background(
                        Capsule()
                            .fill(Color.black.opacity(0.7))
                    )
                    .padding(.bottom, 20)
                }

                // Action buttons
                VStack(spacing: 12) {
                    // Start scan (only when aligned)
                    if isCoinPlaced && isCoinAligned {
                        Button(action: startScanning) {
                            HStack {
                                Image(systemName: "viewfinder.circle.fill")
                                Text("Scannen starten")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(12)
                            .shadow(radius: 10)
                        }
                    }

                    // Reset placement
                    if isCoinPlaced {
                        Button(action: {
                            isCoinPlaced = false
                            isCoinAligned = false
                            coinPosition = nil
                        }) {
                            Text("Neu platzieren")
                                .foregroundColor(.white)
                                .padding()
                        }
                    }

                    // Back button
                    Button(action: { withAnimation { currentStep = .prepare } }) {
                        Text("Zurück")
                            .foregroundColor(.white.opacity(0.7))
                            .padding()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Step 4: Scanning

    private var scanningView: some View {
        ZStack {
            // AR Scanner (reuse existing)
            ARScannerView()
                .environmentObject(scanViewModel)
                .edgesIgnoringSafeArea(.all)

            // Overlay UI
            VStack {
                // Top progress
                VStack(spacing: 16) {
                    Image(systemName: currentStep.icon)
                        .font(.system(size: 40))
                        .foregroundColor(currentStep.color)

                    VStack(spacing: 8) {
                        Text("Münze scannen")
                            .font(.title3)
                            .fontWeight(.semibold)
                            .foregroundColor(.white)

                        if !scanViewModel.isObjectSelected {
                            Text("Tippen Sie auf die Münze")
                                .font(.caption)
                                .foregroundColor(.yellow)
                        } else {
                            HStack(spacing: 12) {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundColor(.green)
                                Text("\(scanViewModel.pointCount) Punkte")
                                    .foregroundColor(.white)
                                ProgressView(value: Double(min(scanViewModel.pointCount, 1000)) / 1000.0)
                                    .frame(width: 100)
                                    .tint(.green)
                            }
                            .font(.caption)
                        }
                    }
                    .multilineTextAlignment(.center)
                }
                .padding()
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(Color.black.opacity(0.7))
                        .shadow(radius: 10)
                )
                .padding(.top, 60)
                .padding(.horizontal)

                Spacer()

                // Scanning tips
                if scanViewModel.isObjectSelected {
                    VStack(alignment: .leading, spacing: 8) {
                        ScanTip(icon: "arrow.triangle.2.circlepath", text: "Bewegen Sie das iPhone langsam um die Münze")
                        ScanTip(icon: "eye.fill", text: "Erfassen Sie alle Seiten")
                        ScanTip(icon: "checkmark.circle", text: "Mindestens 500 Punkte sammeln")
                    }
                    .padding()
                    .background(
                        RoundedRectangle(cornerRadius: 12)
                            .fill(Color.black.opacity(0.7))
                    )
                    .padding(.horizontal)
                }

                // Action buttons
                VStack(spacing: 12) {
                    // Complete scan
                    if scanViewModel.isObjectSelected && scanViewModel.pointCount >= 500 {
                        Button(action: completeScan) {
                            HStack {
                                Image(systemName: "checkmark.circle.fill")
                                Text("Scan abschließen")
                                    .fontWeight(.semibold)
                            }
                            .foregroundColor(.black)
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.green)
                            .cornerRadius(12)
                            .shadow(radius: 10)
                        }
                    }

                    // Cancel
                    Button(action: {
                        scanViewModel.reset()
                        withAnimation { currentStep = .placeVirtualCoin }
                    }) {
                        Text("Abbrechen")
                            .foregroundColor(.white.opacity(0.7))
                            .padding()
                    }
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Step 5: Processing

    private var processingView: some View {
        VStack(spacing: 32) {
            Spacer()

            // Animated icon
            ZStack {
                Circle()
                    .stroke(currentStep.color.opacity(0.3), lineWidth: 8)
                    .frame(width: 120, height: 120)

                Circle()
                    .trim(from: 0, to: 0.7)
                    .stroke(currentStep.color, lineWidth: 8)
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.linear(duration: 1).repeatForever(autoreverses: false), value: UUID())

                Image(systemName: currentStep.icon)
                    .font(.system(size: 50))
                    .foregroundColor(currentStep.color)
            }

            VStack(spacing: 12) {
                Text("Verarbeitung läuft...")
                    .font(.title2)
                    .fontWeight(.semibold)
                    .foregroundColor(.white)

                Text("Die Münze wird analysiert und\nder Kalibrierfaktor berechnet")
                    .font(.subheadline)
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }

            Spacer()
        }
    }

    // MARK: - Step 6: Completed

    private var completedView: some View {
        ScrollView {
            VStack(spacing: 32) {
                Spacer(minLength: 40)

                // Success icon
                Image(systemName: currentStep.icon)
                    .font(.system(size: 80))
                    .foregroundColor(currentStep.color)

                // Title
                VStack(spacing: 12) {
                    Text("Kalibrierung erfolgreich!")
                        .font(.largeTitle)
                        .fontWeight(.bold)
                        .foregroundColor(.white)

                    Text("Ihre Messungen sind jetzt präziser")
                        .font(.subheadline)
                        .foregroundColor(.white.opacity(0.8))
                }

                // Results
                VStack(spacing: 16) {
                    ResultRow(
                        icon: "target",
                        label: "Genauigkeit",
                        value: String(format: "%.1f%%", calibrationManager.calibrationAccuracy),
                        color: accuracyColor
                    )

                    if let factor = calibrationManager.calibrationFactor {
                        ResultRow(
                            icon: "slider.horizontal.3",
                            label: "Kalibrierfaktor",
                            value: String(format: "%.4f", factor),
                            color: .blue
                        )
                    }

                    ResultRow(
                        icon: "calendar",
                        label: "Gültig bis",
                        value: validUntilDate,
                        color: .purple
                    )
                }
                .padding()
                .background(Color.white.opacity(0.1))
                .cornerRadius(16)
                .padding(.horizontal)

                // Tips
                VStack(alignment: .leading, spacing: 12) {
                    Text("💡 Tipps:")
                        .font(.headline)
                        .foregroundColor(.white)

                    Text("• Kalibrierung gilt für 30 Tage")
                    Text("• Bei ungenauen Messungen neu kalibrieren")
                    Text("• Funktioniert für alle Materialien")
                }
                .font(.caption)
                .foregroundColor(.white.opacity(0.8))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
                .background(Color.white.opacity(0.05))
                .cornerRadius(12)
                .padding(.horizontal)

                Spacer()

                // Done button
                Button(action: { dismiss() }) {
                    HStack {
                        Image(systemName: "checkmark")
                        Text("Fertig")
                            .fontWeight(.semibold)
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .padding()
                    .background(currentStep.color)
                    .cornerRadius(12)
                }
                .padding(.horizontal, 32)
                .padding(.bottom, 32)
            }
        }
    }

    // MARK: - Helper Methods

    private func startScanning() {
        withAnimation {
            currentStep = .scanning
        }
        scanViewModel.startScanning()
    }

    private func completeScan() {
        withAnimation {
            currentStep = .processing
        }
        scanViewModel.completeScan()

        // Wait for processing
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
            processCalibrationResults()
        }
    }

    private func processCalibrationResults() {
        let volume = scanViewModel.volumeML
        let dimensions = scanViewModel.dimensions

        let result = calibrationManager.calibrateWithVolume(
            with: .euroCoin1,
            scannedVolume: volume,
            scannedDimensions: dimensions
        )

        if result.success {
            withAnimation {
                currentStep = .completed
            }
            showingSuccess = true
        } else {
            errorMessage = result.message + "\n\nTipps:\n• Scannen Sie bei gutem Licht\n• Erfassen Sie die Münze vollständig\n• Halten Sie 20-30cm Abstand"
            showingError = true
        }

        scanViewModel.reset()
    }

    private var accuracyColor: Color {
        let accuracy = calibrationManager.calibrationAccuracy
        if accuracy >= 90 { return .green }
        if accuracy >= 75 { return .yellow }
        return .orange
    }

    private var validUntilDate: String {
        guard let lastDate = calibrationManager.lastCalibrationDate else {
            return "Unbekannt"
        }
        let validUntil = Calendar.current.date(byAdding: .day, value: 30, to: lastDate) ?? lastDate
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        return formatter.string(from: validUntil)
    }

    // MARK: - Camera Angle Helpers (Vogelperspektive Guidance)

    private var cameraAngleIcon: String {
        if cameraAngle < 30 { return "arrow.down.circle.fill" }
        if cameraAngle < 60 { return "arrow.down.forward.circle.fill" }
        return "arrow.forward.circle.fill"
    }

    private var cameraAngleColor: Color {
        if cameraAngle < 30 { return .green }
        if cameraAngle < 60 { return .orange }
        return .red
    }

    private var cameraAngleText: String {
        if cameraAngle < 30 { return "Perfekte Vogelperspektive!" }
        if cameraAngle < 60 { return "Etwas steiler schauen" }
        return "Von oben schauen"
    }

    private var cameraAngleBackgroundColor: Color {
        if cameraAngle < 30 { return Color.green.opacity(0.3) }
        if cameraAngle < 60 { return Color.orange.opacity(0.3) }
        return Color.red.opacity(0.3)
    }
}

// MARK: - Supporting Views

struct FeatureRow: View {
    let icon: String
    let title: String
    let description: String

    var body: some View {
        HStack(spacing: 16) {
            Image(systemName: icon)
                .font(.title2)
                .foregroundColor(.yellow)
                .frame(width: 40)

            VStack(alignment: .leading, spacing: 4) {
                Text(title)
                    .font(.headline)
                    .foregroundColor(.white)
                Text(description)
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }

            Spacer()
        }
    }
}

struct StepInstruction: View {
    let number: String
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Text(number)
                .font(.headline)
                .fontWeight(.bold)
                .foregroundColor(.black)
                .frame(width: 28, height: 28)
                .background(Circle().fill(Color.yellow))

            Text(text)
                .font(.subheadline)
                .foregroundColor(.white)

            Spacer()
        }
    }
}

struct SpecBadge: View {
    let icon: String
    let value: String

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: icon)
                .font(.caption)
            Text(value)
                .font(.caption)
                .fontWeight(.semibold)
        }
        .foregroundColor(.white)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(Color.white.opacity(0.2))
        .cornerRadius(8)
    }
}

struct ScanTip: View {
    let icon: String
    let text: String

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: icon)
                .foregroundColor(.cyan)
                .font(.caption)
            Text(text)
                .font(.caption)
                .foregroundColor(.white)
        }
    }
}

struct ResultRow: View {
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
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            Text(value)
                .font(.headline)
                .foregroundColor(color)
        }
    }
}

// MARK: - Preview

#Preview {
    ImprovedCalibrationView()
}
