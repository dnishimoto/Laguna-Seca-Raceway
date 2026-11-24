import Foundation
import SceneKit
import UIKit
import simd

final class LagunaSecaRaceCoordinator: NSObject, SCNSceneRendererDelegate {

    struct RaceAgent {
        let id: String
        let name: String
        let role: RaceCarRole
        let node: SCNNode
        let ca: LagunaSecaCA?

        var distanceAlongTrack: Float = 0
        var lastTrackDistance: Float = 0
        var lap: Int = 1
        var totalProgress: Float = 0
        var speed: Float = 0
        var heading: Float = 0
        var steeringAngle: Float = 0
        var lastActionText: String = "Ready"
        var lastStateKey: String = "init"
        var lastAction: RaceAction = .accelerate
        var caTickAccumulator: TimeInterval = 0
    }

    private weak var scene: SCNScene?
    private(set) var spline: LagunaSecaTrackBuilder.TrackSpline
    private(set) var agents: [RaceAgent] = []
    private weak var playerCameraNode: SCNNode?

    var thumbInput = ThumbInputState()
    var animationSpeed: Double = 1.0
    var isRunning: Bool = true
    var totalLaps: Int = 3

    private var lastFrameTime: TimeInterval = 0
    private var lastTelemetryTime: TimeInterval = 0
    private let telemetryInterval: TimeInterval = 0.12

    var onTelemetryUpdate: (([RaceCarTelemetry], Int, Int) -> Void)?

    init(scene: SCNScene, spline: LagunaSecaTrackBuilder.TrackSpline) {
        self.scene = scene
        self.spline = spline
        super.init()
        setupCars(in: scene)
    }

    func setupCars(in scene: SCNScene) {
        for agent in agents {
            agent.node.removeFromParentNode()
        }
        agents.removeAll()

        let configs: [(id: String, name: String, role: RaceCarRole, startDist: Float, lateral: Float, color: UIColor, accent: UIColor, caSeed: Int?)] = [
            ("player", "You (1st Person)", .firstPersonPlayer, 12.0, -2.2, UIColor.systemBlue, UIColor.cyan, nil),
            ("ca-1",   "CA Racer #1",      .caAgent,            8.0,  2.2, UIColor.systemRed, UIColor.yellow, 1),
            ("ca-2",   "CA Racer #2",      .caAgent,            4.0, -2.2, UIColor.systemGreen, UIColor.white, 2),
            ("ca-3",   "CA Racer #3",      .caAgent,            0.0,  2.2, UIColor.systemOrange, UIColor.black, 3)
        ]

        for cfg in configs {
            let built = LagunaSecaTrackBuilder.makeRaceCarNode(
                name: cfg.name,
                role: cfg.role,
                bodyColor: cfg.color,
                accentColor: cfg.accent
            )

            let sample = spline.sample(atDistance: cfg.startDist)
            let flatTangent = simd_normalize(SIMD3<Float>(sample.tangent.x, 0, sample.tangent.z))
            let rightVec = SIMD3<Float>(-flatTangent.z, 0, flatTangent.x)
            let startPos = sample.position + rightVec * cfg.lateral

            built.root.position = SCNVector3(startPos)
            let yaw = atan2(-flatTangent.x, -flatTangent.z)
            built.root.eulerAngles = SCNVector3(0, yaw, 0)
            scene.rootNode.addChildNode(built.root)

            if cfg.role == .firstPersonPlayer {
                playerCameraNode = built.cockpitCamera
            }

            let caInstance = cfg.caSeed.map { LagunaSecaCA(seedOffset: $0) }
            var agent = RaceAgent(
                id: cfg.id,
                name: cfg.name,
                role: cfg.role,
                node: built.root,
                ca: caInstance
            )
            agent.distanceAlongTrack = cfg.startDist
            agent.lastTrackDistance = cfg.startDist
            agent.totalProgress = cfg.startDist
            agent.heading = yaw
            agents.append(agent)
        }
    }

