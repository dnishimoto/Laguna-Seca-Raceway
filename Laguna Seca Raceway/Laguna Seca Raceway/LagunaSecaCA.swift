import Foundation
import Combine
import simd

/// Cellular Automaton driving & RL controller with dirty Q-entry tracking,
/// horizon rollout scoring, stall/goal checks, and mission queue awareness.
final class LagunaSecaCA: ObservableObject {
    let size: Int = 18
    @Published private(set) var generation: Int = 0
    @Published private(set) var liveCellCount: Int = 0
    @Published private(set) var lastDecisionText: String = "Grid initialized"
    @Published private(set) var activeSubGoal: String = "Initialize"
    @Published private(set) var dirtyStateCount: Int = 0

    private var cells: [[Bool]]
    private var nextCells: [[Bool]]
    private var qTable: [String: [Int: Float]] = [:]
    private var visitCounts: [String: [Int: Int]] = [:]
    private var dirtyStates: [String: TimeInterval] = [:]
    private let dirtyExpirationWindow: TimeInterval = 2.5

    private var currentGoalContext: String = ""
    private var tacticalOverrideAction: RaceAction?
    private var tacticalOverrideExpiry: TimeInterval = 0
    private var stallAccumulator: TimeInterval = 0
    private var lastTrackedProgress: Float = 0

    private let learningRate: Float = 0.15
    private let discount: Float = 0.85
    private let minExplorationFloor: Float = 0.02

    init(seedOffset: Int = 0) {
        cells = Array(repeating: Array(repeating: false, count: size), count: size)
        nextCells = cells
        randomize(seedOffset: seedOffset)
    }

    func reset(seedOffset: Int = 0) {
        generation = 0
        qTable.removeAll()
        visitCounts.removeAll()
        dirtyStates.removeAll()
        dirtyStateCount = 0
        currentGoalContext = ""
        tacticalOverrideAction = nil
        tacticalOverrideExpiry = 0
        stallAccumulator = 0
        lastTrackedProgress = 0
        randomize(seedOffset: seedOffset)
    }

    private func randomize(seedOffset: Int) {
        for y in 0..<size {
            for x in 0..<size {
                let wave = ((x * 7 + y * 13 + seedOffset * 5) % 4) == 0
                cells[y][x] = Bool.random() || wave
            }
        }
        liveCellCount = countLiveCells()
    }

    func step() {
        for y in 0..<size {
            for x in 0..<size {
                let neighbors = liveNeighborCount(x: x, y: y)
                let alive = cells[y][x]
                if alive {
                    nextCells[y][x] = (neighbors == 2 || neighbors == 3)
                } else {
                    nextCells[y][x] = (neighbors == 3)
                }
            }
        }
        cells = nextCells
        generation += 1
        liveCellCount = countLiveCells()
    }

    private func liveNeighborCount(x: Int, y: Int) -> Int {
        var count = 0
        for dy in -1...1 {
            for dx in -1...1 {
                if dx == 0 && dy == 0 { continue }
                let nx = (x + dx + size) % size
                let ny = (y + dy + size) % size
                if cells[ny][nx] { count += 1 }
            }
        }
        return count
    }

    private func countLiveCells() -> Int {
        cells.reduce(0) { partial, row in
            partial + row.filter { $0 }.count
        }
    }

    private func sectorActivity(xRange: Range<Int>, yRange: Range<Int>) -> Float {
        var active = 0
        var total = 0
        for y in yRange where y >= 0 && y < size {
            for x in xRange where x >= 0 && x < size {
                total += 1
                if cells[y][x] { active += 1 }
            }
        }
        return total > 0 ? Float(active) / Float(total) : 0
    }

    /// Stage 4: Sync goal context, clear stale plans on change, and mark visible states dirty.
    func ingestPerception(_ perception: RacePerception) {
        let newContext = "\(perception.activeMissionPhase.rawValue)|\(perception.activeSubGoal)"
        if newContext != currentGoalContext {
            currentGoalContext = newContext
            activeSubGoal = perception.activeSubGoal
            tacticalOverrideAction = nil
            tacticalOverrideExpiry = 0
            stallAccumulator = 0
        }

        pruneExpiredDirtyStates(at: perception.timestamp)
        markDirtyState(perception.stateKey, at: perception.timestamp)

        // Also mark neighboring lateral/speed horizon states in view as dirty
        let baseParts = perception.stateKey.split(separator: "|")
        if baseParts.count == 3 {
            let curvePart = String(baseParts[1])
            let speedBand = Int(baseParts[2]) ?? 0
            for band in ["L", "C", "R"] {
                markDirtyState("\(band)|\(curvePart)|\(speedBand)", at: perception.timestamp)
                markDirtyState("\(band)|\(curvePart)|\(max(0, speedBand + 1))", at: perception.timestamp)
            }
        }
        dirtyStateCount = dirtyStates.count
    }

    private func markDirtyState(_ key: String, at time: TimeInterval) {
        dirtyStates[key] = time + dirtyExpirationWindow
    }

