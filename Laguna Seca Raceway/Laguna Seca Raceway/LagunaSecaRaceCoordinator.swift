import Foundation
import SceneKit
import UIKit
import simd

final class LagunaSecaRaceCoordinator: NSObject, SCNSceneRendererDelegate {

    /// Race weight in kg. A heavier car is pushed around less in a collision.
    private static let carMasses: [String: Float] = [
        "player": 1430,                                // Porsche 911 GT3 class
        "ca-1": 1250, "ca-2": 1600, "ca-3": 1350,
        "ca-4": 1500, "ca-5": 1200, "ca-6": 1550,
        "ca-7": 1300, "ca-8": 1450, "ca-9": 1400
    ]

    struct RaceAgent {
        let id: String
        let name: String
        let role: RaceCarRole
        let node: SCNNode
        let ca: LagunaSecaCA?

        var distanceAlongTrack: Float = 0
        var lastTrackDistance: Float = 0
        var lap: Int = 1
        var lapTimer = LapTimer()
        var totalProgress: Float = 0
        var speed: Float = 0
        var bounceVelocity: SIMD3<Float> = .zero   // sliding motion from rail and car hits
        var spinVelocity: Float = 0                // yaw rate from car hits, rad/s
        var mass: Float = 1430                     // kg, with driver
        var impactTimer: Float = 0                 // keeps the "Collision" label up briefly
        var avoidOffset: Float = 0                 // planned shift off the racing line
        var caLineNudge: Float = 0                 // small line preference from the CA
        var driverView = DriverView()
        var driverPlanNote: String = "Racing line"
        var plannedSpeedLimit: Float = .greatestFiniteMagnitude
        var skill: Float = 1.0                     // fraction of the ideal speed
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
    private let racingLine: LagunaSecaRacingLine

    var thumbInput = ThumbInputState()
    var animationSpeed: Double = 1.0
    var isRunning: Bool = true
    var totalLaps: Int = 10

    // Reset is requested on the main thread but carried out on the render thread
    private let resetLock = NSLock()
    private var resetRequested = false

    private var lastFrameTime: TimeInterval = 0
    private var lastTelemetryTime: TimeInterval = 0
    private let telemetryInterval: TimeInterval = 0.12
    private let sensorInterval: TimeInterval = 0.10
    private let outcomeWindowDuration: TimeInterval = 0.45

    var onTelemetryUpdate: (([RaceCarTelemetry], Int, Int) -> Void)?

    init(scene: SCNScene, spline: LagunaSecaTrackBuilder.TrackSpline) {
        self.scene = scene
        self.spline = spline
        self.racingLine = LagunaSecaRacingLine(spline: spline)
        super.init()
        scene.rootNode.addChildNode(racingLine.makeNode())
        setupCars(in: scene)
    }

