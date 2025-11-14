//
//  BerkelScaleView.swift
//  SUPERWAAGE
//
//  Vintage Berkel Scale Display (1930/40s style)
//  Shows weight with animated pointer
//

import SwiftUI

struct BerkelScaleView: View {
    let weight: Double // in grams (0-1000)

    @State private var animatedWeight: Double = 0

    var pointerRotation: Double {
        // Map 0-1000g to -45° to +45°
        return ((animatedWeight / 1000.0) * 90.0) - 45.0
    }

    var body: some View {
        GeometryReader { geometry in
            let scale = geometry.size.width / 400.0

            ZStack {
                // Base
                ScaleBase()

                // Display (positioned above scale)
                WeightDisplay(weight: animatedWeight)
                    .position(x: geometry.size.width / 2, y: 152 * scale)

                // Pointer (rotates around center)
                ScalePointer()
                    .rotationEffect(
                        .degrees(pointerRotation),
                        anchor: UnitPoint(x: 0.5, y: 0.76)
                    )
            }
            .scaleEffect(scale)
            .frame(width: geometry.size.width, height: geometry.size.height)
        }
        .aspectRatio(400/500, contentMode: .fit)
        .onAppear {
            withAnimation(.spring(duration: 1.5)) {
                animatedWeight = weight
            }
        }
        .onChange(of: weight) { oldValue, newValue in
            withAnimation(.spring(duration: 1.0)) {
                animatedWeight = newValue
            }
        }
    }
}

// MARK: - Scale Base
struct ScaleBase: View {
    var body: some View {
        ZStack {
            // Basis
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(red: 0.71, green: 0.35, blue: 0.29))
                .frame(width: 240, height: 60)
                .position(x: 200, y: 450)

            RoundedRectangle(cornerRadius: 6)
                .fill(Color(red: 0.78, green: 0.35, blue: 0.33))
                .frame(width: 230, height: 50)
                .position(x: 200, y: 450)

            // Body (trapezoid)
            TrapezoidShape()
                .fill(Color(red: 0.78, green: 0.35, blue: 0.33))
                .stroke(Color(red: 0.63, green: 0.27, blue: 0.22), lineWidth: 3)
                .frame(width: 180, height: 300)
                .position(x: 200, y: 270)

            // Scale face
            Circle()
                .fill(Color(red: 0.63, green: 0.27, blue: 0.22))
                .frame(width: 250, height: 230)
                .position(x: 200, y: 220)
                .shadow(radius: 5)

            Circle()
                .fill(Color(red: 0.91, green: 0.87, blue: 0.82))
                .frame(width: 240, height: 220)
                .position(x: 200, y: 220)

            Circle()
                .fill(Color(red: 0.99, green: 0.98, blue: 0.97))
                .frame(width: 220, height: 200)
                .position(x: 200, y: 220)

            // Berkel Logo
            Text("BERKEL")
                .font(.system(size: 16, weight: .bold, design: .serif))
                .italic()
                .foregroundColor(Color(red: 0.71, green: 0.29, blue: 0.24))
                .position(x: 200, y: 160)

            // Scale marks
            ScaleMarks()

            // Made in Holland
            Text("Made in Holland")
                .font(.system(size: 10, design: .serif))
                .italic()
                .foregroundColor(Color(red: 0.54, green: 0.48, blue: 0.42))
                .position(x: 200, y: 255)

            // Screws
            ForEach([CGPoint(x: 130, y: 150), CGPoint(x: 270, y: 150),
                     CGPoint(x: 130, y: 290), CGPoint(x: 270, y: 290)], id: \.x) { point in
                Circle()
                    .fill(Color(red: 0.29, green: 0.29, blue: 0.29))
                    .frame(width: 8, height: 8)
                    .position(point)
            }
        }
    }
}

// MARK: - Weight Display
struct WeightDisplay: View {
    let weight: Double

    var body: some View {
        ZStack {
            // Black display box
            RoundedRectangle(cornerRadius: 4)
                .fill(Color(red: 0.16, green: 0.16, blue: 0.16))
                .stroke(Color(red: 0.10, green: 0.10, blue: 0.10), lineWidth: 2)
                .frame(width: 100, height: 35)

            RoundedRectangle(cornerRadius: 3)
                .fill(Color(red: 0.10, green: 0.10, blue: 0.10))
                .frame(width: 94, height: 29)

            // Gold weight text
            Text("\(Int(weight))g")
                .font(.system(size: 24, weight: .bold, design: .serif))
                .foregroundColor(Color(red: 1.0, green: 0.84, blue: 0.0))
        }
    }
}