    private func pruneExpiredDirtyStates(at time: TimeInterval) {
        dirtyStates = dirtyStates.filter { $0.value > time }
        dirtyStateCount = dirtyStates.count
    }

    func isDirty(_ stateKey: String, at time: TimeInterval) -> Bool {
        guard let expiry = dirtyStates[stateKey] else { return false }
        return expiry > time
    }

    /// Stage 5: Executive CA Decision & Action Selection.
    func decideAction(perception: RacePerception, dt: Float, exploration: Float = 0.08) -> RaceAction {
        ingestPerception(perception)

        // 1. Stall & Goal Check
        let progressDelta = perception.totalRaceProgress - lastTrackedProgress
        lastTrackedProgress = perception.totalRaceProgress
        if progressDelta < 0.015 && perception.speed < 2.0 {
            stallAccumulator += TimeInterval(dt)
        } else {
            stallAccumulator = 0
        }

        if stallAccumulator > 1.35 {
            tacticalOverrideAction = abs(perception.lateralOffset) > 1.0
                ? (perception.lateralOffset > 0 ? .steerLeftSoft : .steerRightSoft)
                : .accelerate
            tacticalOverrideExpiry = perception.timestamp + 0.75
            stallAccumulator = 0
        }

        if let override = tacticalOverrideAction, perception.timestamp <= tacticalOverrideExpiry {
            recordDecision(action: override, state: perception.stateKey, note: "Tactical override")
            return override
        } else {
            tacticalOverrideAction = nil
        }

        // 3. Obstruction / Off-Track Override Check
        let edgeRatio = abs(perception.lateralOffset) / max(1.0, perception.trackHalfWidth)
        if edgeRatio > 0.88 || (perception.nearestOpponentDistance < 2.8 && abs(perception.nearestOpponentLateralDelta) < 1.2) {
            let recovery: RaceAction = perception.lateralOffset > 0.5
                ? .steerLeftHard
                : (perception.lateralOffset < -0.5 ? .steerRightHard : .hardBrake)
            tacticalOverrideAction = recovery
            tacticalOverrideExpiry = perception.timestamp + 0.45
            recordDecision(action: recovery, state: perception.stateKey, note: "Obstruction/Edge override")
            return recovery
        }

        // 4a. Prescribed Mission Queue Action Precedence
        if let prescribed = perception.prescribedAction {
            recordDecision(action: prescribed, state: perception.stateKey, note: "Queue prescribed")
            return prescribed
        }

        // 4b. Controlled Exploration (suppressed during critical corner/recharge)
        let effectiveExploration = max(minExplorationFloor, exploration * powf(0.9992, Float(generation)))
        let isCriticalCorner = abs(perception.curvatureAhead) > 0.04 || perception.elevationDropAhead < -1.4
        if !perception.isRecharging && !isCriticalCorner && Float.random(in: 0..<1) < effectiveExploration {
            let chosen = RaceAction.allCases.randomElement() ?? .accelerate
            recordDecision(action: chosen, state: perception.stateKey, note: "CA explore")
            return chosen
        }

        // 2. Rollout & Plan Evaluation across candidate actions
        let leftCA = sectorActivity(xRange: 0..<(size / 3), yRange: 0..<size)
        let centerCA = sectorActivity(xRange: (size / 3)..<((size * 2) / 3), yRange: 0..<size)
        let rightCA = sectorActivity(xRange: ((size * 2) / 3)..<size, yRange: 0..<size)

        var bestAction: RaceAction = .accelerate
        var bestScore: Float = -.infinity

        for action in RaceAction.allCases {
            let qVal = qTable[perception.stateKey]?[action.rawValue] ?? 0
            let visits = Float(visitCounts[perception.stateKey]?[action.rawValue] ?? 0)
            let novelty = 0.25 / sqrtf(1.0 + visits)

            let advisory = advisoryBias(
                for: action,
                perception: perception,
                leftCA: leftCA,
                centerCA: centerCA,
                rightCA: rightCA
            )
            let rolloutScore = evaluateShortHorizonRollout(
                action: action,
                perception: perception,
                horizonSteps: 3,
                stepDt: 0.14
            )

            let total = qVal + advisory + rolloutScore + novelty
            if total > bestScore {
                bestScore = total
                bestAction = action
            }
        }

        recordDecision(action: bestAction, state: perception.stateKey, note: "CA gen \(generation)")
        return bestAction
    }