    func setupCars(in scene: SCNScene) {
        for agent in agents {
            agent.node.removeFromParentNode()
        }
        agents.removeAll()

        let configs: [(id: String, name: String, role: RaceCarRole, startDist: Float, lateral: Float, color: UIColor, accent: UIColor, caSeed: Int?)] = [
            ("player", "You (1st Person)", .firstPersonPlayer, 88.0, -2.2, UIColor.systemBlue, UIColor.cyan, nil),
            ("ca-1",   "CA Racer #1",      .caAgent,           84.0,  2.2, UIColor.systemRed, UIColor.yellow, 1),
            ("ca-2",   "CA Racer #2",      .caAgent,           80.0, -2.2, UIColor.systemGreen, UIColor.white, 2),
            ("ca-3",   "CA Racer #3",      .caAgent,           76.0,  2.2, UIColor.systemOrange, UIColor.black, 3),
            ("ca-4",   "CA Racer #4",      .caAgent,           72.0, -2.2, UIColor.systemPurple, UIColor.green, 4),
            ("ca-5",   "CA Racer #5",      .caAgent,           68.0,  2.2, UIColor.systemPink, UIColor.white, 5),
            ("ca-6",   "CA Racer #6",      .caAgent,           64.0, -2.2, UIColor.systemTeal, UIColor.yellow, 6),
            ("ca-7",   "CA Racer #7",      .caAgent,           60.0,  2.2, UIColor.systemIndigo, UIColor.orange, 7),
            ("ca-8",   "CA Racer #8",      .caAgent,           56.0, -2.2, UIColor.systemBrown, UIColor.white, 8),
            ("ca-9",   "CA Racer #9",      .caAgent,           52.0,  2.2, UIColor.systemMint, UIColor.black, 9)
         
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
            agent.mass = Self.carMasses[cfg.id] ?? 1430
            agent.lapTimer = LapTimer(totalLaps: totalLaps)
            agent.skill = cfg.caSeed.map { 1.0 - Float($0 - 1) * 0.03 } ?? 1.0
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

    /// Safe to call from the main thread. The cars are rebuilt at the start of the next
    /// frame, so `agents` is never replaced while a frame is still using it.
    func resetRace() {
        resetLock.lock()
        resetRequested = true
        resetLock.unlock()
    }

    private func takeResetRequest() -> Bool {
        resetLock.lock()
        defer { resetLock.unlock() }
        let requested = resetRequested
        resetRequested = false
        return requested
    }

    func renderer(_ renderer: SCNSceneRenderer, updateAtTime time: TimeInterval) {
        if takeResetRequest(), let scene {
            lastFrameTime = 0
            lastTelemetryTime = 0
            setupCars(in: scene)
            renderer.pointOfView = playerCameraNode
        }

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
                var perception = buildPerception(
                    for: agents[i],
                    trackInfo: trackInfo,
                    nearestOpponent: nearest,
                    allPositions: positions,
                    time: time
                )
                if agents[i].role == .caAgent {
                    lookAndPlan(index: i, positions: positions)
                    applyDriverView(agents[i], to: &perception)
                }
                agents[i].lastPerception = perception
            }

            if agents[i].role == .firstPersonPlayer {
                updateFirstPersonPlayer(
                    agent: &agents[i],
                    trackInfo: trackInfo,
                    nearestOpponent: nearest,
                    dt: dt
                )
            } else {
                updateCAAgent(agent: &agents[i], dt: dt)
            }

            updateLapAndProgress(agent: &agents[i], trackInfo: trackInfo)
            agents[i].lapTimer.update(lapNumber: agents[i].lap, speed: agents[i].speed, dt: TimeInterval(dt))
            evaluateOutcomeWindow(agent: &agents[i], trackInfo: trackInfo, dt: dt, time: time)
        }

        resolveCarCollisions()

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

            let speedBeforeControls = agent.speed   // may be outside engine limits after a hit
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
                agent.speed = max(min(-10.0, speedBeforeControls), agent.speed - brakeAmount * brakeRate * surfaceGrip * dt)
            }

            agent.speed = max(min(-10.0, speedBeforeControls), min(max(maxForwardSpeed, speedBeforeControls), agent.speed))

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
            let hitRail = applyGuardRail(agent: &agent, position: &nextPos, dt: dt)

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
            if agent.impactTimer > 0 {
                agent.lastActionText = "Collision"
            } else if hitRail {
                agent.lastActionText = "Guard Rail Bounce"
            }
        }
    /// `agent` is an inout reference into `agents`, so nothing in here (or in anything
    /// it calls) may read `self.agents`. Doing so is an exclusivity violation that crashes.
    private func updateCAAgent(agent: inout RaceAgent, dt: Float) {
        // Perception is built by the render loop before this call; skip the frame if missing
        guard let ca = agent.ca, let perception = agent.lastPerception else { return }

        agent.caTickAccumulator += TimeInterval(dt)
        if agent.caTickAccumulator >= 0.18 {
            agent.caTickAccumulator = 0
            ca.step()
        }

        let action = ca.decideAction(perception: perception, dt: dt)
        driveAlongRacingLine(agent: &agent, action: action, dt: dt)

        agent.lastStateKey = perception.stateKey
        agent.lastAction = action
        agent.lastActionText = "\(agent.driverPlanNote) • CA: \(action)"
    }

