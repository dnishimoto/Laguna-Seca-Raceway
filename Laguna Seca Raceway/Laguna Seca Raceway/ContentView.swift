/*
 The racing controller’s perception system can support a broad range of racing situations because it combines vehicle speed, track curvature, heading error, lateral position, nearest-opponent distance, opponent lateral position, elevation changes, race progress, and recharge status. These inputs allow the controller to recognize many important conditions affecting how the vehicle should accelerate, brake, steer, recover, and position itself. However, the current code represents nearby traffic primarily through the nearest opponent’s distance and lateral offset. It does not yet contain a complete multi-vehicle collision perception system, so pile-ups and complex traffic situations should be described as scenarios the architecture can help address, rather than hazards it has already been proven to detect and avoid.&#x20;


 The controller can recognize and respond to **high-speed approach situations** by combining vehicle speed, heading error, track curvature, opponent distance, and lateral position. When an opponent is close and the vehicle is traveling quickly, the advisory logic can favor braking. When a severe turn or elevation drop is ahead, it can reduce acceleration preference and favor braking or steering adjustments. This helps the AI avoid entering a difficult section of track at excessive speed. The short-horizon rollout adds another layer by evaluating candidate actions over the next few steps rather than choosing only from past rewards.

 In **side-by-side racing**, the nearest opponent distance and lateral difference provide information about whether another vehicle is close and which side it occupies. The controller can use that information when considering steering, defending a line, or braking. Its action set includes soft and hard steering in both directions, braking, acceleration, apex cutting, and line defense. This gives it several possible responses to traffic instead of relying on a single steering behavior. The current implementation also includes a tactical recovery condition when the vehicle is near the track edge or an opponent is very close with little lateral separation.

 In **pile-ups and blocked-track situations**, the controller could use the perception grid to represent a sudden reduction in available space, nearby vehicles, and changing track conditions. If the nearest opponent becomes very close, the system can favor braking and evaluate alternative steering actions. If the vehicle’s progress stalls at low speed, the stall detector can trigger a temporary recovery action. This could help the AI escape a slow or obstructed situation, but the current perception does not identify a pile-up as a distinct event or map every blocked lane. It only receives nearest-opponent information, so it may not know whether a safe escape route exists between multiple vehicles.

 In **high-speed collision avoidance**, the most important principle is to evaluate the time and space available to respond, not distance alone. A vehicle traveling quickly needs more stopping distance and more time to complete a lane change. The current controller uses speed and opponent distance in its advisory logic, but it does not explicitly calculate time-to-collision, relative closing speed, braking distance, or predicted collision overlap. Those would be valuable additions. With them, the perception system could estimate whether the opponent is moving away, maintaining distance, or rapidly closing, then compare braking and steering options against the remaining safe space.

 The system can also respond to **track-edge danger, sharp turns, elevation drops, heading errors, and loss of progress**. Track curvature and heading error help identify difficult turns; lateral offset helps detect when the vehicle is approaching the edge; elevation-drop perception can discourage acceleration into a steep descent; and progress monitoring can detect when the vehicle is no longer advancing. These signals work together so that the controller can choose recovery or caution actions while continuing to learn from the result.

 The learning architecture makes these scenarios increasingly useful over repeated runs. When the controller encounters a close pass, a difficult turn, a near-edge recovery, or a braking decision, the outcome can update its Q-values, experience memory, and trajectory confidence. Later, when it encounters a similar encoded state, it can use that history alongside current perception and short-horizon prediction. The retained memory after a race reset allows lessons from earlier runs to influence later races.

 To make pile-up avoidance and high-speed safety substantially stronger, the next perception upgrade should track **multiple opponents simultaneously**, including each vehicle’s relative position, relative speed, direction, and predicted path. It should also identify free space, blocked lanes, track boundaries, and safe escape corridors. The controller could then estimate time-to-collision and stopping distance, predict several possible traffic movements, and apply a safety filter that rejects actions likely to cause a collision before the learning system ranks the remaining choices.

 This would make the architecture more than a controller that reacts to the nearest opponent. It would become a traffic-aware racing intelligence that understands how the surrounding vehicles are moving, anticipates dangerous interactions, and selects actions that preserve a safe route while still pursuing race progress. The existing system provides a useful foundation through structured perception, memory, action evaluation, and tactical overrides, but reliable collision avoidance—especially at high speed and in multi-car pile-ups—requires the additional multi-object tracking and predictive safety mechanisms described above.
 */
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