    private func advisoryBias(
        for action: RaceAction,
        perception: RacePerception,
        leftCA: Float,
        centerCA: Float,
        rightCA: Float
    ) -> Float {
        var heuristic: Float = 0
        let absCurvature = abs(perception.curvatureAhead)
        let isSharpTurn = absCurvature > 0.035 || abs(perception.headingError) > 0.32
        let isCorkscrewDrop = perception.elevationDropAhead < -1.2

        if perception.isRecharging {
            switch action {
            case .hardBrake: return 1.5
            case .accelerate: return -1.5
            default: return -0.2
            }
        }

        switch action {
        case .accelerate:
            heuristic += (isSharpTurn || isCorkscrewDrop) ? -1.4 : 1.3 * centerCA + 0.6
            if abs(perception.headingError) > 0.55 { heuristic -= 1.2 }
        case .hardBrake:
            heuristic += (isSharpTurn || isCorkscrewDrop) ? 1.8 : -0.8
            if perception.nearestOpponentDistance < 4.5 && perception.speed > 12 {
                heuristic += 0.9
            }
        case .steerLeftHard:
            heuristic += (perception.headingError < -0.25 || perception.curvatureAhead < -0.03) ? 1.7 : -0.4
            heuristic += leftCA * 0.6
        case .steerLeftSoft:
            heuristic += (perception.headingError < -0.06 || perception.curvatureAhead < -0.01) ? 1.2 : 0.1
            heuristic += leftCA * 0.4
        case .steerRightSoft:
            heuristic += (perception.headingError > 0.06 || perception.curvatureAhead > 0.01) ? 1.2 : 0.1
            heuristic += rightCA * 0.4
        case .steerRightHard:
            heuristic += (perception.headingError > 0.25 || perception.curvatureAhead > 0.03) ? 1.7 : -0.4
            heuristic += rightCA * 0.6
        case .apexCut:
            heuristic += absCurvature > 0.015 ? (1.0 * centerCA) : -0.3
        case .defendLine:
            heuristic += perception.nearestOpponentDistance < 6.0 ? 1.1 : -0.4
        }

        let edgeRatio = abs(perception.lateralOffset) / max(1.0, perception.trackHalfWidth)
        if edgeRatio > 0.72 {
            if perception.lateralOffset > 0 && (action == .steerLeftSoft || action == .steerLeftHard) {
                heuristic += 1.6
            } else if perception.lateralOffset < 0 && (action == .steerRightSoft || action == .steerRightHard) {
                heuristic += 1.6
            } else if action == .steerRightHard && perception.lateralOffset > 0 {
                heuristic -= 2.5
            } else if action == .steerLeftHard && perception.lateralOffset < 0 {
                heuristic -= 2.5
            }
        }

        return heuristic
    }

    private func evaluateShortHorizonRollout(
        action: RaceAction,
        perception: RacePerception,
        horizonSteps: Int,
        stepDt: Float
    ) -> Float {
        var simSpeed = perception.speed
        var simLateral = perception.lateralOffset
        var simHeadingErr = perception.headingError
        var score: Float = 0

        let cmd = controlTargets(for: action, curvatureAhead: perception.curvatureAhead, nearestOpponentLateralDelta: perception.nearestOpponentLateralDelta)

        for _ in 0..<horizonSteps {
            simSpeed = max(3.5, min(perception.maxSpeed, simSpeed + (cmd.accel - simSpeed * 0.42) * stepDt))
            simHeadingErr += (cmd.targetSteer * 1.9 - perception.curvatureAhead * simSpeed * 0.12) * stepDt
            simLateral += simSpeed * sin(simHeadingErr) * stepDt

            let simEdgeRatio = abs(simLateral) / max(1.0, perception.trackHalfWidth)
            let offTrackPenalty: Float = simEdgeRatio > 1.0 ? -2.2 * (simEdgeRatio - 1.0) : 0
            let alignmentReward: Float = max(-1.0, 1.0 - abs(simHeadingErr) * 1.4) * 0.35
            let progressReward: Float = (simSpeed / max(1.0, perception.maxSpeed)) * 0.45

            score += progressReward + alignmentReward + offTrackPenalty
        }

        return score
    }

    func controlTargets(
        for action: RaceAction,
        curvatureAhead: Float,
        nearestOpponentLateralDelta: Float
    ) -> (targetSteer: Float, accel: Float) {
        switch action {
        case .accelerate:
            return (0, 15.0)
        case .hardBrake:
            return (0, -18.0)
        case .steerLeftHard:
            return (0.75, 9.0)
        case .steerLeftSoft:
            return (0.35, 11.0)
        case .steerRightSoft:
            return (-0.35, 11.0)
        case .steerRightHard:
            return (-0.75, 9.0)
        case .apexCut:
            let insideBias: Float = curvatureAhead < 0 ? 0.25 : -0.25
            return (insideBias, 12.5)
        case .defendLine:
            let blockSign: Float = nearestOpponentLateralDelta >= 0 ? -0.25 : 0.25
            return (blockSign, 11.5)
        }
    }

    private func recordDecision(action: RaceAction, state: String, note: String) {
        visitCounts[state, default: [:]][action.rawValue, default: 0] += 1
        lastDecisionText = "\(note) -> \(action)"
    }

    /// Stage 7: Only mutates dirty states seen in view when dirty tracking is active.
    func learn(
        fromState: String,
        action: RaceAction,
        reward: Float,
        toState: String,
        at time: TimeInterval,
        requireDirty: Bool = true
    ) {
        if requireDirty && !isDirty(fromState, at: time) {
            return
        }
        let oldQ = qTable[fromState]?[action.rawValue] ?? 0
        let nextMax = qTable[toState]?.values.max() ?? 0
        let target = reward + discount * nextMax
        let updated = oldQ + learningRate * (target - oldQ)
        qTable[fromState, default: [:]][action.rawValue] = updated
    }
}
