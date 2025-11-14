//
//  ReferenceObjectSelectionView.swift
//  SUPERWAAGE
//
//  Reference object selection screen
//  Clean, minimalist design with large touch targets
//

import SwiftUI

struct ReferenceObjectSelectionView: View {
    @ObservedObject var coordinator: QuickCalibrationCoordinator
    let onBack: () -> Void

    @State private var selectedObject: ReferenceObjectType? = nil
    @State private var showInfoSheet = false
    @State private var infoObject: ReferenceObjectType?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            VStack(spacing: 12) {
                Text("Referenzobjekt wählen")
                    .font(.system(size: 32, weight: .bold, design: .rounded))
                    .foregroundColor(.white)
                    .frame(maxWidth: .infinity, alignment: .leading)

                Text("Wähle ein Objekt, das du gerade zur Hand hast")
                    .font(.system(size: 17, weight: .regular, design: .rounded))
                    .foregroundColor(.white.opacity(0.6))
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.top, 24)
            .padding(.bottom, 32)

            // Object selection
            ScrollView {
                VStack(spacing: 16) {
                    ForEach(ReferenceObjectType.allCases) { object in
                        ObjectSelectionCard(
                            object: object,
                            isSelected: selectedObject == object,
                            onSelect: {
                                withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
                                    selectedObject = object
                                }

                                // Haptic
                                let generator = UIImpactFeedbackGenerator(style: .light)
                                generator.impactOccurred()
                            },
                            onInfo: {
                                infoObject = object
                                showInfoSheet = true
                            }
                        )
                    }
                }
                .padding(.horizontal, 24)
            }

            Spacer()

            // Continue button
            VStack(spacing: 12) {
                Button(action: {
                    guard let object = selectedObject else { return }
                    coordinator.startCalibration(with: object)
                }) {
                    HStack {
                        Text("Weiter")
                            .font(.system(size: 17, weight: .semibold, design: .rounded))

                        Image(systemName: "arrow.right")
                            .font(.system(size: 15, weight: .semibold))
                    }
                    .foregroundColor(.black)
                    .frame(maxWidth: .infinity)
                    .frame(height: 56)
                    .background(
                        RoundedRectangle(cornerRadius: 14)
                            .fill(selectedObject != nil ? Color.white : Color.white.opacity(0.3))
                    )
                }
                .disabled(selectedObject == nil)
                .buttonStyle(PressableButtonStyle())

                // Back button
                Button(action: onBack) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Zurück")
                        .font(.system(size: 17, weight: .medium, design: .rounded))
                }
                .foregroundColor(.white.opacity(0.6))
                .padding(.bottom, 8)
            }
            .padding(.horizontal, 24)
            .padding(.bottom, 32)
        }
        .background(Color.black.ignoresSafeArea())
        .sheet(isPresented: $showInfoSheet) {
            if let object = infoObject {
                ObjectInfoSheet(object: object)
            }
        }
    }
}

// MARK: - Object Selection Card

struct ObjectSelectionCard: View {
    let object: ReferenceObjectType
    let isSelected: Bool
    let onSelect: () -> Void
    let onInfo: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 16) {
                // Icon
                ZStack {
                    Circle()
                        .fill(isSelected ? Color.white.opacity(0.15) : Color.white.opacity(0.05))
                        .frame(width: 56, height: 56)

                    Image(systemName: object.icon)
                        .font(.system(size: 24, weight: .regular))
                        .foregroundColor(.white)
                }

                // Content
                VStack(alignment: .leading, spacing: 4) {
                    Text(object.displayName)
                        .font(.system(size: 18, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)

                    Text(object.description)
                        .font(.system(size: 15, weight: .regular, design: .rounded))
                        .foregroundColor(.white.opacity(0.5))
                }

                Spacer()

                // Info button
                Button(action: onInfo) {
                    Image(systemName: "info.circle")
                        .font(.system(size: 20, weight: .regular))
                        .foregroundColor(.white.opacity(0.3))
                }
                .buttonStyle(PlainButtonStyle())

                // Selection indicator
                ZStack {
                    Circle()
                        .strokeBorder(isSelected ? Color.white : Color.white.opacity(0.2), lineWidth: 2)
                        .frame(width: 24, height: 24)

                    if isSelected {
                        Circle()
                            .fill(Color.white)
                            .frame(width: 12, height: 12)
                    }
                }
            }
            .padding(20)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(isSelected ? Color.white.opacity(0.08) : Color.white.opacity(0.03))
                    .overlay(
                        RoundedRectangle(cornerRadius: 16)
                            .strokeBorder(
                                isSelected ? Color.white.opacity(0.2) : Color.clear,
                                lineWidth: 1
                            )
                    )
            )
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Info Sheet

struct ObjectInfoSheet: View {
    let object: ReferenceObjectType
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            VStack(spacing: 24) {
                // Icon
                ZStack {
                    Circle()
                        .fill(Color.gray.opacity(0.1))
                        .frame(width: 100, height: 100)

                    Image(systemName: object.icon)
                        .font(.system(size: 44, weight: .regular))
                        .foregroundColor(.primary)
                }
                .padding(.top, 32)

                // Info
                VStack(spacing: 16) {
                    InfoRow(label: "Name", value: object.displayName)
                    InfoRow(label: "Breite", value: String(format: "%.2f mm", object.dimensions.width * 1000))
                    InfoRow(label: "Höhe", value: String(format: "%.2f mm", object.dimensions.height * 1000))

                    if object.dimensions.shape == .circular {
                        InfoRow(label: "Form", value: "Kreisförmig")
                    } else {
                        InfoRow(label: "Form", value: "Rechteckig")
                    }
                }
                .padding(.horizontal, 24)

                Spacer()

                // Close button
                Button(action: { dismiss() }) {
                    Text("Schließen")
                        .font(.system(size: 17, weight: .semibold, design: .rounded))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .frame(height: 56)
                        .background(
                            RoundedRectangle(cornerRadius: 14)
                                .fill(Color.blue)
                        )
                }
                .buttonStyle(PressableButtonStyle())
                .padding(.horizontal, 24)
                .padding(.bottom, 32)
            }
            .navigationTitle(object.displayName)
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}

// MARK: - Preview

#Preview {
    ReferenceObjectSelectionView(
        coordinator: QuickCalibrationCoordinator(),
        onBack: {}
    )
    .preferredColorScheme(.dark)
}