    /// Follows the planned trajectory. The CA's choice only nudges pace and line,
    /// so what it learns can shape the driving without steering the car off the road.
    private func driveAlongRacingLine(agent: inout RaceAgent, action: RaceAction, dt: Float) {
        let paceFactor: Float
        let nudge: Float
        switch action {
        case .accelerate:     paceFactor = 1.02; nudge = 0
        case .hardBrake:      paceFactor = 0.95; nudge = 0
        case .steerLeftHard:  paceFactor = 0.98; nudge = -0.6
        case .steerLeftSoft:  paceFactor = 0.99; nudge = -0.3
        case .steerRightSoft: paceFactor = 0.99; nudge = 0.3
        case .steerRightHard: paceFactor = 0.98; nudge = 0.6
        case .apexCut:        paceFactor = 1.00; nudge = 0
        case .defendLine:     paceFactor = 0.99; nudge = 0
        }
        // Smoothed so frame-to-frame CA changes do not shake the car
        agent.caLineNudge += (nudge - agent.caLineNudge) * min(1, dt * 1.5)

        let position = SIMD3<Float>(agent.node.position)
        let here = racingLine.project(position)

        // Target speed: trajectory profile, what is visible, and traffic
        let preview = here.distance + agent.speed * 0.25
        var target = min(racingLine.targetSpeed(at: preview), agent.driverView.visibleSpeedLimit)
        target *= agent.skill * paceFactor
        if agent.isRecharging { target = min(target, 18) }
        if abs(here.lateral) > LagunaSecaTrackBuilder.trackHalfWidth { target = min(target, 16) }
        target = max(4, target)
        target = min(target, agent.plannedSpeedLimit)   // traffic may require slower than 4 m/s
        let trackForward = spline.frame(atDistance: here.distance).forward
        let facing = -sin(agent.heading) * trackForward.x - cos(agent.heading) * trackForward.z
        if facing < 0 { target = 6 }                    // turning around after a spin

        let previousSpeed = agent.speed
        if agent.speed < target {
            agent.speed = min(target, agent.speed + racingLine.limits.acceleration * dt)
        } else {
            agent.speed = max(target, agent.speed - racingLine.limits.braking * dt)
        }

        let wantedCurvature = LagunaSecaDriverAI.steeringCurvature(
            line: racingLine,
            position: position,
            heading: agent.heading,
            trackDistance: here.distance,
            speed: agent.speed,
            avoidOffset: agent.avoidOffset + agent.caLineNudge
        )
        // Limited by turning circle (5.2 m radius) and tire grip
        let gripCurvature = racingLine.limits.lateralGrip * 1.3 / max(1, agent.speed * agent.speed)
        let maxCurvature = min(1.0 / 5.2, gripCurvature)
        // The tires cannot steer while a hit still has the car spinning quickly
        let control = max(0, 1 - abs(agent.spinVelocity) / 2.5)
        let curvature = max(-maxCurvature, min(maxCurvature, wantedCurvature)) * control
        agent.heading = wrappedAngle(agent.heading - agent.speed * curvature * dt)
        agent.steeringAngle += (-atan(2.457 * curvature) - agent.steeringAngle) * min(1, dt * 10)

        let forward = SIMD3<Float>(-sin(agent.heading), 0, -cos(agent.heading))
        var nextPos = position + forward * agent.speed * dt
        _ = applyGuardRail(agent: &agent, position: &nextPos, dt: dt)
        let updatedTrack = spline.closestTrackInfo(to: nextPos)
        nextPos.y += (updatedTrack.trackCenter.y + 0.06 - nextPos.y) * min(1, dt * 16)

        let braking = previousSpeed - agent.speed > 0.01
        agent.node.position = SCNVector3(nextPos)
        agent.node.eulerAngles = SCNVector3(braking ? 0.015 : 0, agent.heading, -agent.steeringAngle * 0.06)
    }

