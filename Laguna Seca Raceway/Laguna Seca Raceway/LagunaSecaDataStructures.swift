import Foundation
import SceneKit
import simd
import SwiftUI

struct NavigationTrajectorySpline {
    let controlPoints: [SIMD3<Float>]
    let sampledPoints: [SIMD3<Float>]

    var lookaheadPoint: SIMD3<Float> {
        guard !sampledPoints.isEmpty else { return .zero }
        let idx = min(sampledPoints.count - 1, max(1, sampledPoints.count / 2))
        return sampledPoints[idx]
    }

    /// Generates a smooth forward trajectory spline by combining track geometry,
    /// road curvature, and lateral clearance away from perceived nearby cars.
    static func build(
        from currentPos: SIMD3<Float>,
        currentLateralOffset: Float,
        distanceAlong: Float,
        curvature: Float,
        trackHalfWidth: Float,
        spline: LagunaSecaTrackBuilder.TrackSpline,
        allPositions: [SIMD3<Float>],
        agentIDs: [String],
        ownAgentID: String
    ) -> NavigationTrajectorySpline {
        let horizonOffsets: [Float] = [0.0, 7.0, 15.0, 25.0, 36.0]
        let maxSafeLateral = max(2.0, trackHalfWidth - 1.2)
        var rawControls: [SIMD3<Float>] = [currentPos]

        for (stepIdx, lookDist) in horizonOffsets.enumerated() where stepIdx > 0 {
            let frame = spline.frame(atDistance: distanceAlong + lookDist)
            let centerSample = spline.pointAt(distance: distanceAlong + lookDist)

            // Start near current lateral offset and blend toward inside apex or centerline
            let blendToRoad = min(1.0, Float(stepIdx) * 0.35)
            let apexBias: Float = abs(curvature) > 0.015
                ? (curvature < 0 ? -1.4 : 1.4)
                : 0.0
            let desiredRoadLateral = max(
                -maxSafeLateral,
                min(maxSafeLateral, apexBias)
            )
            var desiredLateral = currentLateralOffset * (1.0 - blendToRoad) + desiredRoadLateral * blendToRoad

            // Repel laterally from nearby perceived cars along the forward horizon
            for (idx, otherPos) in allPositions.enumerated() {
                guard agentIDs.indices.contains(idx), agentIDs[idx] != ownAgentID else { continue }
                let toOther = otherPos - centerSample
                let alongDelta = simd_dot(SIMD3<Float>(toOther.x, 0, toOther.z), frame.forward)
                let lateralDelta = simd_dot(SIMD3<Float>(toOther.x, 0, toOther.z), frame.right)

                // Affect horizon points near or slightly ahead of perceived vehicles
                let longitudinalWindow: Float = 14.0
                if abs(alongDelta - lookDist) < longitudinalWindow || (alongDelta > -4.0 && alongDelta < lookDist + 8.0) {
                    let longitudinalProximity = max(0.0, 1.0 - abs(alongDelta - lookDist) / longitudinalWindow)
                    let avoidanceBand: Float = 4.2
                    if abs(lateralDelta) < avoidanceBand && longitudinalProximity > 0.05 {
                        let pushDir: Float = lateralDelta >= 0 ? -1.0 : 1.0
                        let pushStrength = (1.0 - abs(lateralDelta) / avoidanceBand) * longitudinalProximity * 3.8
                        desiredLateral += pushDir * pushStrength
                    }
                }
            }

            desiredLateral = max(-maxSafeLateral, min(maxSafeLateral, desiredLateral))
            let pt = SIMD3<Float>(
                centerSample.x + frame.right.x * desiredLateral,
                centerSample.y + 0.06,
                centerSample.z + frame.right.z * desiredLateral
            )
            rawControls.append(pt)
        }

        let smoothed = sampleOpenCatmullRom(rawControls, stepsPerSegment: 6)
        return NavigationTrajectorySpline(controlPoints: rawControls, sampledPoints: smoothed)
    }

    private static func sampleOpenCatmullRom(_ pts: [SIMD3<Float>], stepsPerSegment: Int) -> [SIMD3<Float>] {
        guard pts.count >= 2 else { return pts }
        var result: [SIMD3<Float>] = []
        let last = pts.count - 1

        for i in 0..<last {
            let p0 = i > 0 ? pts[i - 1] : (pts[i] * 2.0 - pts[i + 1])
            let p1 = pts[i]
            let p2 = pts[i + 1]
            let p3 = (i + 2) <= last ? pts[i + 2] : (pts[i + 1] * 2.0 - pts[i])

            for s in 0..<stepsPerSegment {
                let t = Float(s) / Float(stepsPerSegment)
                let t2 = t * t
                let t3 = t2 * t
                let pt = 0.5 * (
                    (2.0 * p1) +
                    (-p0 + p2) * t +
                    (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3) * t2 +
                    (-p0 + 3.0 * p1 - 3.0 * p2 + p3) * t3
                )
                result.append(pt)
            }
        }
        result.append(pts[last])
        return result
    }
}



