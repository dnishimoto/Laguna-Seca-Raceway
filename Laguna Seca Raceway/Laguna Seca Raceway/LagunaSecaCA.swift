import Foundation
import Combine
import simd

/// Racing controller with a 100 x 100 learning grid,
/// perception encoding, associative experience memory,
/// trajectory confidence, Q-learning, rollout scoring,
/// mission queue awareness, and tactical safety overrides.
final class LagunaSecaCA: ObservableObject {

    // MARK: - Learning Structures

    struct TrajectoryConfidenceEntry {
        var confidence: Float = 0.5
        var cumulativeReward: Float = 0.0
        var sampleCount: Int = 0
        var lastUpdatedTime: TimeInterval = 0
    }

    struct CellMemory {
        var activation: Float = 0
        var visitCount: Int = 0
        var rewardAverage: Float = 0
        var lastUpdated: TimeInterval = 0
    }

    struct ExperienceMemory {
        var rewardAverage: Float = 0
        var sampleCount: Int = 0
        var transitionCounts: [String: Int] = [:]
        var lastUpdated: TimeInterval = 0

        var predictedNextState: String? {
            transitionCounts.max {
                $0.value < $1.value
            }?.key
        }
    }

    // MARK: - Grid

    let size: Int = 100

    @Published private(set) var generation: Int = 0
    @Published private(set) var liveCellCount: Int = 0
    @Published private(set) var lastDecisionText: String = "Grid initialized"
    @Published private(set) var activeSubGoal: String = "Initialize"
    @Published private(set) var dirtyStateCount: Int = 0

    private var cells: [[Bool]]
    private var nextCells: [[Bool]]

    private var cellMemory: [CellMemory] =
        Array(repeating: CellMemory(), count: 10_000)

    // MARK: - Learning Memory

    private var qTable: [String: [Int: Float]] = [:]
    private var visitCounts: [String: [Int: Int]] = [:]

    private var trajectoryConfidence:
        [String: [Int: TrajectoryConfidenceEntry]] = [:]

    private var experienceMemory:
        [String: [Int: ExperienceMemory]] = [:]

    private var dirtyStates: [String: TimeInterval] = [:]

    private let dirtyExpirationWindow: TimeInterval = 2.5

    // MARK: - Memory Parameters

    private let cellActivationDecay: Float = 0.94
    private let cellLearningRate: Float = 0.18
    private let memoryLearningRate: Float = 0.20

    // MARK: - Mission and Tactical State

    private var currentGoalContext: String = ""

    private var tacticalOverrideAction: RaceAction?
    private var tacticalOverrideExpiry: TimeInterval = 0

    private var stallAccumulator: TimeInterval = 0
    private var lastTrackedProgress: Float = 0

    // MARK: - Q-Learning Parameters

    private let learningRate: Float = 0.15
    private let discount: Float = 0.85
    private let confidenceAlpha: Float = 0.22
    private let minExplorationFloor: Float = 0.02

    // MARK: - Initialization

    init(seedOffset: Int = 0) {
        cells = Array(
            repeating: Array(repeating: false, count: size),
            count: size
        )

        nextCells = cells

        randomize(seedOffset: seedOffset)
    }

    // MARK: - Reset

    /// Resets the current race state while preserving learned experience.
    func reset(seedOffset: Int = 0) {
        generation = 0

        dirtyStates.removeAll()
        dirtyStateCount = 0

        currentGoalContext = ""
        activeSubGoal = "Initialize"

        tacticalOverrideAction = nil
        tacticalOverrideExpiry = 0

        stallAccumulator = 0
        lastTrackedProgress = 0

        randomize(seedOffset: seedOffset)

        lastDecisionText = "Race reset; learned memory retained"
    }

    /// Explicitly erases all accumulated learning.
    func clearAllLearningMemory() {
        qTable.removeAll()
        visitCounts.removeAll()
        trajectoryConfidence.removeAll()
        experienceMemory.removeAll()
        dirtyStates.removeAll()

        dirtyStateCount = 0

        cellMemory = Array(
            repeating: CellMemory(),
            count: size * size
        )

        cells = Array(
            repeating: Array(repeating: false, count: size),
            count: size
        )

        nextCells = cells

        liveCellCount = 0
        generation = 0

        lastDecisionText = "All learning memory cleared"
    }