    /// What this agent can see, and how it plans to get around the cars in view.
    private func lookAndPlan(index: Int, positions: [SIMD3<Float>]) {
        let me = agents[index]
        let here = racingLine.project(positions[index])

        var others: [LagunaSecaDriverAI.OtherCar] = []
        for j in agents.indices where j != index {
            let projected = racingLine.project(positions[j])
            others.append(LagunaSecaDriverAI.OtherCar(
                id: agents[j].id,
                position: positions[j],
                trackDistance: projected.distance,
                lateral: projected.lateral,
                speed: agents[j].speed
            ))
        }

        let view = LagunaSecaDriverAI.look(
            line: racingLine,
            position: positions[index],
            heading: me.heading,
            trackDistance: here.distance,
            others: others
        )
        let plan = LagunaSecaDriverAI.plan(
            line: racingLine,
            view: view,
            trackDistance: here.distance,
            lateral: here.lateral,
            speed: me.speed,
            previousAvoidOffset: me.avoidOffset
        )

        // Move across smoothly: at most 0.45 m per sensor tick (about 4.5 m/s)
        let change = max(-0.45, min(0.45, plan.avoidOffset - me.avoidOffset))
        agents[index].avoidOffset = me.avoidOffset + change
        agents[index].plannedSpeedLimit = plan.speedLimit
        agents[index].driverView = view
        agents[index].driverPlanNote = plan.note
    }

    /// Feeds the CA only what the driver can actually see.
    private func applyDriverView(_ agent: RaceAgent, to perception: inout RacePerception) {
        let view = agent.driverView
        // Same scale as TrackSpline curvature (about 59 per 1/m)
        perception.curvatureAhead = view.curveCurvature * 59.0
        perception.elevationDropAhead = view.elevationChange
        perception.pathDistanceAhead = view.sightDistance

        if let nearest = view.cars.first {
            let myLateral = racingLine.project(SIMD3<Float>(agent.node.position)).lateral
            perception.nearestOpponentDistance = nearest.distance
            perception.nearestOpponentLateralDelta = nearest.lateral - myLateral
        } else {
            perception.nearestOpponentDistance = .infinity
            perception.nearestOpponentLateralDelta = 0
        }
        perception.detourActive = abs(agent.avoidOffset) > 0.5
    }

    /// Applies any knockback, then bounces the car off the guard rails.
    /// Returns true on the frame the car strikes a rail.
    private func applyGuardRail(agent: inout RaceAgent, position: inout SIMD3<Float>, dt: Float) -> Bool {
        position += agent.bounceVelocity * dt
        agent.bounceVelocity *= exp(-4.0 * dt)      // tire grip stops the sideways slide
        agent.heading = wrappedAngle(agent.heading + agent.spinVelocity * dt)
        agent.spinVelocity *= exp(-3.5 * dt)        // and damps the spin
        agent.impactTimer = max(0, agent.impactTimer - dt)

        let nearest = spline.nearestCenterlinePoint(to: position)
        let delta = SIMD3<Float>(position.x - nearest.point.x, 0, position.z - nearest.point.z)
        let distance = simd_length(delta)
        guard distance > LagunaSecaTrackBuilder.barrierOffset - 2.6 else { return false }

        // Unit vector pointing from the track out through the rail
        let outward = delta / distance
        let nose = SIMD3<Float>(-sin(agent.heading), 0, -cos(agent.heading))
        let side = SIMD3<Float>(-nose.z, 0, nose.x)

        // How far the 4.5 m x 2 m body reaches toward the rail at this angle
        let reach = abs(simd_dot(nose, outward)) * 2.25 + abs(simd_dot(side, outward)) * 1.2
        let limit = LagunaSecaTrackBuilder.barrierOffset - reach
        guard distance > limit else { return false }

        // Put the car back on the track side of the rail
        position.x = nearest.point.x + outward.x * (limit - 0.05)
        position.z = nearest.point.z + outward.z * (limit - 0.05)

        let velocity = nose * agent.speed + agent.bounceVelocity
        let impact = simd_dot(velocity, outward)   // speed into the rail
        guard impact > 0 else { return false }

        // Knock the car back toward the track
        agent.bounceVelocity = -outward * min(18.0, max(5.0, impact * 0.6))

        if agent.speed > 0 {
            // Deflect the nose along the rail and back toward the road.
            // Near head-on hits turn the car in the race direction.
            let along = simd_normalize(nearest.tangent - outward * simd_dot(nearest.tangent, outward))
            let alignment = simd_dot(nose, along)
            let directionSign: Float = alignment < -0.35 ? -1 : 1
            let newNose = simd_normalize(along * directionSign - outward * 0.35)
            agent.heading = atan2(-newNose.x, -newNose.z)

            // Harder hits scrub off more speed
            let headOnRatio = min(1, impact / max(1, agent.speed))
            agent.speed *= 1.0 - 0.65 * headOnRatio
        } else {
            agent.speed = 0
        }

        agent.steeringAngle = 0
        agent.spinVelocity *= 0.3                   // the rail stops most of any spin
        agent.outcomeWindow?.collisionEvents += 1
        return true
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

            let nextLatBand = trackInfo.lateralOffset < -1.8 ? "L" : (trackInfo.lateralOffset > 1.8 ? "R" : "C")
            let nextCurveBand = abs(trackInfo.curvature) > 0.03 ? "sharp" : "straight"
            let nextState = "\(nextLatBand)|\(nextCurveBand)|\(max(0, Int(agent.speed / 12.0)))"

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
            agent.lap = max(0, agent.lap - 1)
        }

