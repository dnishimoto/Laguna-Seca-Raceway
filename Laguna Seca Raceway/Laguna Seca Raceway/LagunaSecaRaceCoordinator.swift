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
        var energyReserve: Float = 100.0
        var isRecharging: Bool = false
        var activeMissionPhase: VehicleMissionPhase = .raceProgression
        var activeSubGoal: String = "Lap 1 Sprint"
        var missionQueue: [MissionGoalItem] = []
        var objectMemory: [String: TrackedObjectMemoryEntry] = [:]
        var outcomeWindow: OutcomeEvaluationWindow?
        var sensorTickAccumulator: TimeInterval = 0
        var caTickAccumulator: TimeInterval = 0
        var lastPerception: RacePerception?
        var lastActionText: String = "Ready"
        var lastStateKey: String = "init"
        var lastAction: RaceAction = .accelerate
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
    private let sensorInterval: TimeInterval = 0.10
    private let outcomeWindowDuration: TimeInterval = 0.45

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
            agent.outcomeWindow = OutcomeEvaluationWindow(
                startTime: 0,
                startPosition: startPos,
                startTrackDistance: cfg.startDist,
                startTotalProgress: cfg.startDist,
                lastStateKey: "init",
                lastAction: .accelerate
            )
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
            updateEnergyAndGauges(agent: &agents[i], dt: dt)
            syncMissionQueue(agent: &agents[i])

            let currentWorld = SIMD3<Float>(agents[i].node.position)
            let trackInfo = spline.closestTrackInfo(to: currentWorld)
            let nearest = nearestOpponentInfo(forIndex: i, allPositions: positions)

            agents[i].sensorTickAccumulator += TimeInterval(dt)
            if agents[i].sensorTickAccumulator >= sensorInterval || agents[i].lastPerception == nil {
                agents[i].sensorTickAccumulator = 0
                agents[i].lastPerception = buildPerception(
                    for: agents[i],
                    trackInfo: trackInfo,
                    nearestOpponent: nearest,
                    allPositions: positions,
                    time: time
                )
            }

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
            evaluateOutcomeWindow(agent: &agents[i], trackInfo: trackInfo, dt: dt, time: time)
        }

        resolveCarToCarSpacing()

        if time - lastTelemetryTime >= telemetryInterval {
            lastTelemetryTime = time
            publishTelemetry()
        }
    }

    private func updateEnergyAndGauges(agent: inout RaceAgent, dt: Float) {
        let boostDrain: Float = (agent.role == .firstPersonPlayer && thumbInput.boostEngaged) ? 14.0 : 1.4
        let speedDrain: Float = abs(agent.speed) * 0.08
        if !agent.isRecharging {
            agent.energyReserve = max(0, agent.energyReserve - (boostDrain + speedDrain) * dt)
            if agent.energyReserve < 15.0 {
                agent.isRecharging = true
            }
        } else {
            agent.energyReserve = min(100.0, agent.energyReserve + 28.0 * dt)
            if agent.energyReserve >= 98.0 {
                agent.isRecharging = false
            }
        }
    }

    private func syncMissionQueue(agent: inout RaceAgent) {
        var queue: [MissionGoalItem] = []

        if agent.isRecharging || agent.energyReserve < 15.0 {
            agent.activeMissionPhase = .energyReplenish
            agent.activeSubGoal = "Recharge Reserve (\(Int(agent.energyReserve))%)"
            queue.append(MissionGoalItem(
                id: "energy-replenish",
                phase: .energyReplenish,
                subGoal: agent.activeSubGoal,
                targetDistanceAlongTrack: agent.distanceAlongTrack,
                prescribedAction: .hardBrake
            ))
        } else if agent.lap <= totalLaps {
            agent.activeMissionPhase = .raceProgression
            agent.activeSubGoal = "Lap \(agent.lap)/\(totalLaps) Sector Push"
            let nextGate = (agent.distanceAlongTrack + 24.0).truncatingRemainder(dividingBy: spline.totalLength)
            queue.append(MissionGoalItem(
                id: "lap-\(agent.lap)-gate",
                phase: .raceProgression,
                subGoal: agent.activeSubGoal,
                targetDistanceAlongTrack: nextGate,
                prescribedAction: nil
            ))
        } else {
            agent.activeMissionPhase = .completionOrCruise
            agent.activeSubGoal = "Race Complete • Cool-Down Cruise"
            queue.append(MissionGoalItem(
                id: "race-complete",
                phase: .completionOrCruise,
                subGoal: agent.activeSubGoal,
                targetDistanceAlongTrack: nil,
                prescribedAction: nil
            ))
        }

        agent.missionQueue = queue
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

    private func buildPerception(
            for agent: RaceAgent,
            trackInfo: (distanceAlong: Float, lateralOffset: Float, trackCenter: SIMD3<Float>, tangent: SIMD3<Float>, curvature: Float, elevationDeltaAhead: Float),
            nearestOpponent: (distance: Float, lateralDelta: Float),
            allPositions: [SIMD3<Float>],
            time: TimeInterval
        ) -> RacePerception {
            let myPos = SIMD3<Float>(agent.node.position)
            let forward = SIMD3<Float>(-sin(agent.heading), 0, -cos(agent.heading))

            var updatedMemory = agent.objectMemory
            for (idx, otherPos) in allPositions.enumerated() {
                let otherID = agents[idx].id
                if otherID == agent.id { continue }
                let d = simd_distance(myPos, otherPos)
                if d < 36.0 {
                    updatedMemory[otherID] = TrackedObjectMemoryEntry(
                        id: otherID,
                        position: otherPos,
                        radius: 1.5,
                        lastSeenTime: time,
                        verifiedClearCount: 0
                    )
                }
            }

            for memID in Array(updatedMemory.keys) {
                guard var entry = updatedMemory[memID] else { continue }
                let toEntry = entry.position - myPos
                let dist = simd_length(SIMD2<Float>(toEntry.x, toEntry.z))
                if dist > 0.01 {
                    let dir = simd_normalize(SIMD3<Float>(toEntry.x, 0, toEntry.z))
                    let dot = simd_dot(SIMD3<Float>(forward.x, 0, forward.z), dir)
                    let stillPresent = allPositions.contains { simd_distance($0, entry.position) < 2.5 }
                    if dot > 0.75 && dist < 32.0 && !stillPresent {
                        entry.verifiedClearCount += 1
                        if entry.verifiedClearCount >= 2 {
                            updatedMemory.removeValue(forKey: memID)
                        } else {
                            updatedMemory[memID] = entry
                        }
                    }
                }
            }

            let desiredYaw = atan2(-trackInfo.tangent.x, -trackInfo.tangent.z)
            let headingError = wrappedAngle(desiredYaw - agent.heading)
            let latBand = trackInfo.lateralOffset < -1.8 ? "L" : (trackInfo.lateralOffset > 1.8 ? "R" : "C")
            let curveBand = abs(trackInfo.curvature) > 0.03 ? "sharp" : "straight"
            let speedBand = max(0, Int(agent.speed / 12.0))
            let stateKey = "\(latBand)|\(curveBand)|\(speedBand)"

            return RacePerception(
                carID: agent.id,
                role: agent.role,
                speed: agent.speed,
                maxSpeed: 64.0,
                energyReserve: agent.energyReserve,
                isRecharging: agent.isRecharging,
                headingError: headingError,
                lateralOffset: trackInfo.lateralOffset,
                trackHalfWidth: LagunaSecaTrackBuilder.trackHalfWidth,
                curvatureAhead: trackInfo.curvature,
                elevationDropAhead: trackInfo.elevationDeltaAhead,
                pathDistanceAhead: 120.0,
                detourActive: abs(trackInfo.lateralOffset) > 3.5 || nearestOpponent.distance < 12.0,
                progressRate: agent.speed,
                nearestOpponentDistance: nearestOpponent.distance,
                nearestOpponentLateralDelta: nearestOpponent.lateralDelta,
                rememberedObstacleCount: updatedMemory.count,
                activeMissionPhase: agent.activeMissionPhase,
                activeSubGoal: agent.activeSubGoal,
                prescribedAction: agent.missionQueue.first?.prescribedAction,
                lap: agent.lap,
                progressInLap: trackInfo.distanceAlong / max(1, spline.totalLength),
                totalRaceProgress: agent.totalProgress,
                stateKey: stateKey,
                timestamp: time
            )
        }

    private func updateFirstPersonPlayer(
            agent: inout RaceAgent,
            trackInfo: (distanceAlong: Float, lateralOffset: Float, trackCenter: SIMD3<Float>, tangent: SIMD3<Float>, curvature: Float, elevationDeltaAhead: Float),
            nearestOpponent: (distance: Float, lateralDelta: Float),
            dt: Float
        ) {
            // Porsche 911 GT3 (992) chassis parameters (1 unit = 1 meter)
            let wheelbaseMeters: Float = 2.457
            let minTurnRadiusMeters: Float = 5.20
            let maxLockWheelAngleRad: Float = asin(wheelbaseMeters / minTurnRadiusMeters) // ~0.492 rad

            let rawSteer = max(-1, min(1, thumbInput.leftThumbX + thumbInput.rightThumbSteerAssist * 0.35))
            let deadzone: Float = 0.055
            let shapedSteer: Float
            if abs(rawSteer) <= deadzone {
                shapedSteer = 0
            } else {
                let sign: Float = rawSteer >= 0 ? 1 : -1
                let mag = (abs(rawSteer) - deadzone) / (1.0 - deadzone)
                let expo = 0.34 * mag + 0.66 * (mag * mag * mag)
                shapedSteer = sign * expo
            }

            let targetWheelAngle = shapedSteer * maxLockWheelAngleRad
            let isUnwinding = abs(targetWheelAngle) < abs(agent.steeringAngle) || (targetWheelAngle * agent.steeringAngle < 0)
            let steerLerpRate: Float = isUnwinding ? 14.5 : 8.0
            agent.steeringAngle += (targetWheelAngle - agent.steeringAngle) * min(1, dt * steerLerpRate)

            let throttleAmount = max(0, min(1, thumbInput.rightThumbThrottle))
            let brakeAmount = max(0, min(1, -thumbInput.leftThumbY))
            let boostMult: Float = (thumbInput.boostEngaged && agent.energyReserve > 2.0) ? 1.12 : 1.0

            let maxForwardSpeed: Float = 68.0 * boostMult
            let accelRate: Float = 24.0 * boostMult
            let brakeRate: Float = 38.0

            let isOffTrack = abs(trackInfo.lateralOffset) > LagunaSecaTrackBuilder.trackHalfWidth
            let surfaceGrip: Float = isOffTrack ? 0.58 : 1.0
            let drag: Float = isOffTrack ? 1.35 : 0.24

            if throttleAmount > 0.02 {
                let targetSpeed = throttleAmount * maxForwardSpeed * (isOffTrack ? 0.72 : 1.0)
                if agent.speed < targetSpeed {
                    agent.speed = min(targetSpeed, agent.speed + accelRate * surfaceGrip * dt)
                } else {
                    agent.speed -= (agent.speed - targetSpeed) * 1.6 * dt
                }
            } else {
                agent.speed -= agent.speed * drag * dt
            }

            if brakeAmount > 0.02 {
                agent.speed = max(-10.0, agent.speed - brakeAmount * brakeRate * surfaceGrip * dt)
            }

            agent.speed = max(-10.0, min(maxForwardSpeed, agent.speed))

            // Weight transfer: trail-braking loads front tires (+front grip), heavy throttle slightly lightens nose
            let frontLoadFactor = max(0.84, min(1.22, 1.0 + brakeAmount * 0.16 - throttleAmount * 0.08))
            let speedRatio = min(1.0, abs(agent.speed) / maxForwardSpeed)

            // GT3 downforce offsets high-speed slip so tires stay planted instead of washing out
            let highSpeedGripScale = max(0.76, 1.0 - 0.24 * (speedRatio * speedRatio)) * surfaceGrip
            let yawGain: Float = 0.78 * frontLoadFactor

            let effectiveWheelAngle = agent.steeringAngle * highSpeedGripScale * yawGain
            let yawRate = (agent.speed / wheelbaseMeters) * tan(effectiveWheelAngle)
            agent.heading = wrappedAngle(agent.heading - yawRate * dt)

            // Grip-limited lateral slip: keep slip tight so the car tracks where the nose points
            let maxLateralGripAccel: Float = isOffTrack ? 8.5 : 18.5
            let rawLateralAccel = abs(agent.speed * yawRate)
            let gripRatio = rawLateralAccel > 0.001 ? min(1.0, maxLateralGripAccel / rawLateralAccel) : 1.0
            let clampedSlipAngle = max(-0.07, min(0.07, effectiveWheelAngle * 0.14 * (1.0 - gripRatio * 0.65)))
            let pathHeading = wrappedAngle(agent.heading - clampedSlipAngle)

            let travelDir = SIMD3<Float>(-sin(pathHeading), 0, -cos(pathHeading))
            var nextPos = SIMD3<Float>(agent.node.position) + travelDir * agent.speed * dt

            let updatedTrack = spline.closestTrackInfo(to: nextPos)
            let targetY = updatedTrack.trackCenter.y + 0.06
            nextPos.y += (targetY - nextPos.y) * min(1, dt * 18)

            let rollAngle = -agent.steeringAngle * (0.04 + 0.05 * speedRatio) * surfaceGrip
            let pitchAngle = brakeAmount * 0.022 - throttleAmount * 0.012
            agent.node.position = SCNVector3(nextPos)
            agent.node.eulerAngles = SCNVector3(pitchAngle, agent.heading, rollAngle)

            if let cam = playerCameraNode {
                cam.eulerAngles = SCNVector3(
                    -0.04 + pitchAngle * 0.45,
                    -agent.steeringAngle * 0.12 + clampedSlipAngle * 0.35,
                    -rollAngle * 0.4
                )
            }

            if thumbInput.boostEngaged {
                agent.lastActionText = "GT3 Boost"
            } else if brakeAmount > 0.08 {
                agent.lastActionText = "Brake (\(Int(brakeAmount * 100))%)"
            } else if abs(shapedSteer) > 0.06 {
                let currentRadius = abs(effectiveWheelAngle) > 0.004
                    ? (wheelbaseMeters / abs(tan(effectiveWheelAngle)))
                    : 999.0
                agent.lastActionText = String(format: "Turn R=%.1fm", min(999.0, currentRadius))
            } else if throttleAmount > 0.08 {
                agent.lastActionText = "Speed (\(Int(throttleAmount * 100))%)"
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

        let perception = agent.lastPerception ?? buildPerception(
            for: agent,
            trackInfo: trackInfo,
            nearestOpponent: nearestOpponent,
            allPositions: agents.map { SIMD3<Float>($0.node.position) },
            time: time
        )

        let action = ca.decideAction(perception: perception, dt: dt)
        let targets = ca.controlTargets(
            for: action,
            curvatureAhead: trackInfo.curvature,
            nearestOpponentLateralDelta: nearestOpponent.lateralDelta
        )
        let targetSteer: Float = targets.targetSteer + headingError * 1.4
        let accel: Float = targets.accel

        agent.steeringAngle += (max(-0.85, min(0.85, targetSteer)) - agent.steeringAngle) * min(1, dt * 10)
        let minAllowedSpeed: Float = agent.isRecharging ? 1.5 : 4.0
        agent.speed = max(minAllowedSpeed, min(24.5, agent.speed + (accel - agent.speed * 0.42) * dt))
        agent.heading = wrappedAngle(agent.heading + agent.steeringAngle * 1.9 * dt)

        let forward = SIMD3<Float>(-sin(agent.heading), 0, -cos(agent.heading))
        var nextPos = SIMD3<Float>(agent.node.position) + forward * agent.speed * dt
        let updatedTrack = spline.closestTrackInfo(to: nextPos)
        nextPos.y += (updatedTrack.trackCenter.y + 0.06 - nextPos.y) * min(1, dt * 16)

        agent.node.position = SCNVector3(nextPos)
        agent.node.eulerAngles = SCNVector3(0, agent.heading, -agent.steeringAngle * 0.06)

        agent.lastStateKey = perception.stateKey
        agent.lastAction = action
        agent.lastActionText = "CA: \(action)"
    }

    private func evaluateOutcomeWindow(
        agent: inout RaceAgent,
        trackInfo: (distanceAlong: Float, lateralOffset: Float, trackCenter: SIMD3<Float>, tangent: SIMD3<Float>, curvature: Float, elevationDeltaAhead: Float),
        dt: Float,
        time: TimeInterval
    ) {
        let pos = SIMD3<Float>(agent.node.position)
        let desiredYaw = atan2(-trackInfo.tangent.x, -trackInfo.tangent.z)
        let err = abs(wrappedAngle(desiredYaw - agent.heading))

        if agent.outcomeWindow == nil {
            agent.outcomeWindow = OutcomeEvaluationWindow(
                startTime: time,
                startPosition: pos,
                startTrackDistance: trackInfo.distanceAlong,
                startTotalProgress: agent.totalProgress,
                lastStateKey: agent.lastStateKey,
                lastAction: agent.lastAction
            )
        }

        guard var win = agent.outcomeWindow else { return }
        win.headingErrorSum += err
        win.headingErrorSamples += 1
        if abs(trackInfo.lateralOffset) > LagunaSecaTrackBuilder.trackHalfWidth {
            win.offTrackSamples += 1
        }
        if agent.speed < 0.8 {
            win.stallDuration += TimeInterval(dt)
        }

        let elapsed = time - win.startTime
        if elapsed >= outcomeWindowDuration {
            let progressGain = agent.totalProgress - win.startTotalProgress
            let avgHeadingErr = win.headingErrorSamples > 0 ? win.headingErrorSum / Float(win.headingErrorSamples) : 0
            let offTrackRatio = win.headingErrorSamples > 0 ? Float(win.offTrackSamples) / Float(win.headingErrorSamples) : 0

            let reward: Float = (progressGain > 0.2 ? 0.6 : -0.3)
                - avgHeadingErr * 0.5
                - offTrackRatio * 1.4
                - (win.stallDuration > 0.25 ? 0.5 : 0)

            let nextLatBand = trackInfo.lateralOffset < -1.5 ? "L" : (trackInfo.lateralOffset > 1.5 ? "R" : "C")
            let nextCurveBand = abs(trackInfo.curvature) > 0.03 ? "sharp" : "straight"
            let nextState = "\(nextLatBand)|\(nextCurveBand)|\(max(0, Int(agent.speed / 6.0)))"

            agent.ca?.learn(
                fromState: win.lastStateKey,
                action: win.lastAction,
                reward: reward,
                toState: nextState,
                at: time,
                requireDirty: true
            )

            agent.outcomeWindow = OutcomeEvaluationWindow(
                startTime: time,
                startPosition: pos,
                startTrackDistance: trackInfo.distanceAlong,
                startTotalProgress: agent.totalProgress,
                lastStateKey: agent.lastStateKey,
                lastAction: agent.lastAction
            )
        } else {
            agent.outcomeWindow = win
        }
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
        guard agents.count >= 2 else { return }
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
                    agents[i].outcomeWindow?.collisionEvents += 1
                    agents[j].outcomeWindow?.collisionEvents += 1
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
                energyPercent: Int(a.energyReserve.rounded()),
                missionPhase: a.activeMissionPhase.rawValue,
                caGeneration: a.ca?.generation ?? 0,
                caLiveCells: a.ca?.liveCellCount ?? 0,
                dirtyStatesCount: a.ca?.dirtyStateCount ?? 0,
                lastAction: a.lastActionText,
                decisionNote: a.ca?.lastDecisionText ?? "Steering wheel input"
            )
        }

        let leadCA = agents.first(where: { $0.role == .caAgent })?.ca
        let gen = leadCA?.generation ?? 0
        let live = leadCA?.liveCellCount ?? 0
        let callback = onTelemetryUpdate

        DispatchQueue.main.async {
            callback?(items, gen, live)
        }
    }

    private func wrappedAngle(_ angle: Float) -> Float {
        var a = angle
        while a > .pi { a -= 2 * .pi }
        while a < -.pi { a += 2 * .pi }
        return a
    }
}
