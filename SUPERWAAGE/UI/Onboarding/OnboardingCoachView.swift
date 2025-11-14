//
//  OnboardingCoachView.swift
//  SUPERWAAGE
//
//  SwiftUI-native onboarding coach for first-time users
//
//  Features:
//  - Step-by-step guidance with highlights
//  - Skip functionality
//  - Persistent state (UserDefaults)
//  - Replay option
//  - Customizable steps
//
//  Usage:
//    .overlay(OnboardingCoachView(isPresented: $showOnboarding))
//

import SwiftUI
import Combine

// MARK: - Onboarding Step Model

public struct OnboardingStep: Identifiable {
    public let id = UUID()
    public let title: String
    public let message: String
    public let systemImage: String
    public let highlightArea: HighlightArea?

    public init(title: String, message: String, systemImage: String = "hand.tap", highlightArea: HighlightArea? = nil) {
        self.title = title
        self.message = message
        self.systemImage = systemImage
        self.highlightArea = highlightArea
    }

    public enum HighlightArea {
        case topLeft
        case topRight
        case bottomLeft
        case bottomRight
        case center
        case top
        case bottom
    }
}

// MARK: - Onboarding Coach View

public struct OnboardingCoachView: View {
    @Binding var isPresented: Bool
    let steps: [OnboardingStep]
    let storageKey: String
    let onComplete: (() -> Void)?

    @State private var currentStep: Int = 0
    @State private var showSkipAlert = false

    public init(
        isPresented: Binding<Bool>,
        steps: [OnboardingStep],
        storageKey: String = "com.superwaage.onboarding.completed",
        onComplete: (() -> Void)? = nil
    ) {
        self._isPresented = isPresented
        self.steps = steps
        self.storageKey = storageKey
        self.onComplete = onComplete
    }

    public var body: some View {
        if isPresented && currentStep < steps.count {
            ZStack {
                // Dimmed background
                Color.black.opacity(0.6)
                    .ignoresSafeArea()
                    .onTapGesture {
                        nextStep()
                    }

                // Highlight area (if specified)
                if let highlightArea = steps[currentStep].highlightArea {
                    highlightView(for: highlightArea)
                }

                // Instruction card
                VStack {
                    instructionCard

                    Spacer()

                    // Navigation controls
                    navigationControls
                }
                .padding()
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: currentStep)
        }
    }

    // MARK: - Instruction Card