        agent.distanceAlongTrack = currDist
        agent.lastTrackDistance = currDist
        agent.totalProgress = Float(agent.lap - 1) * len + currDist
    }

    /// Car-to-car hits using each car's mass. Momentum passes from one car to the other.
    private func resolveCarCollisions() {
        guard agents.count >= 2 else { return }

        var bodies: [LagunaSecaCollisionPhysics.Body] = agents.map { agent in
            let position = agent.node.position
            let nose = SIMD2<Float>(-sin(agent.heading), -cos(agent.heading))
            let slide = SIMD2<Float>(agent.bounceVelocity.x, agent.bounceVelocity.z)
            return LagunaSecaCollisionPhysics.Body(
                position: SIMD2<Float>(Float(position.x), Float(position.z)),
                velocity: nose * agent.speed + slide,
                heading: agent.heading,
                spin: agent.spinVelocity,
                mass: agent.mass
            )
        }

        var touched = [Bool](repeating: false, count: agents.count)
        var struck = [Bool](repeating: false, count: agents.count)

        // A few passes let a hit travel through a line or pack of cars
        for _ in 0..<3 {
            for i in 0..<bodies.count {
                for j in (i + 1)..<bodies.count {
                    // Skip cars separated in height
                    if abs(Float(agents[i].node.position.y - agents[j].node.position.y)) > 2.0 { continue }

                    var a = bodies[i]
                    var b = bodies[j]
                    guard let impactSpeed = LagunaSecaCollisionPhysics.resolve(&a, &b) else { continue }
                    bodies[i] = a
                    bodies[j] = b
                    touched[i] = true
                    touched[j] = true
                    if impactSpeed > 1.0 {
                        struck[i] = true
                        struck[j] = true
                    }
                }
            }
        }

        for i in agents.indices where touched[i] {
            let body = bodies[i]
            // Split the new velocity into rolling (along the nose) and sliding (the rest)
            let nose = body.forward
            let rolling = simd_dot(body.velocity, nose)
            let slide = body.velocity - nose * rolling

            agents[i].speed = rolling
            agents[i].bounceVelocity = SIMD3<Float>(slide.x, 0, slide.y)
            agents[i].spinVelocity = body.spin
            agents[i].node.position = SCNVector3(
                SIMD3<Float>(body.position.x, Float(agents[i].node.position.y), body.position.y)
            )

            if struck[i] {
                agents[i].impactTimer = 0.6
                agents[i].outcomeWindow?.collisionEvents += 1
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
                lap: max(1, min(totalLaps, a.lap)),
                lapTimer: a.lapTimer,
                positionRank: rankMap[a.id] ?? 1,
                speedMph: Int((abs(a.speed) * 2.23694).rounded()),
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
