//
//  QuickUI+SwiftUI.swift
//  SUPERWAAGE
//
//  SwiftUI-native UI components for professional feedback and overlays
//
//  Components:
//  - HUDOverlay: Floating heads-up display with icon + message
//  - ProgressBanner: Progress indicator with message
//  - StatusBadge: Floating status indicator (quality, coverage, etc.)
//  - ToastNotification: Auto-dismissing toast message
//
//  Usage:
//    .overlay(HUDOverlay(message: "Scanning...", systemImage: "camera"))
//    .overlay(StatusBadge(text: "Good Quality", color: .green))
//

import SwiftUI

// MARK: - HUD Overlay

/// Floating HUD with icon and message (top-center)
public struct HUDOverlay: View {
    let message: String
    let systemImage: String
    let tint: Color

    public init(message: String, systemImage: String = "info.circle.fill", tint: Color = .blue) {
        self.message = message
        self.systemImage = systemImage
        self.tint = tint
    }

    public var body: some View {
        VStack {
            HStack(spacing: 12) {
                Image(systemName: systemImage)
                    .font(.title3)
                    .foregroundColor(tint)

                Text(message)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(.primary)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            .background(.ultraThinMaterial, in: Capsule())
            .shadow(color: .black.opacity(0.1), radius: 8, y: 4)
            .padding(.top, 50)

            Spacer()
        }
        .transition(.move(edge: .top).combined(with: .opacity))
        .animation(.spring(response: 0.3, dampingFraction: 0.7), value: message)
    }
}

// MARK: - Progress Banner

/// Full-width progress banner with message (bottom)
public struct ProgressBanner: View {
    let message: String
    let progress: Double

    public init(message: String, progress: Double) {
        self.message = message
        self.progress = progress
    }

    public var body: some View {
        VStack {
            Spacer()

            VStack(spacing: 12) {
                HStack {
                    Text(message)
                        .font(.subheadline.weight(.medium))
                    Spacer()
                    Text("\(Int(progress * 100))%")
                        .font(.subheadline.monospacedDigit())
                        .foregroundColor(.secondary)
                }

                ProgressView(value: progress)
                    .progressViewStyle(.linear)
                    .tint(progressColor(progress))
            }
            .padding(16)
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 16))
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
        .transition(.move(edge: .bottom).combined(with: .opacity))
    }

    private func progressColor(_ value: Double) -> Color {
        if value < 0.5 { return .red }
        if value < 0.8 { return .orange }
        return .green
    }
}

// MARK: - Status Badge

/// Small floating status badge (top-right)
public struct StatusBadge: View {
    let text: String
    let color: Color
    let systemImage: String?

    public init(text: String, color: Color, systemImage: String? = nil) {
        self.text = text
        self.color = color
        self.systemImage = systemImage
    }

    public var body: some View {
        VStack {
            HStack {
                Spacer()

                HStack(spacing: 6) {
                    if let icon = systemImage {
                        Image(systemName: icon)
                            .font(.caption.weight(.bold))
                    }
                    Text(text)
                        .font(.caption.weight(.semibold))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(color, in: Capsule())
                .shadow(color: color.opacity(0.3), radius: 4, y: 2)
                .padding(.trailing, 16)
                .padding(.top, 50)
            }

            Spacer()
        }
        .transition(.scale.combined(with: .opacity))
    }
}

// MARK: - Toast Notification

/// Auto-dismissing toast message (center-bottom)
public struct ToastNotification: View {
    let message: String
    let systemImage: String?
    let backgroundColor: Color

    @State private var isVisible = true

    public init(
        message: String,
        systemImage: String? = "checkmark.circle.fill",
        backgroundColor: Color = .green
    ) {
        self.message = message
        self.systemImage = systemImage
        self.backgroundColor = backgroundColor
    }

    public var body: some View {
        VStack {
            Spacer()

            if isVisible {
                HStack(spacing: 10) {
                    if let icon = systemImage {
                        Image(systemName: icon)
                            .font(.body)
                    }
                    Text(message)
                        .font(.subheadline.weight(.medium))
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
                .background(backgroundColor, in: Capsule())
                .shadow(color: .black.opacity(0.2), radius: 10, y: 5)
                .padding(.bottom, 100)
                .transition(.move(edge: .bottom).combined(with: .opacity))
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 2.5) {
                        withAnimation(.spring(response: 0.3)) {
                            isVisible = false
                        }
                    }
                }
            }
        }
    }
}

// NOTE: QualityIndicator already exists in ScanProgressView.swift - using that implementation