struct LagunaSecaRaceSceneRepresentable: UIViewRepresentable {
    @Binding var thumbInput: ThumbInputState
    @Binding var animationSpeed: Double
    @Binding var resetCounter: Int
    @Binding var telemetry: [RaceCarTelemetry]
    @Binding var caGeneration: Int
    @Binding var caLiveCells: Int
    @Binding var elapsedTime: TimeInterval

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

        coord.onTelemetryUpdate = { items, gen, live, elapsed in
            self.telemetry = items
            self.caGeneration = gen
            self.caLiveCells = live
            self.elapsedTime = elapsed
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


struct RaceCarTelemetry: Identifiable, Equatable {
    let id: String
    let name: String
    let role: RaceCarRole
    let lap: Int
    let totalLaps: Int
    let positionRank: Int
    let speedMph: Int
    let energyPercent: Int
    let missionPhase: String
    let caGeneration: Int
    let caLiveCells: Int
    let dirtyStatesCount: Int
    let lastAction: String
    let decisionNote: String
}

extension SIMD3 where Scalar == Float {
    init(_ vec: SCNVector3) {
        self.init(Float(vec.x), Float(vec.y), Float(vec.z))
    }
}

extension SCNVector3 {
    init(_ v: SIMD3<Float>) {
        self.init(CGFloat(v.x), CGFloat(v.y), CGFloat(v.z))
    }
}

enum RaceAction: Int, CaseIterable, Codable {
    case accelerate
    case hardBrake
    case steerLeftHard
    case steerLeftSoft
    case steerRightSoft
    case steerRightHard
    case apexCut
    case defendLine
}

enum RaceCarRole: String, Codable {
    case firstPersonPlayer
    case caAgent
}

enum VehicleMissionPhase: String, Codable {
    case energyReplenish
    case raceProgression
    case completionOrCruise
}

struct MissionGoalItem: Identifiable, Equatable {
    let id: String
    let phase: VehicleMissionPhase
    let subGoal: String
    let targetDistanceAlongTrack: Float?
    let prescribedAction: RaceAction?
    var isTacticalOverride: Bool = false
}

struct TrackedObjectMemoryEntry: Identifiable {
    let id: String
    var position: SIMD3<Float>
    var radius: Float
    var lastSeenTime: TimeInterval
    var verifiedClearCount: Int = 0
}

struct TrackSample {
    var distanceAlongTrack: Float = 0
    var lateralOffset: Float = 0          // 0 = center, negative = left, positive = right
    var trackHalfWidth: Float = 5.5
    var curvature: Float = 0              // signed turn sharpness ahead
    var elevationDeltaAhead: Float = 0    // e.g. Corkscrew drop
    var nearestCarDistance: Float = .infinity
    var nearestCarBearing: Float = 0
    var offTrackRisk: Float = 0
    var lapProgress: Float = 0
}

struct RacePerception {
    var carID: String
    var role: RaceCarRole
    var speed: Float
    var maxSpeed: Float
    var energyReserve: Float
    var isRecharging: Bool
    var headingError: Float
    var lateralOffset: Float
    var trackHalfWidth: Float
    var curvatureAhead: Float
    var elevationDropAhead: Float
    var pathDistanceAhead: Float
    var detourActive: Bool
    var progressRate: Float
    var nearestOpponentDistance: Float
    var nearestOpponentLateralDelta: Float
    var rememberedObstacleCount: Int
    var activeMissionPhase: VehicleMissionPhase
    var activeSubGoal: String
    var prescribedAction: RaceAction?
    var lap: Int
    var progressInLap: Float
    var totalRaceProgress: Float
    var stateKey: String
    var timestamp: TimeInterval
}

struct OutcomeEvaluationWindow {
    var startTime: TimeInterval
    var startPosition: SIMD3<Float>
    var startTrackDistance: Float
    var startTotalProgress: Float
    var lastStateKey: String
    var lastAction: RaceAction
    var headingErrorSum: Float = 0
    var headingErrorSamples: Int = 0
    var offTrackSamples: Int = 0
    var collisionEvents: Int = 0
    var stallDuration: TimeInterval = 0
}

struct ThumbInputState {
    /// 0.0 to +1.0 when sliding left thumb down (turns wheel left)
    var leftThumbDown: Float = 0
    /// 0.0 to +1.0 when sliding right thumb down (turns wheel right)
    var rightThumbDown: Float = 0
    /// -1.0 (full left thumb left) to +1.0 (full left thumb right)
    var leftThumbX: Float = 0
    /// -1.0 (pull down = brake) to +1.0 (push up = slight reverse/tuck)
    var leftThumbY: Float = 0
    /// 0.0 to +1.0 throttle trigger controlled by right thumb
    var rightThumbThrottle: Float = 0
    /// -1.0 to +1.0 optional right thumb yaw/look assist
    var rightThumbSteerAssist: Float = 0
    /// Boost / KERS trigger
    var boostEngaged: Bool = false

    /// +1.0 = full left turn (left thumb down), -1.0 = full right turn (right thumb down)
    var steeringWheelInput: Float {
        let downDelta = leftThumbDown - rightThumbDown
        let combined = abs(downDelta) > 0.01 ? downDelta : leftThumbX
        return max(-1.0, min(1.0, combined))
    }
}
