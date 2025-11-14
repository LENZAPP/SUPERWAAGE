//
//  CalibrationSuccessView.swift
//  SUPERWAAGE
//
//  Success screen showing calibration results
//  Clean, celebratory design
//

import SwiftUI

struct CalibrationSuccessView: View {
    let result: EnhancedCalibrationResult
    let onDone: () -> Void

    @State private var showDetails = false
    @State private var animateSuccess = false

    var body: some View {
        VStack(spacing: 40) {
            Spacer()

            // Success icon
            ZStack {
                Circle()
                    .fill(
                        LinearGradient(
                            colors: [.green.opacity(0.2), .green.opacity(0.05)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 140, height: 140)
                    .scaleEffect(animateSuccess ? 1.0 : 0.5)
                    .opacity(animateSuccess ? 1.0 : 0.0)

                Image(systemName: "checkmark.circle.fill")
                    .font(.system(size: 80, weight: .light))
                    .foregroundColor(.green)
                    .scaleEffect(animateSuccess ? 1.0 : 0.3)
                    .opacity(animateSuccess ? 1.0 : 0.0)
            }

            // Title
            VStack(spacing: 12) {
                Text("Kalibrierung abgeschlossen!")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text("Deine App misst jetzt deutlich genauer.")
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .opacity(animateSuccess ? 1.0 : 0.0)
            .offset(y: animateSuccess ? 0 : 20)

            // Accuracy card
            VStack(spacing: 20) {
                HStack {
                    Text("Erwartete Genauigkeit")
                        .font(.system(size: 15, weight: .semibold, design: .rounded))
                        .foregroundColor(.white.opacity(0.6))

                    Spacer()

                    QualityBadge(score: result.qualityScore)
                }

                Divider()
                    .background(Color.white.opacity(0.1))

                VStack(spacing: 12) {
                    AccuracyRow(
                        icon: "cube.fill",
                        label: "Kleine Objekte",
                        value: result.qualityScore >= 90 ? "±1–2 g" : "±1–3 g"
                    )

                    AccuracyRow(
                        icon: "cube.transparent.fill",
                        label: "Größere Objekte",
                        value: result.qualityScore >= 90 ? "±3–8 g" : "±5–12 g"
                    )
                }
            }
            .padding(24)
            .background(
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color.white.opacity(0.05))
                    .overlay(
                        RoundedRectangle(cornerRadius: 20)
                            .strokeBorder(Color.white.opacity(0.1), lineWidth: 1)
                    )
            )
            .padding(.horizontal, 32)
            .opacity(animateSuccess ? 1.0 : 0.0)
            .offset(y: animateSuccess ? 0 : 40)

            // Details button
            if !showDetails {
                Button(action: { withAnimation { showDetails.toggle() } }) {
                    HStack {
                        Text("Details anzeigen")
                            .font(.system(size: 15, weight: .medium, design: .rounded))

                        Image(systemName: "chevron.down")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(.white.opacity(0.5))
                }
                .opacity(animateSuccess ? 1.0 : 0.0)
            }

            // Technical details (collapsed)
            if showDetails {
                TechnicalDetailsCard(result: result)
                    .padding(.horizontal, 32)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            Spacer()

            // Done button
            Button(action: onDone) {
                Text("Fertig")
                    .font(.system(size: 17, weight: .semibold, design: .rounded))
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(Color.white)
                    )
            }
            .buttonStyle(PressableButtonStyle())
            .padding(.horizontal, 32)
            .padding(.bottom, 48)
            .opacity(animateSuccess ? 1.0 : 0.0)
        }
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            withAnimation(.spring(response: 0.6, dampingFraction: 0.7)) {
                animateSuccess = true
            }

            // Haptic feedback
            let generator = UINotificationFeedbackGenerator()
            generator.notificationOccurred(.success)
        }
    }
}

// MARK: - Quality Badge

struct QualityBadge: View {
    let score: Double

    var qualityText: String {
        if score >= 90 { return "Exzellent" }
        if score >= 75 { return "Sehr gut" }
        if score >= 60 { return "Gut" }
        return "Befriedigend"
    }

    var qualityColor: Color {
        if score >= 90 { return .green }
        if score >= 75 { return .cyan }
        if score >= 60 { return .orange }
        return .yellow
    }

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "star.fill")
                .font(.system(size: 12, weight: .bold))
                .foregroundColor(qualityColor)

            Text(qualityText)
                .font(.system(size: 15, weight: .bold, design: .rounded))
                .foregroundColor(qualityColor)

            Text("\(Int(score))%")
                .font(.system(size: 13, weight: .semibold, design: .rounded))
                .foregroundColor(qualityColor.opacity(0.7))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(
            Capsule()
                .fill(qualityColor.opacity(0.15))
        )
    }
}

