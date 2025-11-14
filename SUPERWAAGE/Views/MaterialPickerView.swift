//
//  MaterialPickerView.swift
//  SUPERWAAGE
//
//  Enhanced material selection with comprehensive kitchen material database
//  Apple Senior Developer level implementation
//

import SwiftUI
import UIKit

struct MaterialPickerView: View {
    @EnvironmentObject var scanViewModel: ScanViewModel
    @Environment(\.dismiss) var dismiss
    @State private var selectedCategory: MaterialCategory = .flour
    @State private var searchText = ""

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Search Bar
                HStack {
                    Image(systemName: "magnifyingglass")
                        .foregroundColor(.secondary)
                    TextField("Material suchen...", text: $searchText)
                        .textFieldStyle(.plain)

                    if !searchText.isEmpty {
                        Button(action: { searchText = "" }) {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(10)
                .background(Color(.systemGray6))
                .cornerRadius(10)
                .padding()

                // Category Picker (only shown when not searching)
                if searchText.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 12) {
                            ForEach(MaterialCategory.allCases.filter { $0 != .custom }, id: \.self) { category in
                                CategoryChip(
                                    category: category,
                                    isSelected: category == selectedCategory
                                )
                                .onTapGesture {
                                    selectedCategory = category
                                }
                            }
                        }
                        .padding(.horizontal)
                    }
                    .padding(.bottom, 8)
                }

                // Materials List
                ScrollView {
                    LazyVGrid(columns: [
                        GridItem(.flexible()),
                        GridItem(.flexible())
                    ], spacing: 16) {
                        ForEach(filteredMaterials, id: \.id) { material in
                            MaterialCard(
                                material: material,
                                isSelected: material.id == scanViewModel.selectedMaterial.id
                            )
                            .onTapGesture {
                                selectMaterial(material)
                            }
                        }
                    }
                    .padding()
                }

                // Material Count Info
                HStack {
                    Image(systemName: "info.circle")
                        .foregroundColor(.blue)
                        .font(.caption)

                    Text("\(filteredMaterials.count) Materialien verfügbar")
                        .font(.caption)
                        .foregroundColor(.secondary)

                    Spacer()

                    if scanViewModel.isCalibrated {
                        HStack(spacing: 4) {
                            Image(systemName: "checkmark.seal.fill")
                                .foregroundColor(.green)
                                .font(.caption)
                            Text("Kalibriert")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                    }
                }
                .padding(.horizontal)
                .padding(.bottom, 8)
            }
            .navigationTitle("Material auswählen")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { /* Show calibration */ }) {
                        Image(systemName: "target")
                            .foregroundColor(.blue)
                    }
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Fertig") {
                        dismiss()
                    }
                }
            }
        }
    }

    // MARK: - Filtered Materials

    private var filteredMaterials: [MaterialPreset] {
        if !searchText.isEmpty {
            return DensityDatabase.search(searchText)
        } else {
            return DensityDatabase.presets(for: selectedCategory)
        }
    }

    private func selectMaterial(_ material: MaterialPreset) {
        scanViewModel.setMaterial(material)

        // Haptic feedback
        let generator = UIImpactFeedbackGenerator(style: .medium)
        generator.impactOccurred()

        // Auto-dismiss after short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            dismiss()
        }
    }
}

// MARK: - Category Chip
struct CategoryChip: View {
    let category: MaterialCategory
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 6) {
            Text(categoryIcon)
                .font(.title3)

            Text(category.rawValue)
                .font(.caption2)
                .fontWeight(isSelected ? .semibold : .regular)
                .foregroundColor(isSelected ? .white : .primary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 12)
                .fill(isSelected ? Color.blue : Color(.systemGray5))
        )
    }

    private var categoryIcon: String {
        switch category {
        case .flour: return "🌾"
        case .sugar: return "🍬"
        case .salt: return "🧂"
        case .grains: return "🌾"
        case .spices: return "🌿"
        case .powder: return "☁️"
        case .dairy: return "🧈"
        case .nuts: return "🥜"
        case .liquids: return "💧"
        case .custom: return "⚙️"
        }
    }
}

// MARK: - Material Card
struct MaterialCard: View {
    let material: MaterialPreset
    let isSelected: Bool

    var body: some View {
        VStack(spacing: 12) {
            // Category Icon
            Text(categoryIcon)
                .font(.system(size: 40))

            // Name
            Text(material.name)
                .font(.subheadline)
                .fontWeight(.medium)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.8)
                .frame(height: 36)

            // Density Info
            VStack(spacing: 2) {
                Text("Dichte")
                    .font(.caption2)
                    .foregroundColor(.secondary)

                Text(String(format: "%.2f g/cm³", material.density))
                    .font(.caption)
                    .fontWeight(.semibold)
                    .foregroundColor(.primary)
            }

            // Density Range (if available)
            if let range = material.densityRange {
                Text(String(format: "%.2f - %.2f", range.lowerBound, range.upperBound))
                    .font(.caption2)
                    .foregroundColor(.secondary)
            } else {
                Text("Konstant")
                    .font(.caption2)
                    .foregroundColor(.green)
            }

            // Packing Factor (for powders)
            if material.packingFactor != nil {
                HStack(spacing: 4) {
                    Image(systemName: "scalemass")
                        .font(.caption2)
                        .foregroundColor(.orange)
                    Text("Pulver")
                        .font(.caption2)
                        .foregroundColor(.orange)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 12)
        .padding(.horizontal, 8)
        .background(
            RoundedRectangle(cornerRadius: 16)
                .fill(isSelected ? Color.blue.opacity(0.15) : Color(.systemGray6))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 16)
                .stroke(isSelected ? Color.blue : Color.clear, lineWidth: 2)
        )
    }

    private var categoryIcon: String {
        switch material.category {
        case .flour: return "🌾"
        case .sugar: return "🍬"
        case .salt: return "🧂"
        case .grains: return "🌾"
        case .spices: return "🌿"
        case .powder: return "☁️"
        case .dairy: return "🧈"
        case .nuts: return "🥜"
        case .liquids: return "💧"
        case .custom: return "⚙️"
        }
    }
}

#Preview {
    MaterialPickerView()
        .environmentObject(ScanViewModel())
}
