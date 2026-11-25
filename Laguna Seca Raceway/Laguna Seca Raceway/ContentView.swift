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
        ambient.light = SCNLight()
        ambient.light?.type = .ambient
        ambient.light?.intensity = 550
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        sun.light = SCNLight()
        sun.light?.type = .directional
        sun.light?.intensity = 1100
        sun.light?.castsShadow = true
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

struct DualThumbPadView: View {
    let title: String
    let subtitle: String
    let accent: Color
    let onDragChanged: (CGPoint, CGSize) -> Void
    let onDragEnded: () -> Void

    @State private var knobOffset: CGSize = .zero

    var body: some View {
        VStack(spacing: 4) {
            GeometryReader { geo in
                let radius = min(geo.size.width, geo.size.height) * 0.36
                ZStack {
                    Circle()
                        .fill(.ultraThinMaterial)
                        .overlay(Circle().stroke(accent.opacity(0.65), lineWidth: 2))

                    Circle()
                        .fill(accent.opacity(0.85))
                        .frame(width: radius * 0.9, height: radius * 0.9)
                        .offset(knobOffset)
                        .shadow(radius: 4)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .gesture(
                    DragGesture(minimumDistance: 0)
                        .onChanged { value in
                            let maxR = radius
                            let dx = max(-maxR, min(maxR, value.translation.width))
                            let dy = max(-maxR, min(maxR, value.translation.height))
                            knobOffset = CGSize(width: dx, height: dy)
                            onDragChanged(value.location, CGSize(width: dx / maxR, height: dy / maxR))
                        }
                        .onEnded { _ in
                            withAnimation(.interactiveSpring(response: 0.2, dampingFraction: 0.7)) {
                                knobOffset = .zero
                            }
                            onDragEnded()
                        }
                )
            }
            .frame(width: 124, height: 124)

            Text(title)
                .font(.caption2.bold())
            Text(subtitle)
                .font(.system(size: 10))
                .foregroundStyle(.secondary)
        }
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
                    DualThumbPadView(
                        title: "LEFT THUMB",
                        subtitle: "Steer L/R • Down Brake",
                        accent: .cyan,
                        onDragChanged: { _, norm in
                            thumbInput.leftThumbX = Float(norm.width)
                            thumbInput.leftThumbY = Float(norm.height)
                        },
                        onDragEnded: {
                            thumbInput.leftThumbX = 0
                            thumbInput.leftThumbY = 0
                        }
                    )

                    Spacer()

                    VStack(spacing: 8) {
                        Button {
                            thumbInput.boostEngaged.toggle()
                        } label: {
                            Text(thumbInput.boostEngaged ? "BOOST ON" : "BOOST")
                                .font(.caption2.bold())
                                .padding(.horizontal, 12)
                                .padding(.vertical, 6)
                                .background(thumbInput.boostEngaged ? Color.orange : Color.black.opacity(0.6))
                                .foregroundStyle(.white)
                                .clipShape(Capsule())
                        }

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

                    DualThumbPadView(
                        title: "RIGHT THUMB",
                        subtitle: "Push Up = Gas",
                        accent: .green,
                        onDragChanged: { _, norm in
                            let throttle = max(0, min(1, Float(-norm.height)))
                            thumbInput.rightThumbThrottle = throttle
                            thumbInput.rightThumbSteerAssist = Float(norm.width)
                        },
                        onDragEnded: {
                            thumbInput.rightThumbThrottle = 0
                            thumbInput.rightThumbSteerAssist = 0
                        }
                    )
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 16)
            }
        }
    }
}