    private var instructionCard: some View {
        VStack(spacing: 16) {
            // Step indicator
            HStack {
                ForEach(0..<steps.count, id: \.self) { index in
                    Circle()
                        .fill(index == currentStep ? Color.blue : Color.gray.opacity(0.3))
                        .frame(width: 8, height: 8)
                }
            }
            .padding(.top, 8)

            // Icon
            Image(systemName: steps[currentStep].systemImage)
                .font(.system(size: 50))
                .foregroundColor(.blue)

            // Title
            Text(steps[currentStep].title)
                .font(.title2.weight(.bold))
                .multilineTextAlignment(.center)

            // Message
            Text(steps[currentStep].message)
                .font(.body)
                .multilineTextAlignment(.center)
                .foregroundColor(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            // Progress
            Text("Schritt \(currentStep + 1) von \(steps.count)")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(24)
        .background(.ultraThickMaterial, in: RoundedRectangle(cornerRadius: 20))
        .shadow(color: .black.opacity(0.2), radius: 15, y: 10)
        .padding(.top, 60)
    }

    // MARK: - Navigation Controls

    private var navigationControls: some View {
        HStack(spacing: 16) {
            // Skip button
            Button {
                showSkipAlert = true
            } label: {
                Text("Überspringen")
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.white.opacity(0.8))
                    .padding(.horizontal, 20)
                    .padding(.vertical, 12)
                    .background(.ultraThinMaterial, in: Capsule())
            }
            .alert("Einführung überspringen?", isPresented: $showSkipAlert) {
                Button("Abbrechen", role: .cancel) {}
                Button("Überspringen", role: .destructive) {
                    completeOnboarding()
                }
            } message: {
                Text("Du kannst die Einführung später in den Einstellungen erneut anzeigen.")
            }

            Spacer()

            // Next button
            Button {
                nextStep()
            } label: {
                HStack(spacing: 8) {
                    Text(currentStep == steps.count - 1 ? "Fertig" : "Weiter")
                        .font(.subheadline.weight(.semibold))

                    Image(systemName: currentStep == steps.count - 1 ? "checkmark" : "arrow.right")
                }
                .foregroundColor(.white)
                .padding(.horizontal, 24)
                .padding(.vertical, 12)
                .background(Color.blue, in: Capsule())
            }
        }
        .padding(.horizontal)
        .padding(.bottom, 20)
    }

    // MARK: - Highlight View

    private func highlightView(for area: OnboardingStep.HighlightArea) -> some View {
        GeometryReader { geometry in
            let size = geometry.size

            Rectangle()
                .fill(Color.clear)
                .border(Color.blue, width: 3)
                .frame(width: highlightSize(for: size).width, height: highlightSize(for: size).height)
                .position(highlightPosition(for: area, in: size))
                .shadow(color: .blue.opacity(0.5), radius: 10)
        }
    }

    private func highlightSize(for size: CGSize) -> CGSize {
        CGSize(width: size.width * 0.4, height: size.height * 0.2)
    }

    private func highlightPosition(for area: OnboardingStep.HighlightArea, in size: CGSize) -> CGPoint {
        let w = size.width
        let h = size.height

        switch area {
        case .topLeft:
            return CGPoint(x: w * 0.2, y: h * 0.1)
        case .topRight:
            return CGPoint(x: w * 0.8, y: h * 0.1)
        case .bottomLeft:
            return CGPoint(x: w * 0.2, y: h * 0.9)
        case .bottomRight:
            return CGPoint(x: w * 0.8, y: h * 0.9)
        case .center:
            return CGPoint(x: w * 0.5, y: h * 0.5)
        case .top:
            return CGPoint(x: w * 0.5, y: h * 0.1)
        case .bottom:
            return CGPoint(x: w * 0.5, y: h * 0.9)
        }
    }

    // MARK: - Actions

    private func nextStep() {
        if currentStep < steps.count - 1 {
            withAnimation {
                currentStep += 1
            }
        } else {
            completeOnboarding()
        }
    }

    private func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: storageKey)
        withAnimation {
            isPresented = false
        }
        onComplete?()
    }
}

// MARK: - Onboarding Manager

/// Helper class to manage onboarding state
public class OnboardingManager: ObservableObject {
    private let storageKey = "com.superwaage.onboarding.completed"

    @Published public var shouldShowOnboarding: Bool

    public init() {
        self.shouldShowOnboarding = !UserDefaults.standard.bool(forKey: storageKey)
    }

    /// Reset onboarding (show again)
    public func resetOnboarding() {
        UserDefaults.standard.set(false, forKey: storageKey)
        shouldShowOnboarding = true
    }

    /// Mark onboarding as completed
    public func completeOnboarding() {
        UserDefaults.standard.set(true, forKey: storageKey)
        shouldShowOnboarding = false
    }

    /// Check if onboarding was completed
    public var hasCompletedOnboarding: Bool {
        UserDefaults.standard.bool(forKey: storageKey)
    }
}

// MARK: - Predefined Step Collections

extension Array where Element == OnboardingStep {

    /// Default SUPERWAAGE onboarding steps
    public static var superwaageSteps: [OnboardingStep] {
        [
            OnboardingStep(
                title: "Willkommen bei SUPERWAAGE",
                message: "Scanne dein Essen mit LiDAR für präzise Volumen- und Gewichtsmessung",
                systemImage: "camera.viewfinder",
                highlightArea: nil
            ),
            OnboardingStep(
                title: "Objekt auswählen",
                message: "Tippe auf dein Essen im AR-View, um es zu markieren",
                systemImage: "hand.tap",
                highlightArea: .center
            ),
            OnboardingStep(
                title: "Scan starten",
                message: "Drücke den Scan-Button und bewege die Kamera langsam um das Objekt",
                systemImage: "play.circle.fill",
                highlightArea: .bottom
            ),
            OnboardingStep(
                title: "Qualität prüfen",
                message: "Achte auf die Qualitätsanzeige - grün bedeutet gute Abdeckung",
                systemImage: "star.fill",
                highlightArea: .topRight
            ),
            OnboardingStep(
                title: "Material wählen",
                message: "Wähle das passende Material aus der Liste, um das Gewicht zu berechnen",
                systemImage: "list.bullet",
                highlightArea: .bottomLeft
            ),
            OnboardingStep(
                title: "Fertig!",
                message: "Bereit zum Scannen. Viel Erfolg!",
                systemImage: "checkmark.circle.fill",
                highlightArea: nil
            )
        ]
    }

