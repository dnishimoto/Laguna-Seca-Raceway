import SwiftUI

/// Race clock and lap times for one car.
struct LapTimer: Equatable {
    var totalLaps: Int = 3
    private(set) var elapsed: TimeInterval = 0
    private(set) var lapTimes: [TimeInterval] = []   // completed laps, in order
    private(set) var hasStarted = false
    private var lapStartTime: TimeInterval = 0

    var isFinished: Bool { lapTimes.count >= totalLaps }
    var currentLap: Int { min(totalLaps, lapTimes.count + 1) }
    var currentLapTime: TimeInterval { elapsed - lapStartTime }
    var bestLapTime: TimeInterval? { lapTimes.min() }

    /// Call once per frame. `lapNumber` is the lap the car is on (1 = first lap).
    mutating func update(lapNumber: Int, speed: Float, dt: TimeInterval) {
        guard !isFinished else { return }   // the clock stops at the finish

        // The clock starts when the car first moves
        if !hasStarted {
            guard abs(speed) > 0.5 else { return }
            hasStarted = true
        }
        elapsed += dt

        // Only a lap number never reached before counts, so backing over the
        // line and crossing it again cannot record an extra lap
        if lapNumber > lapTimes.count + 1 {
            lapTimes.append(elapsed - lapStartTime)
            lapStartTime = elapsed
        }
    }

    /// Minutes, seconds and tenths, e.g. 1:34.5
    static func format(_ time: TimeInterval) -> String {
        let tenths = Int(max(0, time) * 10)
        return String(format: "%d:%02d.%d", tenths / 600, (tenths / 10) % 60, tenths % 10)
    }
}

/// On-screen lap counter, race clock and lap times.
struct LapTimerView: View {
    let timer: LapTimer

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Text(timer.isFinished ? "FINISHED" : "LAP \(timer.currentLap)/\(timer.totalLaps)")
                .font(.system(size: 15, weight: .heavy, design: .monospaced))
                .foregroundStyle(timer.isFinished ? .green : .cyan)

            Text("TIME \(LapTimer.format(timer.elapsed))")
                .font(.system(size: 14, weight: .bold, design: .monospaced))

            if !timer.isFinished {
                Text("This lap \(LapTimer.format(timer.currentLapTime))")
            }

            ForEach(Array(timer.lapTimes.enumerated()), id: \.offset) { index, time in
                Text("Lap \(index + 1)  \(LapTimer.format(time))")
                    .foregroundStyle(time == timer.bestLapTime ? .yellow : .white)
            }
        }
        .font(.system(size: 11, weight: .semibold, design: .monospaced))
        .foregroundStyle(.white)
        .padding(8)
        .background(.black.opacity(0.55))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
