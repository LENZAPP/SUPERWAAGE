//
//  CalibrationProcessingView.swift
//  SUPERWAAGE
//
//  Processing screen with animated progress
//  Shows calculation steps
//

import SwiftUI

struct CalibrationProcessingView: View {
    @State private var currentStep = 0
    @State private var progress: CGFloat = 0.0

    private let steps = [
        ("checkmark.circle", "Erkenne Konturen"),
        ("ruler", "Bestimme Pixel-Abstand"),
        ("cube.transparent", "Analysiere Tiefenwerte"),
        ("function", "Schätze Scale-Faktor"),
        ("chart.line.uptrend.xyaxis", "Führe Regression durch")
    ]

    var body: some View {
        VStack(spacing: 48) {
            Spacer()

            // Title
            Text("Kalibrierung wird berechnet...")
                .font(.system(size: 28, weight: .semibold, design: .rounded))
                .foregroundColor(.white)
                .multilineTextAlignment(.center)

            // Progress circle
            ZStack {
                // Background circle
                Circle()
                    .stroke(Color.white.opacity(0.1), lineWidth: 8)
                    .frame(width: 120, height: 120)

                // Progress circle
                Circle()
                    .trim(from: 0, to: progress)
                    .stroke(
                        LinearGradient(
                            colors: [.blue, .cyan],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        ),
                        style: StrokeStyle(lineWidth: 8, lineCap: .round)
                    )
                    .frame(width: 120, height: 120)
                    .rotationEffect(.degrees(-90))
                    .animation(.easeInOut(duration: 0.5), value: progress)

                // Percentage
                Text("\(Int(progress * 100))%")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
            }

            // Steps list
            VStack(spacing: 16) {
                ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                    StepRow(
                        icon: step.0,
                        text: step.1,
                        isActive: index == currentStep,
                        isCompleted: index < currentStep
                    )
                }
            }
            .padding(.horizontal, 32)

            Spacer()
        }
        .padding(.horizontal, 32)
        .background(Color.black.ignoresSafeArea())
        .onAppear {
            animateProgress()
        }
    }

    private func animateProgress() {
        let stepDuration = 0.6
        let stepIncrement = 1.0 / Double(steps.count)

        for i in 0..<steps.count {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * stepDuration) {
                withAnimation {
                    currentStep = i
                    progress = CGFloat((i + 1)) * CGFloat(stepIncrement)
                }
            }
        }
    }
}

// MARK: - Step Row

struct StepRow: View {
    let icon: String
    let text: String
    let isActive: Bool
    let isCompleted: Bool

    var body: some View {
        HStack(spacing: 16) {
            // Icon
            ZStack {
                Circle()
                    .fill(isActive ? Color.blue.opacity(0.2) : Color.white.opacity(0.05))
                    .frame(width: 40, height: 40)

                if isCompleted {
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundColor(.green)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(isActive ? .blue : .white.opacity(0.3))
                }
            }

            // Text
            Text(text)
                .font(.system(size: 16, weight: isActive ? .semibold : .regular, design: .rounded))
                .foregroundColor(isActive ? .white : .white.opacity(0.5))

            Spacer()

            // Loading indicator
            if isActive {
                ProgressView()
                    .progressViewStyle(CircularProgressViewStyle(tint: .blue))
                    .scaleEffect(0.8)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isActive ? Color.white.opacity(0.05) : Color.clear)
        )
    }
}

// MARK: - Preview

#Preview {
    CalibrationProcessingView()
        .preferredColorScheme(.dark)
}
