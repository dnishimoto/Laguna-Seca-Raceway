import SwiftUI
import SceneKit
import simd

struct LagunaSecaRaceSceneRepresentable: UIViewRepresentable {
    @Binding var thumbInput: ThumbInputState
    @Binding var animationSpeed: Double
    @Binding var resetCounter: Int
    @Binding var telemetry: [RaceCarTelemetry]
    @Binding var caGeneration: Int
    @Binding var caLiveCells: Int

    final class Holder {
        var coordinator: LagunaSecaRaceCoordinator?
        var lastResetCounter: Int = 0
    }

    func makeCoordinator() -> Holder {
        Holder()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.55, green: 0.74, blue: 0.92, alpha: 1.0)

        let spline = LagunaSecaTrackBuilder.makeLagunaSecaSpline()
        LagunaSecaTrackBuilder.buildTrack(in: scene, spline: spline)

        let ambient = SCNNode()
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 550
        ambient.light = ambientLight
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        let sunLight = SCNLight()
        sunLight.type = .directional
        sunLight.intensity = 1100
        sunLight.castsShadow = true
        sun.light = sunLight
        sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
        scene.rootNode.addChildNode(sun)

        let coord = LagunaSecaRaceCoordinator(scene: scene, spline: spline)
        coord.animationSpeed = animationSpeed
        coord.onTelemetryUpdate = { items, gen, live in
            self.telemetry = items
            self.caGeneration = gen
            self.caLiveCells = live
        }

        context.coordinator.coordinator = coord
        view.scene = scene
        if let fpCam = scene.rootNode.childNode(withName: "FirstPersonDriverCamera", recursively: true) {
            view.pointOfView = fpCam
        }
        view.delegate = coord
        view.isPlaying = true
        view.rendersContinuously = true
        view.allowsCameraControl = false

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let coord = context.coordinator.coordinator else { return }
        coord.thumbInput = thumbInput
        coord.animationSpeed = animationSpeed

        if resetCounter != context.coordinator.lastResetCounter {
            context.coordinator.lastResetCounter = resetCounter
            coord.resetRace()
            if let fpCam = uiView.scene?.rootNode.childNode(withName: "FirstPersonDriverCamera", recursively: true) {
                uiView.pointOfView = fpCam
            }
        }
    }
}

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
    private let baseMaxSpeedMps: Float = 28.0

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

            Text("\(Int((clampedThrottle * baseMaxSpeedMps * 3.6).rounded())) KM/H")
                .font(.system(size: 10, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .background(.black.opacity(0.5))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

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
                                Text("\(car.speedKmh) km/h")
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
                            Text("\(player.speedKmh) KM/H")
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
