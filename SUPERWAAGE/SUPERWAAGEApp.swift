//
//  SUPERWAAGEApp.swift
//  SUPERWAAGE
//
//  Created by Claude Code
//  Die ultimative AR-LiDAR Küchenwaage mit KI-Unterstützung
//

import SwiftUI

@main
struct SUPERWAAGEApp: App {
    @StateObject private var scanViewModel = ScanViewModel()
    @StateObject private var calibrationManager = CalibrationManager.shared

    @State private var showOnboarding = !UserDefaults.standard.bool(
        forKey: "com.superwaage.onboarding.completed"
    )
    @State private var showQuickCalibrationPrompt = false

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(scanViewModel)
                .overlay(
                    OnboardingCoachView(
                        isPresented: $showOnboarding,
                        steps: scanningSteps,
                        onComplete: {
                            UserDefaults.standard.set(
                                true,
                                forKey: "com.superwaage.onboarding.completed"
                            )
                            // After onboarding, show calibration prompt if not calibrated
                            if !calibrationManager.isCalibrated {
                                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                    showQuickCalibrationPrompt = true
                                }
                            }
                        }
                    )
                )
                .fullScreenCover(isPresented: $showQuickCalibrationPrompt) {
                    QuickCalibrationFlow()
                }
                .onAppear {
                    // Check if we should show calibration prompt on first launch
                    if !showOnboarding && !calibrationManager.isCalibrated {
                        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                            showQuickCalibrationPrompt = true
                        }
                    }
                }
        }
    }

    // ✨ Define onboarding steps
    private var scanningSteps: [OnboardingStep] {
        [
            OnboardingStep(
                title: "Willkommen bei SUPERWAAGE",
                message: "Scannen Sie Objekte in 3D mit Ihrem iPhone LiDAR-Scanner",
                systemImage: "arkit"
            ),
            OnboardingStep(
                title: "Objekt antippen",
                message: "Tippen Sie auf das Objekt, das Sie scannen möchten",
                systemImage: "hand.tap",
                highlightArea: .center
            ),
            OnboardingStep(
                title: "Langsam bewegen",
                message: "Bewegen Sie die Kamera langsam um das Objekt herum (360°)",
                systemImage: "arrow.triangle.2.circlepath.camera"
            ),
            OnboardingStep(
                title: "Qualität beachten",
                message: "Folgen Sie den Empfehlungen im Display für beste Ergebnisse",
                systemImage: "star.fill"
            ),
            OnboardingStep(
                title: "Los geht's!",
                message: "Viel Erfolg beim Scannen! Tippen Sie auf 'Fertig' wenn komplett.",
                systemImage: "checkmark.circle.fill"
            )
        ]
    }
}
