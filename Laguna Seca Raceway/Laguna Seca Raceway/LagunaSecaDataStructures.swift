import Foundation
import SceneKit
import simd

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
    var headingError: Float
    var lateralOffset: Float
    var trackHalfWidth: Float
    var curvatureAhead: Float
    var elevationDropAhead: Float
    var nearestOpponentDistance: Float
    var nearestOpponentLateralDelta: Float
    var lap: Int
    var progressInLap: Float
    var totalRaceProgress: Float
    var stateKey: String
    var timestamp: TimeInterval
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
    let caGeneration: Int
    let caLiveCells: Int
    let lastAction: String
}
