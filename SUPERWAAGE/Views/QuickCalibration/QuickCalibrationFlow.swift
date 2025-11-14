//
//  QuickCalibrationFlow.swift
//  SUPERWAAGE
//
//  Main container for Quick Accuracy Calibration flow
//  Modern, minimalist Apple-style UI
//

import SwiftUI

/// Main calibration flow container
struct QuickCalibrationFlow: View {
    @StateObject private var coordinator = QuickCalibrationCoordinator()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        ZStack {
            // Background
            Color.black
                .ignoresSafeArea()

            // Content based on state
            Group {
                switch coordinator.state {
                case .notStarted:
                    CalibrationStartView(
                        onStart: {
                            coordinator.startFlow()
                        },
                        onSkip: {
                            dismiss()
                        }
                    )
                    .transition(.opacity.combined(with: .scale(scale: 0.95)))

                case .selectingObject:
                    ReferenceObjectSelectionView(
                        coordinator: coordinator,
                        onBack: {
                            coordinator.reset()
                        }
                    )
                    .transition(.move(edge: .trailing).combined(with: .opacity))

                case .capturingFrame(let angle, let progress, let total):
                    QuickCalibrationARView(
                        coordinator: coordinator,
                        currentAngle: angle,
                        progress: progress,
                        total: total
                    )
                    .transition(.opacity)

                case .processing:
                    CalibrationProcessingView()
                        .transition(.opacity.combined(with: .scale(scale: 0.9)))

                case .completed(let result):
                    CalibrationSuccessView(
                        result: result,
                        onDone: {
                            dismiss()
                        }
                    )
                    .transition(.move(edge: .bottom).combined(with: .opacity))

                case .failed(let message):
                    CalibrationFailureView(
                        message: message,
                        onRetry: {
                            coordinator.reset()
                        },
                        onCancel: {
                            dismiss()
                        }
                    )
                    .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: coordinator.state)
        }
        .preferredColorScheme(.dark)
    }
}

// MARK: - Start View

struct CalibrationStartView: View {
    let onStart: () -> Void
    let onSkip: () -> Void

    @State private var showDetails = false

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Icon
            ZStack {
                Circle()
                    .fill(Color.white.opacity(0.05))
                    .frame(width: 120, height: 120)

                Image(systemName: "target")
                    .font(.system(size: 50, weight: .light))
                    .foregroundColor(.white)
            }

            // Title
            Text("Messgenauigkeit optimieren?")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            // Description
            Text("Verbessere die Präzision deiner\nGewichtsmessungen in nur 10 Sekunden.")
                .font(.system(size: 17, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.7))
                .multilineTextAlignment(.center)
                .lineSpacing(4)

            Spacer()

            // Buttons
            VStack(spacing: 16) {
                // Primary button
                Button(action: onStart) {
                    HStack {
                        Text("Jetzt kalibrieren")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))

                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white)
                    )
                }
                .buttonStyle(PressableButtonStyle())

                // Secondary button
                Button(action: onSkip) {
                    Text("Später")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white.opacity(0.05))
                        )
                }
                .buttonStyle(PressableButtonStyle())
            }
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
        }
        .padding(.horizontal, 32)
    }
}

// MARK: - Pressable Button Style

struct PressableButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.97 : 1.0)
            .opacity(configuration.isPressed ? 0.9 : 1.0)
            .animation(.easeInOut(duration: 0.1), value: configuration.isPressed)
    }
}

// MARK: - Preview

#Preview("Start") {
    CalibrationStartView(
        onStart: {},
        onSkip: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Full Flow") {
    QuickCalibrationFlow()
}
