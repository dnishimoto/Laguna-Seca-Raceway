import SwiftUI
import SceneKit
import simd


struct ContentView: View {
    @State private var thumbInput = ThumbInputState()
    @State private var animationSpeed: Double = 1.0
    @State private var resetCounter: Int = 0
    @State private var telemetry: [RaceCarTelemetry] = []
    @State private var caGeneration: Int = 0
    @State private var caLiveCells: Int = 0

    var body: some View {
        ZStack {
            LagunaSecaRaceSceneRepresentable(
                thumbInput: $thumbInput,
                animationSpeed: $animationSpeed,
                resetCounter: $resetCounter,
                telemetry: $telemetry,
                caGeneration: $caGeneration,
                caLiveCells: $caLiveCells
            )
            .ignoresSafeArea()

            VStack(spacing: 0) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("LAGUNA SECA • 1ST PERSON CA RACE")
                            .font(.caption.bold())
                            .foregroundStyle(.white)
                        ForEach(telemetry) { car in
                            HStack(spacing: 6) {
                                Text("P\(car.positionRank)")
                                    .font(.system(size: 11, weight: .bold, design: .monospaced))
                                    .foregroundStyle(car.role == .firstPersonPlayer ? .cyan : .yellow)
                                Text(car.name)
                                    .font(.system(size: 11, weight: .medium))
                                    .foregroundStyle(.white)
                                Spacer(minLength: 8)
                                Text("\(car.speedMph) mph")
                                    .font(.system(size: 11, design: .monospaced))
                                    .foregroundStyle(.white.opacity(0.85))
                            }
                        }
                    }
                    .padding(10)
                    .frame(maxWidth: 250)
                    .background(.black.opacity(0.55))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                    Spacer()

                    VStack(alignment: .trailing, spacing: 6) {
                        Button {
                            resetCounter += 1
                        } label: {
                            Label("Reset", systemImage: "arrow.counterclockwise")
                                .font(.caption.bold())
                        }
                        .buttonStyle(.borderedProminent)

                        if let player = telemetry.first(where: { $0.role == .firstPersonPlayer }) {
                            LapTimerView(timer: player.lapTimer)
                        }

                        VStack(alignment: .trailing, spacing: 2) {
                            Text("CA Gen: \(caGeneration)")
                            Text("Live Cells: \(caLiveCells)")
                        }
                        .font(.system(size: 11, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white)
                        .padding(8)
                        .background(.black.opacity(0.55))
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()

                Spacer()

                HStack(alignment: .bottom) {
                    VStack(spacing: 8) {
                        SpeedSliderView(throttle: $thumbInput.rightThumbThrottle)

                        Text("BRAKE")
                            .font(.caption.bold())
                            .padding(.horizontal, 14)
                            .padding(.vertical, 10)
                            .background(thumbInput.leftThumbY < -0.1 ? Color.red : Color.black.opacity(0.65))
                            .foregroundStyle(.white)
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                            .gesture(
                                DragGesture(minimumDistance: 0)
                                    .onChanged { _ in thumbInput.leftThumbY = -1.0 }
                                    .onEnded { _ in thumbInput.leftThumbY = 0.0 }
                            )
                    }

                    Spacer()

                    VStack(spacing: 8) {
                        SteeringWheelNavView(wheelSteer: $thumbInput.leftThumbX)

                        if let player = telemetry.first(where: { $0.role == .firstPersonPlayer }) {
                            Text("\(player.speedMph) MPH")
                                .font(.headline.monospacedDigit())
                                .foregroundStyle(.white)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(.black.opacity(0.6))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }
                    }

                    Spacer()

                    Button {
                        thumbInput.boostEngaged.toggle()
                    } label: {
                        Text(thumbInput.boostEngaged ? "BOOST ON" : "BOOST")
                            .font(.caption2.bold())
                            .padding(.horizontal, 12)
                            .padding(.vertical, 8)
                            .background(thumbInput.boostEngaged ? Color.orange : Color.black.opacity(0.65))
                            .foregroundStyle(.white)
                            .clipShape(Capsule())
                    }
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }
}