// MARK: - Scale Marks
struct ScaleMarks: View {
    var body: some View {
        ZStack {
            // Main arc
            Arc(startAngle: .degrees(135), endAngle: .degrees(45), clockwise: false)
                .stroke(Color(red: 0.78, green: 0.66, blue: 0.51), lineWidth: 6)
                .frame(width: 160, height: 40)
                .position(x: 200, y: 195)

            // Numbers
            Text("0").font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundColor(Color(red: 0.16, green: 0.16, blue: 0.16))
                .position(x: 110, y: 200)

            Text("250").font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundColor(Color(red: 0.16, green: 0.16, blue: 0.16))
                .position(x: 143, y: 188)

            Text("500").font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundColor(Color(red: 0.16, green: 0.16, blue: 0.16))
                .position(x: 192, y: 180)

            Text("750").font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundColor(Color(red: 0.16, green: 0.16, blue: 0.16))
                .position(x: 237, y: 188)

            Text("1000").font(.system(size: 14, weight: .bold, design: .serif))
                .foregroundColor(Color(red: 0.16, green: 0.16, blue: 0.16))
                .position(x: 268, y: 200)

            // Tick marks
            ForEach(0..<17) { i in
                let angle = 135.0 - (Double(i) * 90.0 / 16.0)
                let isMain = i % 4 == 0
                TickMark(angle: angle, length: isMain ? 10 : 6, width: isMain ? 2 : 1)
            }
        }
    }
}

// MARK: - Scale Pointer
struct ScalePointer: View {
    var body: some View {
        ZStack {
            // Shadow
            Path { path in
                path.move(to: CGPoint(x: 200, y: 295))
                path.addLine(to: CGPoint(x: 198, y: 190))
                path.addLine(to: CGPoint(x: 202, y: 190))
            }
            .fill(Color.black.opacity(0.2))
            .offset(x: 2, y: 2)

            // Pointer body
            Path { path in
                path.move(to: CGPoint(x: 200, y: 295))
                path.addLine(to: CGPoint(x: 196, y: 185))
                path.addQuadCurve(to: CGPoint(x: 204, y: 185), control: CGPoint(x: 200, y: 180))
            }
            .fill(
                LinearGradient(
                    colors: [
                        Color(red: 0.29, green: 0.29, blue: 0.29),
                        Color(red: 0.16, green: 0.16, blue: 0.16),
                        Color(red: 0.10, green: 0.10, blue: 0.10)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )

            // Highlight
            Path { path in
                path.move(to: CGPoint(x: 200, y: 295))
                path.addLine(to: CGPoint(x: 199, y: 185))
                path.addLine(to: CGPoint(x: 200, y: 180))
            }
            .fill(Color(red: 0.29, green: 0.29, blue: 0.29).opacity(0.5))

            // Center rivet
            Circle()
                .fill(
                    RadialGradient(
                        colors: [
                            Color(red: 0.29, green: 0.29, blue: 0.29),
                            Color(red: 0.16, green: 0.16, blue: 0.16)
                        ],
                        center: .center,
                        startRadius: 0,
                        endRadius: 12
                    )
                )
                .frame(width: 24, height: 24)
                .position(x: 200, y: 295)

            Circle()
                .fill(Color(red: 0.16, green: 0.16, blue: 0.16))
                .frame(width: 20, height: 20)
                .position(x: 200, y: 295)

            Circle()
                .fill(Color(red: 0.10, green: 0.10, blue: 0.10))
                .frame(width: 12, height: 12)
                .position(x: 200, y: 295)

            // Highlight on rivet
            Circle()
                .fill(Color(red: 0.42, green: 0.42, blue: 0.42).opacity(0.7))
                .frame(width: 4, height: 4)
                .position(x: 198, y: 293)
        }
    }
}

// MARK: - Helper Shapes
struct TrapezoidShape: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX + 30, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addQuadCurve(
            to: CGPoint(x: rect.maxX, y: rect.minY),
            control: CGPoint(x: rect.midX, y: rect.minY - 20)
        )
        path.addLine(to: CGPoint(x: rect.maxX - 30, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

struct Arc: Shape {
    let startAngle: Angle
    let endAngle: Angle
    let clockwise: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.addArc(
            center: CGPoint(x: rect.midX, y: rect.midY),
            radius: rect.width / 2,
            startAngle: startAngle,
            endAngle: endAngle,
            clockwise: clockwise
        )
        return path
    }
}

struct TickMark: View {
    let angle: Double
    let length: CGFloat
    let width: CGFloat

    var body: some View {
        Rectangle()
            .fill(Color(red: 0.16, green: 0.16, blue: 0.16))
            .frame(width: width, height: length)
            .position(x: 200 + cos(angle * .pi / 180) * 80,
                     y: 195 + sin(angle * .pi / 180) * 40)
            .rotationEffect(.degrees(angle + 90))
    }
}

// MARK: - Preview
#Preview {
    VStack {
        BerkelScaleView(weight: 450)
            .frame(height: 400)

        BerkelScaleView(weight: 750)
            .frame(height: 400)
    }
}
