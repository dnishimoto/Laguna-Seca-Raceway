import Foundation
import SceneKit
import simd

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
}

struct RaceCarTelemetry: Identifiable, Equatable {
    let id: String
    let name: String
    let role: RaceCarRole
    let lap: Int
    let positionRank: Int
    let speedKmh: Int
    let energyPercent: Int
    let missionPhase: String
    let caGeneration: Int
    let caLiveCells: Int
    let dirtyStatesCount: Int
    let lastAction: String
    let decisionNote: String
}