// MARK: - Accuracy Row

struct AccuracyRow: View {
    let icon: String
    let label: String
    let value: String

    var body: some View {
        HStack {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .regular))
                .foregroundColor(.white.opacity(0.5))
                .frame(width: 24)

            Text(label)
                .font(.system(size: 16, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.8))

            Spacer()

            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
        }
    }
}

// MARK: - Technical Details Card

struct TechnicalDetailsCard: View {
    let result: EnhancedCalibrationResult

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Text("Technische Details")
                    .font(.system(size: 15, weight: .semibold, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))

                Spacer()
            }

            Divider()
                .background(Color.white.opacity(0.1))

            VStack(alignment: .leading, spacing: 10) {
                CalibrationDetailRow(label: "Skalierungsfaktor", value: String(format: "%.6f", result.scaleFactor))
                CalibrationDetailRow(label: "Verwendete Frames", value: "\(result.frameCount)")
                CalibrationDetailRow(label: "Depth Bias (a)", value: String(format: "%.4f", result.depthBiasCoefficients.first ?? 0))
                if result.depthBiasCoefficients.count > 1 {
                    CalibrationDetailRow(label: "Depth Bias (b)", value: String(format: "%.4f", result.depthBiasCoefficients[1]))
                }
                CalibrationDetailRow(label: "MSE", value: String(format: "%.6f", result.mse))
                CalibrationDetailRow(label: "Referenzobjekt", value: result.referenceObject.displayName)
            }
        }
        .padding(20)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(Color.white.opacity(0.03))
                .overlay(
                    RoundedRectangle(cornerRadius: 16)
                        .strokeBorder(Color.white.opacity(0.08), lineWidth: 1)
                )
        )
    }
}

struct CalibrationDetailRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .font(.system(size: 14, weight: .regular, design: .rounded))
                .foregroundColor(.white.opacity(0.6))

            Spacer()

            Text(value)
                .font(.system(size: 14, weight: .regular, design: .monospaced))
                .foregroundColor(.white.opacity(0.9))
        }
    }
}

// MARK: - Failure View

struct CalibrationFailureView: View {
    let message: String
    let onRetry: () -> Void
    let onCancel: () -> Void

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // Error icon
            ZStack {
                Circle()
                    .fill(Color.red.opacity(0.1))
                    .frame(width: 120, height: 120)

                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60, weight: .light))
                    .foregroundColor(.orange)
            }

            // Message
            VStack(spacing: 12) {
                Text("Kalibrierung fehlgeschlagen")
                    .font(.system(size: 28, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .multilineTextAlignment(.center)

                Text(message)
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.7))
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 32)
            }

            Spacer()

            // Buttons
            VStack(spacing: 16) {
                Button(action: onRetry) {
                    Text("Erneut versuchen")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.white)
                        )
                }
                .buttonStyle(PressableButtonStyle())

                Button(action: onCancel) {
                    Text("Abbrechen")
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
        .background(Color.black.ignoresSafeArea())
    }
}

// MARK: - Preview

#Preview("Success") {
    CalibrationSuccessView(
        result: EnhancedCalibrationResult(
            scaleFactor: 1.0234,
            depthBiasCoefficients: [0.0012, -0.0003],
            qualityScore: 92.5,
            referenceObject: .euroCoin,
            frameCount: 3,
            timestamp: Date(),
            mse: 0.00012
        ),
        onDone: {}
    )
    .preferredColorScheme(.dark)
}

#Preview("Failure") {
    CalibrationFailureView(
        message: "Das Referenzobjekt konnte nicht eindeutig erkannt werden.",
        onRetry: {},
        onCancel: {}
    )
    .preferredColorScheme(.dark)
}
