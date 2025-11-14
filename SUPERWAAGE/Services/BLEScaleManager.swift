//
// BLEScaleManager.swift
// SUPERWAAGE
//
// Bluetooth LE manager for kitchen scale connectivity
// Discovers, connects, and reads weight measurements from BLE-enabled scales
//
// Supported Scales:
//   - Standard Weight Scale Service (0x181D)
//   - Custom scale profiles (configurable UUIDs)
//
// Usage:
//   BLEScaleManager.shared.startScan(delegate: self)
//   // Implement BLEScaleDelegate to receive weight updates
//
// Requirements:
//   - Add to Info.plist:
//     * NSBluetoothAlwaysUsageDescription
//     * NSBluetoothPeripheralUsageDescription
//

import Foundation
import CoreBluetooth
import Combine

// MARK: - Delegate Protocol

public protocol BLEScaleDelegate: AnyObject {
    /// Called when scale updates weight measurement
    /// - Parameter weightKg: Weight in kilograms
    func scaleDidUpdateWeight(_ weightKg: Double)

    /// Called when scale successfully connects
    func scaleDidConnect()

    /// Called when scale disconnects
    func scaleDidDisconnect()

    /// Called when scale battery level updates (optional)
    func scaleDidUpdateBattery(_ percentage: Int)
}

// Make battery update optional
public extension BLEScaleDelegate {
    func scaleDidUpdateBattery(_ percentage: Int) {}
}

// MARK: - BLE Scale Manager

@MainActor
public final class BLEScaleManager: NSObject {

    public static let shared = BLEScaleManager()

    // MARK: - Properties

    private var centralManager: CBCentralManager!
    private var connectedPeripheral: CBPeripheral?
    private weak var delegate: BLEScaleDelegate?

    // Connection state
    @Published public private(set) var isScanning: Bool = false
    @Published public private(set) var isConnected: Bool = false
    @Published public private(set) var lastWeight: Double = 0.0
    @Published public private(set) var discoveredScales: [CBPeripheral] = []

    // MARK: - Service & Characteristic UUIDs

    /// Standard Bluetooth SIG Weight Scale Service
    /// https://www.bluetooth.com/specifications/gatt/services/
    public var scaleServiceUUID = CBUUID(string: "181D") // Weight Scale Service

    /// Standard Weight Measurement Characteristic
    public var weightCharacteristicUUID = CBUUID(string: "2A9D") // Weight Measurement

    /// Battery Service (optional)
    public var batteryServiceUUID = CBUUID(string: "180F") // Battery Service
    public var batteryLevelUUID = CBUUID(string: "2A19") // Battery Level

    // MARK: - Custom Scale Support

    /// Configure custom scale UUIDs (for non-standard scales)
    public func configureCustomScale(serviceUUID: String, weightCharUUID: String) {
        self.scaleServiceUUID = CBUUID(string: serviceUUID)
        self.weightCharacteristicUUID = CBUUID(string: weightCharUUID)
        print("📡 BLEScaleManager: Configured custom scale - Service: \(serviceUUID), Char: \(weightCharUUID)")
    }

    // MARK: - Initialization

    private override init() {
        super.init()
        centralManager = CBCentralManager(delegate: self, queue: .main)
    }

    // MARK: - Public API

    /// Start scanning for BLE scales
    /// - Parameter delegate: Delegate to receive scale events
    public func startScan(delegate: BLEScaleDelegate) {
        self.delegate = delegate

        guard centralManager.state == .poweredOn else {
            print("⚠️ BLEScaleManager: Bluetooth not ready")
            return
        }

        discoveredScales.removeAll()
        isScanning = true

        // Scan for weight scale service
        centralManager.scanForPeripherals(
            withServices: [scaleServiceUUID],
            options: [CBCentralManagerScanOptionAllowDuplicatesKey: false]
        )

        print("🔍 BLEScaleManager: Scanning for scales...")
    }

    /// Stop scanning
    public func stopScan() {
        centralManager.stopScan()
        isScanning = false
        print("⏹️ BLEScaleManager: Stopped scanning")
    }

    /// Connect to a specific scale
    /// - Parameter peripheral: Scale peripheral to connect
    public func connect(to peripheral: CBPeripheral) {
        guard centralManager.state == .poweredOn else { return }

        // Disconnect existing connection
        if let existing = connectedPeripheral {
            centralManager.cancelPeripheralConnection(existing)
        }

        connectedPeripheral = peripheral
        peripheral.delegate = self
        centralManager.connect(peripheral, options: nil)

        print("🔗 BLEScaleManager: Connecting to \(peripheral.name ?? "Unknown Scale")...")
    }

    /// Disconnect from current scale
    public func disconnect() {
        guard let peripheral = connectedPeripheral else { return }
        centralManager.cancelPeripheralConnection(peripheral)
        print("🔌 BLEScaleManager: Disconnecting...")
    }

    /// Request weight reading (if scale supports on-demand reading)
    public func requestWeight() {
        guard let peripheral = connectedPeripheral else { return }

        // Find weight characteristic and read
        if let services = peripheral.services {
            for service in services where service.uuid == scaleServiceUUID {
                if let characteristics = service.characteristics {
                    for char in characteristics where char.uuid == weightCharacteristicUUID {
                        peripheral.readValue(for: char)
                    }
                }
            }
        }
    }

    // MARK: - Weight Parsing