    func resetRace() {
        lastFrameTime = 0
        lastTelemetryTime = 0
        guard let scene else { return }
        setupCars(in: scene)
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        guard isRunning, let scene else { return }
        scene.physicsWorld.speed = CGFloat(animationSpeed)

        let rawDt: Float = lastFrameTime == 0
            ? 1.0 / 60.0
            : Float(min(max(time - lastFrameTime, 1.0 / 240.0), 0.05))
        lastFrameTime = time
        let dt = rawDt * Float(animationSpeed)
        guard dt > 0 else { return }

        let positions = agents.map { SIMD3<Float>($0.node.position) }

        for i in agents.indices {
            let nearest = nearestOpponentInfo(forIndex: i, allPositions: positions)
            let currentWorld = SIMD3<Float>(agents[i].node.position)
            let trackInfo = spline.closestTrackInfo(to: currentWorld)

            let desiredYaw = atan2(-trackInfo.tangent.x, -trackInfo.tangent.z)
            let headingError = wrappedAngle(desiredYaw - agents[i].heading)

            if agents[i].role == .firstPersonPlayer {
                updateFirstPersonPlayer(
                    agent: &agents[i],
                    trackInfo: trackInfo,
                    nearestOpponent: nearest,
                    dt: dt
                )
            } else {
                updateCAAgent(
                    agent: &agents[i],
                    trackInfo: trackInfo,
                    headingError: headingError,
                    nearestOpponent: nearest,
                    dt: dt,
                    time: time
                )
            }

            updateLapAndProgress(agent: &agents[i], trackInfo: trackInfo)
        }

        resolveCarToCarSpacing()

        if time - lastTelemetryTime >= telemetryInterval {
            lastTelemetryTime = time
            publishTelemetry()
        }
    }

    private func nearestOpponentInfo(forIndex idx: Int, allPositions: [SIMD3<Float>]) -> (distance: Float, lateralDelta: Float) {
        let me = allPositions[idx]
        var bestDist: Float = .infinity
        var bestLat: Float = 0

        for j in allPositions.indices where j != idx {
            let d = simd_distance(me, allPositions[j])
            if d < bestDist {
                bestDist = d
                bestLat = allPositions[j].x - me.x
            }
        }
        return (bestDist, bestLat)
    }

    private func updateFirstPersonPlayer(
        agent: inout RaceAgent,
        trackInfo: (distanceAlong: Float, lateralOffset: Float, trackCenter: SIMD3<Float>, tangent: SIMD3<Float>, curvature: Float, elevationDeltaAhead: Float),
        nearestOpponent: (distance: Float, lateralDelta: Float),
        dt: Float
    ) {
        let steerInput = max(-1, min(1, thumbInput.leftThumbX))
        let maxSteerRate: Float = 2.35
        agent.steeringAngle += (steerInput * maxSteerRate - agent.steeringAngle) * min(1, dt * 14)

        let brakeAmount = max(0, -thumbInput.leftThumbY)
        let reverseAmount = max(0, thumbInput.leftThumbY)
        let boostMult: Float = thumbInput.boostEngaged ? 1.28 : 1.0

        let maxForwardSpeed: Float = 28.0 * boostMult
        let accelRate: Float = 16.0 * boostMult
        let brakeRate: Float = 24.0
        let drag: Float = 2.8

        if thumbInput.rightThumbThrottle > 0.02 {
            agent.speed += thumbInput.rightThumbThrottle * accelRate * dt
        } else if reverseAmount > 0.1 && agent.speed < 0.5 {
            agent.speed -= reverseAmount * 8.0 * dt
        } else {
            agent.speed -= agent.speed * drag * dt
        }

        if brakeAmount > 0.02 {
            agent.speed = max(-6.0, agent.speed - brakeAmount * brakeRate * dt)
        }

        agent.speed = max(-6.0, min(maxForwardSpeed, agent.speed))

        let speedTurnFactor = min(1.0, max(0.35, abs(agent.speed) / 8.0))
        let reverseSign: Float = agent.speed >= -0.05 ? 1.0 : -1.0
        agent.heading = wrappedAngle(agent.heading - agent.steeringAngle * speedTurnFactor * reverseSign * dt)

        if abs(trackInfo.lateralOffset) > LagunaSecaTrackBuilder.trackHalfWidth + 0.3 {
            agent.speed *= powf(0.55, dt)
        }

        let forward = SIMD3<Float>(-sin(agent.heading), 0, -cos(agent.heading))
        var nextPos = SIMD3<Float>(agent.node.position) + forward * agent.speed * dt

        let updatedTrack = spline.closestTrackInfo(to: nextPos)
        let targetY = updatedTrack.trackCenter.y + 0.06
        nextPos.y += (targetY - nextPos.y) * min(1, dt * 16)

        agent.node.position = SCNVector3(nextPos)
        agent.node.eulerAngles = SCNVector3(0, agent.heading, -agent.steeringAngle * 0.08)

        if let cam = playerCameraNode {
            cam.eulerAngles = SCNVector3(-0.04, -agent.steeringAngle * 0.16, -agent.steeringAngle * 0.05)
        }

        if thumbInput.boostEngaged {
            agent.lastActionText = "Thumb Boost"
        } else if brakeAmount > 0.25 {
            agent.lastActionText = "Thumb Brake"
        } else if abs(steerInput) > 0.15 {
            agent.lastActionText = steerInput < 0 ? "Thumb Steer L" : "Thumb Steer R"
        } else if thumbInput.rightThumbThrottle > 0.1 {
            agent.lastActionText = "Thumb Throttle"
        } else {
            agent.lastActionText = "Coast"
        }
    }