    /// Quick scan tutorial (3 steps)
    public static var quickScanSteps: [OnboardingStep] {
        [
            OnboardingStep(
                title: "Objekt antippen",
                message: "Tippe im AR-View auf das Objekt",
                systemImage: "hand.tap",
                highlightArea: .center
            ),
            OnboardingStep(
                title: "Scan läuft automatisch",
                message: "Der Scan startet automatisch bei guter Qualität",
                systemImage: "camera.metering.center.weighted",
                highlightArea: .top
            ),
            OnboardingStep(
                title: "Fertig!",
                message: "Der Scan stoppt automatisch bei ausreichender Abdeckung",
                systemImage: "checkmark.circle.fill",
                highlightArea: .bottom
            )
        ]
    }
}

// MARK: - View Extension for Easy Integration

extension View {

    /// Show onboarding overlay
    public func onboarding(
        isPresented: Binding<Bool>,
        steps: [OnboardingStep],
        onComplete: (() -> Void)? = nil
    ) -> some View {
        self.overlay(
            OnboardingCoachView(
                isPresented: isPresented,
                steps: steps,
                onComplete: onComplete
            )
        )
    }

    /// Show onboarding automatically on first launch
    public func onboardingOnFirstLaunch(
        steps: [OnboardingStep] = .superwaageSteps,
        onComplete: (() -> Void)? = nil
    ) -> some View {
        OnboardingWrapper(content: self, steps: steps, onComplete: onComplete)
    }
}

// MARK: - Wrapper for Auto-Show

private struct OnboardingWrapper<Content: View>: View {
    let content: Content
    let steps: [OnboardingStep]
    let onComplete: (() -> Void)?

    @StateObject private var manager = OnboardingManager()

    var body: some View {
        content
            .onboarding(
                isPresented: $manager.shouldShowOnboarding,
                steps: steps,
                onComplete: onComplete
            )
    }
}

// MARK: - Usage Examples
/*

 EXAMPLE 1: Manual Control

 struct ContentView: View {
     @State private var showOnboarding = false

     var body: some View {
         MainView()
             .onboarding(
                 isPresented: $showOnboarding,
                 steps: .superwaageSteps
             )
             .onAppear {
                 // Show on first launch
                 if !UserDefaults.standard.bool(forKey: "com.superwaage.onboarding.completed") {
                     showOnboarding = true
                 }
             }
     }
 }

 EXAMPLE 2: Automatic on First Launch

 struct ContentView: View {
     var body: some View {
         MainView()
             .onboardingOnFirstLaunch(steps: .superwaageSteps) {
                 print("Onboarding completed!")
             }
     }
 }

 EXAMPLE 3: Custom Steps

 struct ScanView: View {
     @State private var showOnboarding = true

     let customSteps = [
         OnboardingStep(
             title: "Auto-Scan aktiviert",
             message: "Diese Ansicht scannt automatisch",
             systemImage: "camera.metering.center.weighted"
         ),
         OnboardingStep(
             title: "Bewege die Kamera",
             message: "Bewege dich langsam um das Objekt",
             systemImage: "move.3d"
         )
     ]

     var body: some View {
         ARScannerView()
             .onboarding(isPresented: $showOnboarding, steps: customSteps)
     }
 }

 EXAMPLE 4: Replay Onboarding from Settings

 struct SettingsView: View {
     @StateObject private var onboardingManager = OnboardingManager()
     @State private var showOnboarding = false

     var body: some View {
         List {
             Section("Hilfe") {
                 Button("Einführung anzeigen") {
                     showOnboarding = true
                 }
             }
         }
         .onboarding(
             isPresented: $showOnboarding,
             steps: .superwaageSteps
         )
     }
 }

 */