    // MARK: - Grid Initialization

    private func randomize(seedOffset: Int) {
        cells = Array(
            repeating: Array(repeating: false, count: size),
            count: size
        )

        nextCells = cells

        cellMemory = Array(
            repeating: CellMemory(),
            count: size * size
        )

        liveCellCount = 0
    }

    // MARK: - Cellular Grid Evolution

    func step() {
        for y in 0..<size {
            for x in 0..<size {
                let neighbors = liveNeighborCount(x: x, y: y)
                let alive = cells[y][x]

                if alive {
                    nextCells[y][x] =
                        neighbors == 2 || neighbors == 3
                } else {
                    nextCells[y][x] = neighbors == 3
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
                if dx == 0 && dy == 0 {
                    continue
                }

                let nx = (x + dx + size) % size
                let ny = (y + dy + size) % size

                if cells[ny][nx] {
                    count += 1
                }
            }
        }

        return count
    }

    private func countLiveCells() -> Int {
        cells.reduce(0) { partial, row in
            partial + row.filter { $0 }.count
        }
    }

    // MARK: - Grid Activity

    private func sectorActivity(
        xRange: Range<Int>,
        yRange: Range<Int>
    ) -> Float {
        var active = 0
        var total = 0

        for y in yRange where y >= 0 && y < size {
            for x in xRange where x >= 0 && x < size {
                total += 1

                if cells[y][x] {
                    active += 1
                }
            }
        }

        return total > 0
            ? Float(active) / Float(total)
            : 0
    }

    // MARK: - Perception Encoding

    private func normalized(
        _ value: Float,
        minimum: Float,
        maximum: Float
    ) -> Float {
        guard maximum > minimum else {
            return 0
        }

        return max(
            0,
            min(1, (value - minimum) / (maximum - minimum))
        )
    }

    private func encodeFeature(
        _ value: Float,
        minimum: Float,
        maximum: Float,
        row: Int,
        timestamp: TimeInterval
    ) {
        guard row >= 0 && row < size else {
            return
        }

        let normalizedValue = normalized(
            value,
            minimum: minimum,
            maximum: maximum
        )

        let column = min(
            size - 1,
            max(
                0,
                Int(normalizedValue * Float(size - 1))
            )
        )

        let index = row * size + column

        guard cellMemory.indices.contains(index) else {
            return
        }

        var memory = cellMemory[index]

        memory.activation +=
            cellLearningRate * (1.0 - memory.activation)

        memory.activation = min(1, memory.activation)
        memory.visitCount += 1
        memory.lastUpdated = timestamp

        cellMemory[index] = memory
    }

    private func encodePerception(
        _ perception: RacePerception
    ) {
        for index in cellMemory.indices {
            cellMemory[index].activation *= cellActivationDecay
        }

        encodeFeature(perception.speed, minimum: 0, maximum: max(1, perception.maxSpeed), row: 0, timestamp: perception.timestamp)
        encodeFeature(perception.curvatureAhead, minimum: -0.10, maximum: 0.10, row: 1, timestamp: perception.timestamp)
        encodeFeature(perception.headingError, minimum: -1.5, maximum: 1.5, row: 2, timestamp: perception.timestamp)
        encodeFeature(perception.lateralOffset, minimum: -perception.trackHalfWidth, maximum: perception.trackHalfWidth, row: 3, timestamp: perception.timestamp)
        encodeFeature(perception.nearestOpponentDistance, minimum: 0, maximum: 50, row: 4, timestamp: perception.timestamp)
        encodeFeature(perception.nearestOpponentLateralDelta, minimum: -10, maximum: 10, row: 5, timestamp: perception.timestamp)
        encodeFeature(perception.elevationDropAhead, minimum: -10, maximum: 10, row: 6, timestamp: perception.timestamp)
        encodeFeature(perception.totalRaceProgress, minimum: 0, maximum: 1, row: 7, timestamp: perception.timestamp)
        encodeFeature(perception.isRecharging ? 1 : 0, minimum: 0, maximum: 1, row: 8, timestamp: perception.timestamp)

        updateVisibleGrid()
    }

    private func updateVisibleGrid() {
        for index in cellMemory.indices {
            let y = index / size
            let x = index % size

            cells[y][x] =
                cellMemory[index].activation > 0.20
        }

        liveCellCount = countLiveCells()
    }

    // MARK: - Cell Memory Access

    func cellActivation(x: Int, y: Int) -> Float {
        guard x >= 0, x < size,
              y >= 0, y < size else {
            return 0
        }

        return cellMemory[y * size + x].activation
    }

    func cellVisitCount(x: Int, y: Int) -> Int {
        guard x >= 0, x < size,
              y >= 0, y < size else {
            return 0
        }

        return cellMemory[y * size + x].visitCount
    }

    // MARK: - Trajectory Confidence

    func confidence(
        forState stateKey: String,
        action: RaceAction,
        at time: TimeInterval? = nil
    ) -> Float {
        guard var entry =
            trajectoryConfidence[stateKey]?[action.rawValue] else {
            return 0.5
        }

        if let now = time,
           entry.lastUpdatedTime > 0 {

            let age = max(
                0,
                Float(now - entry.lastUpdatedTime)
            )

            let decay = expf(-0.03 * age)

            entry.confidence =
                0.5 + (entry.confidence - 0.5) * decay
        }

        return max(
            0.0,
            min(1.0, entry.confidence)
        )
    }

    private func trajectoryConfidenceScore(
        forState stateKey: String,
        action: RaceAction,
        at time: TimeInterval
    ) -> Float {
        let conf = confidence(
            forState: stateKey,
            action: action,
            at: time
        )

        let samples = Float(
            trajectoryConfidence[stateKey]?[action.rawValue]?.sampleCount ?? 0
        )

        let reliability = min(
            1.0,
            0.25 + samples * 0.15
        )

        let centered = (conf - 0.5) * 2.0

        return centered * 1.15 * reliability
    }

    // MARK: - Experience Memory

    private func experienceScore(
        state: String,
        action: RaceAction
    ) -> Float {
        guard let entry =
            experienceMemory[state]?[action.rawValue],
            entry.sampleCount > 0 else {
            return 0
        }

        let reliability = min(
            1.0,
            Float(entry.sampleCount) / 10.0
        )

        return entry.rewardAverage * reliability * 1.5
    }

    private func recordExperience(
        fromState: String,
        action: RaceAction,
        reward: Float,
        toState: String,
        time: TimeInterval
    ) {
        var entry =
            experienceMemory[fromState]?[action.rawValue]
            ?? ExperienceMemory()

        entry.rewardAverage +=
            memoryLearningRate *
            (reward - entry.rewardAverage)

        entry.sampleCount += 1

        entry.transitionCounts[toState, default: 0] += 1

        entry.lastUpdated = time

        experienceMemory[
            fromState,
            default: [:]
        ][action.rawValue] = entry
    }

    func predictedNextState(
        from state: String,
        action: RaceAction
    ) -> String? {
        experienceMemory[state]?[action.rawValue]?
            .predictedNextState
    }

    func experienceCount(
        for state: String,
        action: RaceAction
    ) -> Int {
        experienceMemory[state]?[action.rawValue]?
            .sampleCount ?? 0
    }

    func experienceReward(
        for state: String,
        action: RaceAction
    ) -> Float {
        experienceMemory[state]?[action.rawValue]?
            .rewardAverage ?? 0
    }

    // MARK: - Perception Ingestion

    func ingestPerception(
        _ perception: RacePerception
    ) {
        let newContext =
            "\(perception.activeMissionPhase.rawValue)|\(perception.activeSubGoal)"

        if newContext != currentGoalContext {
            currentGoalContext = newContext

            activeSubGoal = perception.activeSubGoal

            tacticalOverrideAction = nil
            tacticalOverrideExpiry = 0

            stallAccumulator = 0
        }

        encodePerception(perception)

        pruneExpiredDirtyStates(
            at: perception.timestamp
        )

        markDirtyState(
            perception.stateKey,
            at: perception.timestamp
        )

        let baseParts =
            perception.stateKey.split(separator: "|")

        if baseParts.count == 3 {
            let curvePart = String(baseParts[1])
            let speedBand = Int(baseParts[2]) ?? 0

            for band in ["L", "C", "R"] {
                markDirtyState(
                    "\(band)|\(curvePart)|\(speedBand)",
                    at: perception.timestamp
                )

                markDirtyState(
                    "\(band)|\(curvePart)|\(max(0, speedBand + 1))",
                    at: perception.timestamp
                )
            }
        }

        dirtyStateCount = dirtyStates.count
    }

    // MARK: - Dirty State Tracking

    private func markDirtyState(
        _ key: String,
        at time: TimeInterval
    ) {
        dirtyStates[key] =
            time + dirtyExpirationWindow
    }

    private func pruneExpiredDirtyStates(
        at time: TimeInterval
    ) {
        dirtyStates = dirtyStates.filter {
            $0.value > time
        }

        dirtyStateCount = dirtyStates.count
    }

    func isDirty(
        _ stateKey: String,
        at time: TimeInterval
    ) -> Bool {
        guard let expiry = dirtyStates[stateKey] else {
            return false
        }

        return expiry > time
    }

    // MARK: - Executive Decision and Action Selection

    func decideAction(
        perception: RacePerception,
        dt: Float,
        exploration: Float = 0.08
    ) -> RaceAction {

        ingestPerception(perception)

        // 1. Stall and goal check.

        let progressDelta =
            perception.totalRaceProgress - lastTrackedProgress

        lastTrackedProgress =
            perception.totalRaceProgress

        if progressDelta < 0.015 &&
            perception.speed < 2.0 {

            stallAccumulator += TimeInterval(dt)
        } else {
            stallAccumulator = 0
        }

        if stallAccumulator > 1.35 {
            tacticalOverrideAction =
                abs(perception.lateralOffset) > 1.0
                ? (
                    perception.lateralOffset > 0
                    ? .steerLeftSoft
                    : .steerRightSoft
                )
                : .accelerate

            tacticalOverrideExpiry =
                perception.timestamp + 0.75

            stallAccumulator = 0
        }

        // 2. Apply an active tactical override.

        if let override = tacticalOverrideAction,
           perception.timestamp <= tacticalOverrideExpiry {

            recordDecision(
                action: override,
                state: perception.stateKey,
                note: "Tactical override"
            )

            return override
        } else {
            tacticalOverrideAction = nil
        }

        // 3. Obstruction and off-track override.

        let edgeRatio =
            abs(perception.lateralOffset) /
            max(1.0, perception.trackHalfWidth)

        if edgeRatio > 0.88 ||
            (
                perception.nearestOpponentDistance < 2.8 &&
                abs(perception.nearestOpponentLateralDelta) < 1.2
            ) {

            let recovery: RaceAction =
                perception.lateralOffset > 0.5
                ? .steerLeftHard
                : (
                    perception.lateralOffset < -0.5
                    ? .steerRightHard
                    : .hardBrake
                )

            tacticalOverrideAction = recovery

            tacticalOverrideExpiry =
                perception.timestamp + 0.45

            recordDecision(
                action: recovery,
                state: perception.stateKey,
                note: "Obstruction/Edge override"
            )

            return recovery
        }

        // 4. Prescribed mission queue action precedence.

        if let prescribed = perception.prescribedAction {
            recordDecision(
                action: prescribed,
                state: perception.stateKey,
                note: "Queue prescribed"
            )

            return prescribed
        }

        // 5. Controlled exploration.

        let effectiveExploration = max(
            minExplorationFloor,
            exploration * powf(
                0.9992,
                Float(generation)
            )
        )

        let isCriticalCorner =
            abs(perception.curvatureAhead) > 0.055 ||
            perception.elevationDropAhead < -2.2

        if !perception.isRecharging &&
            !isCriticalCorner &&
            Float.random(in: 0..<1) < effectiveExploration {

            let chosen =
                RaceAction.allCases.randomElement() ?? .accelerate

            recordDecision(
                action: chosen,
                state: perception.stateKey,
                note: "CA explore"
            )

            return chosen
        }

        // 6. Grid activity.

        let leftCA = sectorActivity(
            xRange: 0..<(size / 3),
            yRange: 0..<size
        )

        let centerCA = sectorActivity(
            xRange: (size / 3)..<((size * 2) / 3),
            yRange: 0..<size
        )

        let rightCA = sectorActivity(
            xRange: ((size * 2) / 3)..<size,
            yRange: 0..<size
        )

        // 7. Evaluate candidate actions.

        var bestAction: RaceAction = .accelerate
        var bestScore: Float = -.infinity
        var bestConfidence: Float = 0.5

        for action in RaceAction.allCases {

            let qVal =
                qTable[perception.stateKey]?[action.rawValue] ?? 0

            let visits = Float(
                visitCounts[perception.stateKey]?[action.rawValue] ?? 0
            )

            let novelty =
                0.25 / sqrtf(1.0 + visits)

            let confBonus = trajectoryConfidenceScore(
                forState: perception.stateKey,
                action: action,
                at: perception.timestamp
            )

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

            let memoryScore = experienceScore(
                state: perception.stateKey,
                action: action
            )

            let total =
                qVal +
                advisory +
                rolloutScore +
                confBonus +
                novelty +
                memoryScore

            if total > bestScore {
                bestScore = total
                bestAction = action

                bestConfidence = confidence(
                    forState: perception.stateKey,
                    action: action,
                    at: perception.timestamp
                )
            }
        }

        recordDecision(
            action: bestAction,
            state: perception.stateKey,
            note: String(
                format: "CA g%d (conf %.2f)",
                generation,
                bestConfidence
            )
        )

        return bestAction
    }

    // MARK: - Advisory Scoring

    private func advisoryBias(
        for action: RaceAction,
        perception: RacePerception,
        leftCA: Float,
        centerCA: Float,
        rightCA: Float
    ) -> Float {

        var heuristic: Float = 0

        let absCurvature =
            abs(perception.curvatureAhead)

        let isSevereTurn =
            absCurvature > 0.055 ||
            abs(perception.headingError) > 0.55

        let isSevereDrop =
            perception.elevationDropAhead < -2.2

        if perception.isRecharging {
            switch action {
            case .hardBrake:
                return 1.5

            case .accelerate:
                return -1.5

            default:
                return -0.2
            }
        }

        switch action {

        case .accelerate:
            heuristic +=
                (isSevereTurn || isSevereDrop)
                ? -0.6
                : 1.8 * centerCA + 1.2

            if abs(perception.headingError) > 0.75 {
                heuristic -= 0.9
            }

        case .hardBrake:
            heuristic +=
                (isSevereTurn || isSevereDrop)
                ? 1.4
                : -1.3

            if perception.nearestOpponentDistance < 3.5 &&
                perception.speed > 18 {
                heuristic += 0.6
            }

        case .steerLeftHard:
            heuristic +=
                (
                    perception.headingError < -0.25 ||
                    perception.curvatureAhead < -0.03
                )
                ? 1.7
                : -0.3

            heuristic += leftCA * 0.6

        case .steerLeftSoft:
            heuristic +=
                (
                    perception.headingError < -0.06 ||
                    perception.curvatureAhead < -0.01
                )
                ? 1.3
                : 0.35

            heuristic += leftCA * 0.4

        case .steerRightSoft:
            heuristic +=
                (
                    perception.headingError > 0.06 ||
                    perception.curvatureAhead > 0.01
                )
                ? 1.3
                : 0.35

            heuristic += rightCA * 0.4

        case .steerRightHard:
            heuristic +=
                (
                    perception.headingError > 0.25 ||
                    perception.curvatureAhead > 0.03
                )
                ? 1.7
                : -0.3

            heuristic += rightCA * 0.6

        case .apexCut:
            heuristic +=
                absCurvature > 0.012
                ? 1.3 * centerCA + 0.5
                : 0.2

        case .defendLine:
            heuristic +=
                perception.nearestOpponentDistance < 7.0
                ? 1.2
                : -0.2
        }

        let edgeRatio =
            abs(perception.lateralOffset) /
            max(1.0, perception.trackHalfWidth)

        if edgeRatio > 0.72 {

            if perception.lateralOffset > 0 &&
                (
                    action == .steerLeftSoft ||
                    action == .steerLeftHard
                ) {

                heuristic += 1.6

            } else if perception.lateralOffset < 0 &&
                (
                    action == .steerRightSoft ||
                    action == .steerRightHard
                ) {

                heuristic += 1.6

            } else if action == .steerRightHard &&
                        perception.lateralOffset > 0 {

                heuristic -= 2.5

            } else if action == .steerLeftHard &&
                        perception.lateralOffset < 0 {

                heuristic -= 2.5
            }
        }

        return heuristic
    }

    // MARK: - Short Horizon Prediction

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

        let cmd = controlTargets(
            for: action,
            curvatureAhead: perception.curvatureAhead,
            nearestOpponentLateralDelta:
                perception.nearestOpponentLateralDelta
        )

        for _ in 0..<horizonSteps {

            simSpeed = max(
                4.0,
                min(
                    perception.maxSpeed,
                    simSpeed +
                    (cmd.accel - simSpeed * 0.28) * stepDt
                )
            )

            simHeadingErr += (
                cmd.targetSteer * 1.9 -
                perception.curvatureAhead * simSpeed * 0.10
            ) * stepDt

            simLateral +=
                simSpeed * sin(simHeadingErr) * stepDt

            let simEdgeRatio =
                abs(simLateral) /
                max(1.0, perception.trackHalfWidth)

            let offTrackPenalty: Float =
                simEdgeRatio > 1.0
                ? -2.0 * (simEdgeRatio - 1.0)
                : 0

            let alignmentReward: Float =
                max(
                    -1.0,
                    1.0 - abs(simHeadingErr) * 1.2
                ) * 0.30

            let progressReward: Float =
                (
                    simSpeed /
                    max(1.0, perception.maxSpeed)
                ) * 0.75

            score +=
                progressReward +
                alignmentReward +
                offTrackPenalty
        }

        return score
    }