    private func updateCAAgent(
        agent: inout RaceAgent,
        trackInfo: (distanceAlong: Float, lateralOffset: Float, trackCenter: SIMD3<Float>, tangent: SIMD3<Float>, curvature: Float, elevationDeltaAhead: Float),
        headingError: Float,
        nearestOpponent: (distance: Float, lateralDelta: Float),
        dt: Float,
        time: TimeInterval
    ) {
        guard let ca = agent.ca else { return }

        agent.caTickAccumulator += TimeInterval(dt)
        if agent.caTickAccumulator >= 0.18 {
            agent.caTickAccumulator = 0
            ca.step()
        }

        let latBand = trackInfo.lateralOffset < -1.5 ? "L" : (trackInfo.lateralOffset > 1.5 ? "R" : "C")
        let curveBand = abs(trackInfo.curvature) > 0.03 ? "sharp" : "straight"
        let stateKey = "\(latBand)|\(curveBand)|\(Int(agent.speed / 6))"

        let perception = RacePerception(
            carID: agent.id,
            role: .caAgent,
            speed: agent.speed,
            maxSpeed: 24.5,
            headingError: headingError,
            lateralOffset: trackInfo.lateralOffset,
            trackHalfWidth: LagunaSecaTrackBuilder.trackHalfWidth,
            curvatureAhead: trackInfo.curvature,
            elevationDropAhead: trackInfo.elevationDeltaAhead,
            nearestOpponentDistance: nearestOpponent.distance,
            nearestOpponentLateralDelta: nearestOpponent.lateralDelta,
            lap: agent.lap,
            progressInLap: trackInfo.distanceAlong / max(1, spline.totalLength),
            totalRaceProgress: agent.totalProgress,
            stateKey: stateKey,
            timestamp: time
        )

        let action = ca.decideAction(perception: perception)

        var targetSteer: Float = headingError * 1.6
        var accel: Float = 11.5

        switch action {
        case .accelerate:
            accel = 15.0
        case .hardBrake:
            accel = -18.0
        case .steerLeftHard:
            targetSteer = 0.75
            accel = 9.0
        case .steerLeftSoft:
            targetSteer = 0.35
            accel = 11.0
        case .steerRightSoft:
            targetSteer = -0.35
            accel = 11.0
        case .steerRightHard:
            targetSteer = -0.75
            accel = 9.0
        case .apexCut:
            let insideBias: Float = trackInfo.curvature < 0 ? 0.25 : -0.25
            targetSteer = headingError * 1.5 + insideBias
            accel = 12.5
        case .defendLine:
            let blockSign: Float = nearestOpponent.lateralDelta >= 0 ? -0.25 : 0.25
            targetSteer = headingError * 1.4 + blockSign
            accel = 11.5
        }

        agent.steeringAngle += (max(-0.85, min(0.85, targetSteer)) - agent.steeringAngle) * min(1, dt * 10)
        agent.speed = max(4.0, min(24.5, agent.speed + (accel - agent.speed * 0.42) * dt))
        agent.heading = wrappedAngle(agent.heading + agent.steeringAngle * 1.9 * dt)

        let forward = SIMD3<Float>(-sin(agent.heading), 0, -cos(agent.heading))
        var nextPos = SIMD3<Float>(agent.node.position) + forward * agent.speed * dt
        let updatedTrack = spline.closestTrackInfo(to: nextPos)
        nextPos.y += (updatedTrack.trackCenter.y + 0.06 - nextPos.y) * min(1, dt * 16)

        agent.node.position = SCNVector3(nextPos)
        agent.node.eulerAngles = SCNVector3(0, agent.heading, -agent.steeringAngle * 0.06)

        let onTrackReward: Float = abs(updatedTrack.lateralOffset) < LagunaSecaTrackBuilder.trackHalfWidth ? 0.5 : -0.8
        let nextLatBand = updatedTrack.lateralOffset < -1.5 ? "L" : (updatedTrack.lateralOffset > 1.5 ? "R" : "C")
        let nextState = "\(nextLatBand)|\(curveBand)|\(Int(agent.speed / 6))"
        ca.learn(fromState: agent.lastStateKey, action: agent.lastAction, reward: onTrackReward, toState: nextState)

        agent.lastStateKey = nextState
        agent.lastAction = action
        agent.lastActionText = "CA: \(action)"
    }

