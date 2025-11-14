//
//  PermissionManager.swift
//  SUPERWAAGE
//
//  Manages camera and other privacy permissions for AR scanning
//

import Foundation
import AVFoundation
import SwiftUI
import Combine

/// Manages app permissions (camera, etc.)
@MainActor
class PermissionManager: ObservableObject {
    static let shared = PermissionManager()

    @Published var cameraPermissionGranted: Bool = false
    @Published var showingPermissionAlert: Bool = false

    private init() {
        // Check initial status
        checkCameraPermission()
    }

    // MARK: - Camera Permission

    /// Check current camera permission status (synchronous)
    func checkCameraPermission() {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            cameraPermissionGranted = true
            print("✅ Camera permission: Authorized")

        case .notDetermined:
            cameraPermissionGranted = false
            print("⚠️ Camera permission: Not determined (will request)")

        case .denied:
            cameraPermissionGranted = false
            print("❌ Camera permission: Denied")

        case .restricted:
            cameraPermissionGranted = false
            print("❌ Camera permission: Restricted")

        @unknown default:
            cameraPermissionGranted = false
            print("⚠️ Camera permission: Unknown status")
        }
    }

    /// Request camera permission (async)
    func requestCameraPermission() async -> Bool {
        let status = AVCaptureDevice.authorizationStatus(for: .video)

        switch status {
        case .authorized:
            print("✅ Camera permission already granted")
            cameraPermissionGranted = true
            return true

        case .notDetermined:
            print("📷 Requesting camera permission...")
            let granted = await AVCaptureDevice.requestAccess(for: .video)

            cameraPermissionGranted = granted

            if granted {
                print("✅ Camera permission granted by user")
            } else {
                print("❌ Camera permission denied by user")
                showingPermissionAlert = true
            }

            return granted

        case .denied, .restricted:
            print("❌ Camera permission denied or restricted")
            cameraPermissionGranted = false
            showingPermissionAlert = true
            return false

        @unknown default:
            print("⚠️ Unknown camera permission status")
            cameraPermissionGranted = false
            return false
        }
    }

    /// Open app settings (for when permission is denied)
    func openAppSettings() {
        guard let settingsURL = URL(string: UIApplication.openSettingsURLString) else {
            print("❌ Could not create settings URL")
            return
        }

        if UIApplication.shared.canOpenURL(settingsURL) {
            UIApplication.shared.open(settingsURL) { success in
                if success {
                    print("✅ Opened app settings")
                } else {
                    print("❌ Failed to open app settings")
                }
            }
        }
    }

    // MARK: - Permission Alert View

    /// SwiftUI alert for permission denied
    var permissionAlert: Alert {
        Alert(
            title: Text("Kamerazugriff erforderlich"),
            message: Text("SUPERWAAGE benötigt Kamerazugriff für AR-Scanning. Bitte aktivieren Sie die Kamera in den Einstellungen."),
            primaryButton: .default(Text("Einstellungen öffnen")) {
                self.openAppSettings()
            },
            secondaryButton: .cancel(Text("Abbrechen"))
        )
    }
}