    // MARK: - Action Control Targets

    func controlTargets(
        for action: RaceAction,
        curvatureAhead: Float,
        nearestOpponentLateralDelta: Float
    ) -> (targetSteer: Float, accel: Float) {

        switch action {

        case .accelerate:
            return (0, 20.0)

        case .hardBrake:
            return (0, -18.0)

        case .steerLeftHard:
            return (0.75, 11.5)

        case .steerLeftSoft:
            return (0.35, 13.5)

        case .steerRightSoft:
            return (-0.35, 13.5)

        case .steerRightHard:
            return (-0.75, 11.5)

        case .apexCut:
            let insideBias: Float =
                curvatureAhead < 0 ? 0.25 : -0.25

            return (insideBias, 16.5)

        case .defendLine:
            let blockSign: Float =
                nearestOpponentLateralDelta >= 0
                ? -0.25
                : 0.25

            return (blockSign, 15.0)
        }
    }

    // MARK: - Decision Recording

    private func recordDecision(
        action: RaceAction,
        state: String,
        note: String
    ) {
        visitCounts[
            state,
            default: [:]
        ][action.rawValue, default: 0] += 1

        lastDecisionText =
            "\(note) -> \(action)"
    }

    // MARK: - Learning From Outcomes

    func learn(
        fromState: String,
        action: RaceAction,
        reward: Float,
        toState: String,
        at time: TimeInterval,
        requireDirty: Bool = true
    ) {

        var entry =
            trajectoryConfidence[fromState]?[action.rawValue]
            ?? TrajectoryConfidenceEntry()

        let normalizedOutcome = max(
            0.0,
            min(1.0, 0.5 + reward * 0.5)
        )

        entry.confidence +=
            confidenceAlpha *
            (normalizedOutcome - entry.confidence)

        entry.cumulativeReward += reward
        entry.sampleCount += 1
        entry.lastUpdatedTime = time

        trajectoryConfidence[
            fromState,
            default: [:]
        ][action.rawValue] = entry

        recordExperience(
            fromState: fromState,
            action: action,
            reward: reward,
            toState: toState,
            time: time
        )

        if requireDirty &&
            !isDirty(fromState, at: time) {
            return
        }

        let oldQ =
            qTable[fromState]?[action.rawValue] ?? 0

        let nextMax =
            qTable[toState]?.values.max() ?? 0

        let target =
            reward + discount * nextMax

        let updated =
            oldQ + learningRate * (target - oldQ)

        qTable[
            fromState,
            default: [:]
        ][action.rawValue] = updated
    }
}