    private func updateLapAndProgress(
        agent: inout RaceAgent,
        trackInfo: (distanceAlong: Float, lateralOffset: Float, trackCenter: SIMD3<Float>, tangent: SIMD3<Float>, curvature: Float, elevationDeltaAhead: Float)
    ) {
        let len = spline.totalLength
        let currDist = trackInfo.distanceAlong
        let prevDist = agent.lastTrackDistance

        if prevDist > len * 0.75 && currDist < len * 0.25 {
            agent.lap += 1
        } else if prevDist < len * 0.25 && currDist > len * 0.75 {
            agent.lap = max(1, agent.lap - 1)
        }

        agent.distanceAlongTrack = currDist
        agent.lastTrackDistance = currDist
        agent.totalProgress = Float(max(0, agent.lap - 1)) * len + currDist
    }

    private func resolveCarToCarSpacing() {
        let minSep: Float = 2.35
        for i in 0..<agents.count {
            for j in (i + 1)..<agents.count {
                let pA = SIMD3<Float>(agents[i].node.position)
                let pB = SIMD3<Float>(agents[j].node.position)
                let delta = pB - pA
                let dist = simd_length(SIMD2<Float>(delta.x, delta.z))
                if dist > 0.001 && dist < minSep {
                    let overlap = (minSep - dist) * 0.5
                    let dir = simd_normalize(SIMD3<Float>(delta.x, 0, delta.z))
                    agents[i].node.position = SCNVector3(pA - dir * overlap)
                    agents[j].node.position = SCNVector3(pB + dir * overlap)
                }
            }
        }
    }

    private func publishTelemetry() {
        let sortedByProgress = agents.sorted { $0.totalProgress > $1.totalProgress }
        var rankMap: [String: Int] = [:]
        for (idx, item) in sortedByProgress.enumerated() {
            rankMap[item.id] = idx + 1
        }

        let items: [RaceCarTelemetry] = agents.map { a in
            RaceCarTelemetry(
                id: a.id,
                name: a.name,
                role: a.role,
                lap: min(totalLaps, a.lap),
                positionRank: rankMap[a.id] ?? 1,
                speedKmh: Int(abs(a.speed) * 3.6),
                caGeneration: a.ca?.generation ?? 0,
                caLiveCells: a.ca?.liveCellCount ?? 0,
                lastAction: a.lastActionText
            )
        }

        let leadCA = agents.first(where: { $0.role == .caAgent })?.ca
        let gen = leadCA?.generation ?? 0
        let live = leadCA?.liveCellCount ?? 0

        DispatchQueue.main.async { [weak self] in
            self?.onTelemetryUpdate?(items, gen, live)
        }
    }

    private func wrappedAngle(_ angle: Float) -> Float {
        var a = angle
        while a > .pi { a -= 2 * .pi }
        while a < -.pi { a += 2 * .pi }
        return a
    }
}
