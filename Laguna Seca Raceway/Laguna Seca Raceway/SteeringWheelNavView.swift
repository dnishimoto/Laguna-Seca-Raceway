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

    private let maxDragWidth: CGFloat = 68
    // Porsche 911 GT3 rack: ~2.28 turns lock-to-lock (±410 degrees)
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

                // Porsche GT3 12-o'clock yellow center marker
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

            Text("GT3 STEERING • 5.2M RADIUS")
                .font(.caption2.bold())
                .foregroundStyle(.white)
        }
        .padding(10)
        .background(.black.opacity(0.45))
        .clipShape(RoundedRectangle(cornerRadius: 16))
    }
}
struct SpeedSliderView: View {
    @Binding var throttle: Float // 0.0 (zero speed) ... 1.0 (max speed)

    private let trackHeight: CGFloat = 136
    private let baseMaxSpeedMps: Float = 68.0 // matches the player's top speed

    private var clampedThrottle: Float {
        max(0, min(1, throttle))
    }

    private var thumbOffsetY: CGFloat {
        // Top of track = 1.0 (max speed), bottom of track = 0.0 (zero)
        let span = trackHeight - 32
        return CGFloat(1.0 - clampedThrottle) * span - (span * 0.5)
    }

    var body: some View {
        VStack(spacing: 6) {
            Text("MAX")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.green)

            ZStack(alignment: .bottom) {
                Capsule()
                    .fill(.white.opacity(0.18))
                    .frame(width: 12, height: trackHeight)

                Capsule()
                    .fill(.green.opacity(0.8))
                    .frame(width: 12, height: max(8, CGFloat(clampedThrottle) * trackHeight))

                Circle()
                    .fill(.green)
                    .frame(width: 32, height: 32)
                    .shadow(radius: 4)
                    .offset(y: thumbOffsetY)
            }
            .frame(width: 56, height: trackHeight + 24)
            .contentShape(Rectangle())
            .gesture(
                DragGesture(minimumDistance: 0)
                    .onChanged { value in
                        let span = max(1, trackHeight - 32)
                        let topY = -(span * 0.5)
                        let bottomY = span * 0.5
                        let localY = max(topY, min(bottomY, value.location.y - ((trackHeight + 24) * 0.5)))
                        let ratio = Float((bottomY - localY) / span)
                        throttle = max(0, min(1, ratio))
                    }
                    // Intentionally no snap-back in onEnded so speed holds at chosen level
            )

            Text("0")
                .font(.system(size: 9, weight: .bold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.8))

            Text("\(Int((clampedThrottle * baseMaxSpeedMps * 2.23694).rounded())) MPH")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}
