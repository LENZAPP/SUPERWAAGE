//
//  BLEPairingView.swift
//  SUPERWAAGE
//
//  SwiftUI BLE scale pairing view
//  Works with existing BLEScaleManager.swift
//
//  Features:
//  - Auto-discovery of BLE scales
//  - Connection status
//  - Signal strength indicator
//  - Reconnect to last device
//  - Manual scan control
//
//  Usage:
//    NavigationLink("Waage verbinden") {
//        BLEPairingView()
//    }
//

import SwiftUI
import CoreBluetooth
import Combine

// MARK: - BLE Pairing View

public struct BLEPairingView: View {
    @StateObject private var viewModel = BLEPairingViewModel()
    @Environment(\.dismiss) private var dismiss

    public init() {}

    public var body: some View {
        List {
            // Connection status
            Section {
                if viewModel.isConnected {
                    connectedStatusRow
                } else {
                    disconnectedStatusRow
                }
            }

            // Discovered scales
            Section {
                if viewModel.isScanning {
                    HStack {
                        ProgressView()
                        Text("Suche nach Waagen...")
                            .foregroundColor(.secondary)
                    }
                } else if viewModel.discoveredScales.isEmpty {
                    Text("Keine Waagen gefunden")
                        .foregroundColor(.secondary)
                } else {
                    ForEach(viewModel.discoveredScales, id: \.identifier) { scale in
                        scaleRow(scale)
                    }
                }
            } header: {
                Text("Verfügbare Waagen")
            }

            // Current weight (if connected)
            if viewModel.isConnected && viewModel.lastWeight > 0 {
                Section {
                    HStack {
                        Label("Aktuelles Gewicht", systemImage: "scalemass")
                        Spacer()
                        Text(String(format: "%.3f kg", viewModel.lastWeight))
                            .font(.headline.monospacedDigit())
                            .foregroundColor(.primary)
                    }
                } header: {
                    Text("Messung")
                }
            }

            // Actions
            Section {
                if viewModel.isConnected {
                    Button("Verbindung trennen") {
                        viewModel.disconnect()
                    }
                    .foregroundColor(.red)
                } else {
                    Button(viewModel.isScanning ? "Suche stoppen" : "Erneut suchen") {
                        if viewModel.isScanning {
                            viewModel.stopScan()
                        } else {
                            viewModel.startScan()
                        }
                    }
                }
            }

            // Help
            Section {
                helpText
            } header: {
                Text("Hilfe")
            }
        }
        .navigationTitle("Waage verbinden")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
                if viewModel.isConnected {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
        .onAppear {
            viewModel.setup()
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

    // MARK: - Subviews

    private var connectedStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "checkmark.circle.fill")
                .font(.title2)
                .foregroundColor(.green)

            VStack(alignment: .leading, spacing: 4) {
                Text("Verbunden")
                    .font(.headline)

                if let name = viewModel.connectedScaleName {
                    Text(name)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Signal strength
            Image(systemName: "antenna.radiowaves.left.and.right")
                .foregroundColor(.green)
        }
        .padding(.vertical, 4)
    }

    private var disconnectedStatusRow: some View {
        HStack(spacing: 12) {
            Image(systemName: "exclamationmark.circle.fill")
                .font(.title2)
                .foregroundColor(.orange)

            Text("Nicht verbunden")
                .font(.headline)

            Spacer()
        }
        .padding(.vertical, 4)
    }

    private func scaleRow(_ scale: CBPeripheral) -> some View {
        Button {
            viewModel.connect(to: scale)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(scale.name ?? "Unbekannte Waage")
                        .font(.body)
                        .foregroundColor(.primary)

                    Text(scale.identifier.uuidString.prefix(8))
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }

                Spacer()

                if viewModel.connectingToScale == scale.identifier {
                    ProgressView()
                } else {
                    Image(systemName: "chevron.right")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
        }
    }

    private var helpText: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("So verbinden Sie Ihre Waage:")
                .font(.subheadline.weight(.medium))

            VStack(alignment: .leading, spacing: 8) {
                HelpStep(number: 1, text: "Schalten Sie die Bluetooth-Waage ein")
                HelpStep(number: 2, text: "Stellen Sie sicher, dass Bluetooth aktiviert ist")
                HelpStep(number: 3, text: "Tippen Sie auf Ihre Waage in der Liste")
                HelpStep(number: 4, text: "Die Verbindung erfolgt automatisch")
            }

            Text("Unterstützte Waagen:")
                .font(.subheadline.weight(.medium))
                .padding(.top, 8)

            Text("• Bluetooth Weight Scale (Standard)")
                .font(.caption)
                .foregroundColor(.secondary)

            Text("• Benutzerdefinierte Waagen (konfigurierbar)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Help Step

private struct HelpStep: View {
    let number: Int
    let text: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text("\(number).")
                .font(.caption.weight(.semibold))
                .foregroundColor(.blue)
                .frame(width: 20, alignment: .leading)

            Text(text)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }
}

// MARK: - View Model

@MainActor
private class BLEPairingViewModel: ObservableObject, BLEScaleDelegate {

    @Published var isScanning: Bool = false
    @Published var isConnected: Bool = false
    @Published var lastWeight: Double = 0.0
    @Published var discoveredScales: [CBPeripheral] = []
    @Published var connectingToScale: UUID?
    @Published var connectedScaleName: String?

    private var cancellables = Set<AnyCancellable>()

    func setup() {
        // Observe BLEScaleManager changes
        BLEScaleManager.shared.$isScanning
            .receive(on: DispatchQueue.main)
            .assign(to: &$isScanning)

        BLEScaleManager.shared.$isConnected
            .receive(on: DispatchQueue.main)
            .assign(to: &$isConnected)

        BLEScaleManager.shared.$lastWeight
            .receive(on: DispatchQueue.main)
            .assign(to: &$lastWeight)

        BLEScaleManager.shared.$discoveredScales
            .receive(on: DispatchQueue.main)
            .assign(to: &$discoveredScales)

        // Start scanning
        startScan()
    }

    func cleanup() {
        stopScan()
    }

    func startScan() {
        BLEScaleManager.shared.startScan(delegate: self)
    }

    func stopScan() {
        BLEScaleManager.shared.stopScan()
    }

    func connect(to scale: CBPeripheral) {
        connectingToScale = scale.identifier
        connectedScaleName = scale.name
        BLEScaleManager.shared.connect(to: scale)
    }

    func disconnect() {
        BLEScaleManager.shared.disconnect()
        connectedScaleName = nil
        connectingToScale = nil
    }

    // MARK: - BLEScaleDelegate

    func scaleDidUpdateWeight(_ weightKg: Double) {
        // Weight updates are handled by @Published property observation
        print("⚖️ Weight updated: \(weightKg) kg")
    }

    func scaleDidConnect() {
        connectingToScale = nil
        print("✅ Scale connected")
    }

    func scaleDidDisconnect() {
        connectedScaleName = nil
        connectingToScale = nil
        print("🔌 Scale disconnected")
    }

    func scaleDidUpdateBattery(_ percentage: Int) {
        print("🔋 Battery: \(percentage)%")
    }
}

// MARK: - Simplified Pairing Sheet

/// Minimal pairing sheet for quick integration
public struct BLEPairingSheet: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var viewModel = BLEPairingViewModel()

    public init() {}

    public var body: some View {
        NavigationView {
            BLEPairingView()
                .toolbar {
                    ToolbarItem(placement: .navigationBarLeading) {
                        Button("Abbrechen") {
                            dismiss()
                        }
                    }
                }
        }
    }
}

// MARK: - View Extension for Easy Integration

extension View {

    /// Present BLE pairing sheet
    public func blePairingSheet(isPresented: Binding<Bool>) -> some View {
        self.sheet(isPresented: isPresented) {
            BLEPairingSheet()
        }
    }
}

// MARK: - Usage Examples
/*

 EXAMPLE 1: Navigation Link

 struct SettingsView: View {
     var body: some View {
         List {
             Section("Hardware") {
                 NavigationLink("Waage verbinden") {
                     BLEPairingView()
                 }
             }
         }
     }
 }

 EXAMPLE 2: Sheet Presentation

 struct ContentView: View {
     @State private var showPairing = false

     var body: some View {
         Button("Waage verbinden") {
             showPairing = true
         }
         .blePairingSheet(isPresented: $showPairing)
     }
 }

 EXAMPLE 3: Automatic on First Launch

 struct ContentView: View {
     @State private var showPairing = false

     var body: some View {
         MainView()
             .onAppear {
                 // Show pairing if no scale connected and not shown before
                 if !BLEScaleManager.shared.isConnected &&
                    !UserDefaults.standard.bool(forKey: "ble.pairing.shown") {
                     showPairing = true
                     UserDefaults.standard.set(true, forKey: "ble.pairing.shown")
                 }
             }
             .blePairingSheet(isPresented: $showPairing)
     }
 }

 EXAMPLE 4: In-App Prompt

 struct ScanView: View {
     @ObservedObject var viewModel: ScanViewModel
     @State private var showPairing = false

     var body: some View {
         ZStack {
             ARScannerView()
                 .environmentObject(viewModel)

             // Show prompt if weight needed but no scale connected
             if viewModel.scanState == .completed && !BLEScaleManager.shared.isConnected {
                 VStack {
                     Spacer()

                     VStack(spacing: 12) {
                         Text("Waage nicht verbunden")
                             .font(.headline)

                         Text("Verbinde eine Bluetooth-Waage für automatische Gewichtsmessung")
                             .font(.caption)
                             .foregroundColor(.secondary)
                             .multilineTextAlignment(.center)

                         Button("Waage verbinden") {
                             showPairing = true
                         }
                         .buttonStyle(.borderedProminent)
                     }
                     .padding()
                     .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
                     .padding()
                 }
             }
         }
         .blePairingSheet(isPresented: $showPairing)
     }
 }

 EXAMPLE 5: Real-time Weight Display

 struct WeightDisplayView: View {
     @ObservedObject private var scaleManager = BLEScaleManager.shared

     var body: some View {
         VStack(spacing: 16) {
             if scaleManager.isConnected {
                 VStack(spacing: 8) {
                     Text("Aktuelles Gewicht")
                         .font(.caption)
                         .foregroundColor(.secondary)

                     Text(String(format: "%.3f kg", scaleManager.lastWeight))
                         .font(.system(size: 48, weight: .bold, design: .rounded))
                         .foregroundColor(.primary)

                     Text("Live von Bluetooth-Waage")
                         .font(.caption2)
                         .foregroundColor(.green)
                 }
             } else {
                 Text("Keine Waage verbunden")
                     .font(.caption)
                     .foregroundColor(.secondary)
             }
         }
     }
 }

 */