    /// Parse weight from characteristic data
    /// Supports multiple weight scale data formats
    private func parseWeight(from data: Data) -> Double? {
        guard data.count >= 2 else { return nil }

        // Try standard IEEE-11073 FLOAT format (most common)
        // Format: Flags (1 byte) + Weight (SFLOAT - 2 bytes) + [optional fields]
        if data.count >= 3 {
            let flags = data[0]
            let weightBytes = data.subdata(in: 1..<3)

            // Check unit (bit 0 of flags: 0=SI (kg), 1=Imperial (lb))
            let isMetric = (flags & 0x01) == 0

            // Parse SFLOAT (short float, IEEE-11073)
            let rawValue = weightBytes.withUnsafeBytes { $0.load(as: UInt16.self) }
            let mantissa = Int16(rawValue & 0x0FFF)
            let exponent = Int8(rawValue >> 12)

            var weight = Double(mantissa) * pow(10.0, Double(exponent))

            // Convert to kg if needed
            if !isMetric {
                weight = weight * 0.453592 // lb to kg
            }

            return weight
        }

        // Fallback: try simple 16-bit value (some scales use value/200 or value/100)
        if data.count == 2 {
            let raw = data.withUnsafeBytes { $0.load(as: UInt16.self) }
            // Common convention: value / 200 = kg
            return Double(raw) / 200.0
        }

        return nil
    }
}

// MARK: - CBCentralManagerDelegate

extension BLEScaleManager: CBCentralManagerDelegate {

    public func centralManagerDidUpdateState(_ central: CBCentralManager) {
        switch central.state {
        case .poweredOn:
            print("✅ BLEScaleManager: Bluetooth powered on")
        case .poweredOff:
            print("❌ BLEScaleManager: Bluetooth powered off")
        case .unauthorized:
            print("⚠️ BLEScaleManager: Bluetooth unauthorized")
        case .unsupported:
            print("❌ BLEScaleManager: Bluetooth not supported")
        default:
            break
        }
    }

    public func centralManager(_ central: CBCentralManager,
                              didDiscover peripheral: CBPeripheral,
                              advertisementData: [String : Any],
                              rssi RSSI: NSNumber) {

        // Add to discovered list
        if !discoveredScales.contains(where: { $0.identifier == peripheral.identifier }) {
            discoveredScales.append(peripheral)
            print("📡 BLEScaleManager: Found scale - \(peripheral.name ?? "Unknown") (RSSI: \(RSSI))")
        }

        // Auto-connect to first discovered scale (for convenience)
        // In production, show list to user
        if connectedPeripheral == nil && !isConnected {
            connect(to: peripheral)
        }
    }

    public func centralManager(_ central: CBCentralManager,
                              didConnect peripheral: CBPeripheral) {
        isConnected = true
        stopScan()
        delegate?.scaleDidConnect()

        print("✅ BLEScaleManager: Connected to \(peripheral.name ?? "Scale")")

        // Discover services
        peripheral.discoverServices([scaleServiceUUID, batteryServiceUUID])
    }

    public func centralManager(_ central: CBCentralManager,
                              didDisconnectPeripheral peripheral: CBPeripheral,
                              error: Error?) {
        isConnected = false
        connectedPeripheral = nil
        delegate?.scaleDidDisconnect()

        if let error = error {
            print("❌ BLEScaleManager: Disconnected with error: \(error.localizedDescription)")
        } else {
            print("🔌 BLEScaleManager: Disconnected")
        }
    }

    public func centralManager(_ central: CBCentralManager,
                              didFailToConnect peripheral: CBPeripheral,
                              error: Error?) {
        print("❌ BLEScaleManager: Failed to connect: \(error?.localizedDescription ?? "Unknown error")")
        isConnected = false
        connectedPeripheral = nil
    }
}

// MARK: - CBPeripheralDelegate

extension BLEScaleManager: CBPeripheralDelegate {

    public func peripheral(_ peripheral: CBPeripheral,
                          didDiscoverServices error: Error?) {
        guard let services = peripheral.services else { return }

        for service in services {
            if service.uuid == scaleServiceUUID {
                // Discover weight characteristic
                peripheral.discoverCharacteristics([weightCharacteristicUUID], for: service)
            } else if service.uuid == batteryServiceUUID {
                // Discover battery characteristic
                peripheral.discoverCharacteristics([batteryLevelUUID], for: service)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                          didDiscoverCharacteristicsFor service: CBService,
                          error: Error?) {
        guard let characteristics = service.characteristics else { return }

        for characteristic in characteristics {
            if characteristic.uuid == weightCharacteristicUUID {
                // Enable notifications for continuous weight updates
                peripheral.setNotifyValue(true, for: characteristic)

                // Also read once
                peripheral.readValue(for: characteristic)

                print("✅ BLEScaleManager: Subscribed to weight updates")
            } else if characteristic.uuid == batteryLevelUUID {
                // Read battery level
                peripheral.readValue(for: characteristic)
            }
        }
    }

    public func peripheral(_ peripheral: CBPeripheral,
                          didUpdateValueFor characteristic: CBCharacteristic,
                          error: Error?) {

        if let error = error {
            print("⚠️ BLEScaleManager: Read error: \(error.localizedDescription)")
            return
        }

        guard let data = characteristic.value else { return }

        if characteristic.uuid == weightCharacteristicUUID {
            // Parse weight
            if let weight = parseWeight(from: data) {
                lastWeight = weight
                delegate?.scaleDidUpdateWeight(weight)
                print("⚖️ BLEScaleManager: Weight = \(String(format: "%.3f", weight)) kg")
            }
        } else if characteristic.uuid == batteryLevelUUID {
            // Parse battery level (0-100%)
            if let battery = data.first {
                delegate?.scaleDidUpdateBattery(Int(battery))
                print("🔋 BLEScaleManager: Battery = \(battery)%")
            }
        }
    }
}
