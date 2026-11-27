

import Foundation
import SwiftUI
import SceneKit

//
//  File.swift
//  Laguna Seca Raceway
//
//  Created by David Nishimoto on 11/25/26.
//

import Foundation
import SwiftUI
import SceneKit

struct SteeringWheelNavView: View {
    @Binding var wheelSteer: Float // -1.0 left ... +1.0 right

    private let maxDragWidth: CGFloat = 100
    // Sports-car rack: ~2.28 turns lock-to-lock (±410 degrees)
    private let maxWheelDegrees: Double = 410.0

    var body: some View {
        VStack(spacing: 6) {
            ZStack {
                Circle()
                    .fill(.black.opacity(0.45))
                    .frame(width: 112, height: 112)

                Circle()
                    .stroke(.white.opacity(0.9), lineWidth: 7)
                    .frame(width: 96, height: 96)

                Rectangle()
                    .fill(.white.opacity(0.85))
                    .frame(width: 88, height: 6)

                Rectangle()
                    .fill(.white.opacity(0.85))
                    .frame(width: 6, height: 44)
                    .offset(y: 22)

                Circle()
                    .fill(.cyan)
                    .frame(width: 22, height: 22)

                // 12-o'clock yellow center marker
                Rectangle()
                    .fill(.yellow)
                    .frame(width: 6, height: 12)
                    .offset(y: -46)
            }
            .rotationEffect(.degrees(Double(wheelSteer) * maxWheelDegrees))
            .animation(.interactiveSpring(response: 0.24, dampingFraction: 0.92), value: wheelSteer)
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let clamped = max(-maxDragWidth, min(maxDragWidth, value.translation.width))
                        wheelSteer = Float(clamped / maxDragWidth)
                    }
                    .onEnded { _ in
                        withAnimation(.interactiveSpring(response: 0.26, dampingFraction: 0.95)) {
                            wheelSteer = 0
                        }
                    }
            )

            Text("SPORT STEERING • 5.2M RADIUS")
                .font(.caption2.bold())
                .foregroundStyle(.white)
        }
        .padding(10)
        .background(.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
struct SpeedButtonsView: View {
    @Binding var throttle: Float // 0.0 (zero speed) ... 1.0 (max speed)

    private let stepCount: Float = 10 // each press changes the set speed by 10% (about 15 MPH)
    private let baseMaxSpeedMps: Float = 68.0 // matches the player's top speed

    private var clampedThrottle: Float {
        max(0, min(1, throttle))
    }

    var body: some View {
        VStack(spacing: 8) {
            speedButton(systemName: "plus", label: "Increase speed", color: .green, delta: 1)
                .disabled(clampedThrottle >= 1)

            Text("SET \(Int((clampedThrottle * baseMaxSpeedMps * 2.23694).rounded())) MPH")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            speedButton(systemName: "minus", label: "Decrease speed", color: .orange, delta: -1)
                .disabled(clampedThrottle <= 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func speedButton(systemName: String, label: String, color: Color, delta: Float) -> some View {
        Button {
            // Work in whole steps so repeated presses land exactly on 0 and max
            let step = (clampedThrottle * stepCount).rounded() + delta
            throttle = max(0, min(1, step / stepCount))
        } label: {
            Image(systemName: systemName)
                .font(.system(size: 24, weight: .heavy))
                .foregroundStyle(.white)
                .frame(width: 64, height: 52)
                .background(color.opacity(0.85))
                .clipShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonRepeatBehavior(.enabled) // press and hold to keep changing speed
        .accessibilityLabel(label)
    }
}
