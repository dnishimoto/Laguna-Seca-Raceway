import Foundation
import simd

/// Another car as one driver sees it.
struct SeenCar {
    var id: String
    var gap: Float        // meters ahead along the track (negative = just behind)
    var lateral: Float    // offset from the centerline, + = right
    var speed: Float
    var distance: Float
}

/// Everything an agent driver can see from its seat this moment.
struct DriverView {
    var sightDistance: Float = 0          // how far down the road is visible
    var curveDistance: Float = 0          // distance to the tightest visible curve
    var curveCurvature: Float = 0         // 1/m, + = right
    var elevationChange: Float = 0        // biggest rise (+) or drop (-) in view, meters
    var crestDistance: Float? = nil       // where a hill crest hides the road
    var visibleSpeedLimit: Float = 0      // fastest speed that can still make everything in view
    var cars: [SeenCar] = []
}

struct LagunaSecaDriverAI {

    static let fieldOfViewHalfAngle: Float = 60.0 * .pi / 180.0   // 120° forward cone
    static let roadViewRange: Float = 160.0
    static let carViewRange: Float = 90.0
    static let sideAwarenessRange: Float = 7.0                    // mirrors: cars alongside
    static let eyeHeight: Float = 1.15

    struct OtherCar {
        var id: String
        var position: SIMD3<Float>
        var trackDistance: Float
        var lateral: Float
        var speed: Float
    }

    // MARK: - Perception

    static func look(
        line: LagunaSecaRacingLine,
        position: SIMD3<Float>,
        heading: Float,
        trackDistance: Float,
        others: [OtherCar]
    ) -> DriverView {
        var view = DriverView()
        view.visibleSpeedLimit = line.limits.topSpeed

        let forward = SIMD2<Float>(-sin(heading), -cos(heading))
        let eyeY = position.y + eyeHeight
        let minCos = cos(fieldOfViewHalfAngle)

        // Walk down the road until it leaves the view cone or drops behind a crest
        var horizonSlope = -Float.greatestFiniteMagnitude
        var ahead: Float = 6
        while ahead <= roadViewRange {
            let p = line.point(at: trackDistance + ahead)
            let flat = SIMD2<Float>(p.x - position.x, p.z - position.z)
            let range = max(0.1, simd_length(flat))

            if ahead > 20 && simd_dot(flat / range, forward) < minCos { break }

            // The road surface is hidden if nearer ground rises above the line of sight
            let sightSlope = (p.y + 0.35 - eyeY) / range
            if sightSlope < horizonSlope {
                view.crestDistance = ahead
                break
            }
            horizonSlope = max(horizonSlope, (p.y - eyeY) / range)
            view.sightDistance = ahead

            let k = line.curvature(at: trackDistance + ahead)
            if abs(k) > abs(view.curveCurvature) {
                view.curveCurvature = k
                view.curveDistance = ahead
            }

            let rise = p.y - position.y
            if abs(rise) > abs(view.elevationChange) {
                view.elevationChange = rise
            }

            // Brake early enough for every visible corner
            let corner = line.cornerSpeed(at: trackDistance + ahead)
            let usableDistance = max(0, ahead - 5)
            let allowed = sqrt(corner * corner + 2 * line.limits.braking * 0.8 * usableDistance)
            view.visibleSpeedLimit = min(view.visibleSpeedLimit, allowed)

            ahead += 5
        }

        // Never outrun the view: keep enough room to slow down for what is hidden
        let blindLimit = sqrt(14.0 * 14.0 + 2 * line.limits.braking * max(view.sightDistance, 25))
        view.visibleSpeedLimit = min(view.visibleSpeedLimit, blindLimit)

        let halfLap = line.totalLength * 0.5
        for other in others {
            let flat = SIMD2<Float>(other.position.x - position.x, other.position.z - position.z)
            let distance = simd_length(flat)
            guard distance < carViewRange else { continue }

            let inCone = distance > 0.01 && simd_dot(flat / distance, forward) >= minCos
            let withinSight = distance <= max(view.sightDistance, 25) + 10
            guard distance <= sideAwarenessRange || (inCone && withinSight) else { continue }

            var gap = other.trackDistance - trackDistance
            if gap > halfLap { gap -= line.totalLength }
            if gap < -halfLap { gap += line.totalLength }

            view.cars.append(SeenCar(
                id: other.id,
                gap: gap,
                lateral: other.lateral,
                speed: other.speed,
                distance: distance
            ))
        }
        view.cars.sort { $0.distance < $1.distance }
        return view
    }

    // MARK: - Planning around other cars

    struct Plan {
        var avoidOffset: Float        // sideways shift away from the racing line
        var speedLimit: Float
        var note: String
    }

    static func plan(
        line: LagunaSecaRacingLine,
        view: DriverView,
        trackDistance: Float,
        lateral: Float,
        speed: Float,
        previousAvoidOffset: Float
    ) -> Plan {
        let maxLateral = LagunaSecaTrackBuilder.trackHalfWidth - 1.3
        let carSpacing: Float = 2.9
        let lineOffset = line.offset(at: trackDistance + 12)
        var wanted = max(-maxLateral, min(maxLateral, lineOffset + previousAvoidOffset))
        var desired = lineOffset
        var speedLimit = Float.greatestFiniteMagnitude
        var note = "Racing line"

        // Cars that matter: alongside, or ahead and being caught. Nearest first.
        for car in view.cars where car.gap > -5 && car.gap < 14 + max(0, speed - car.speed) * 2.2 {
            let alongside = abs(car.gap) < 6
            let blocksPath = abs(car.lateral - desired) < carSpacing || abs(car.lateral - lateral) < 2.4
            guard blocksPath else { continue }

            let leftSlot = car.lateral - carSpacing
            let rightSlot = car.lateral + carSpacing
            let leftOpen = leftSlot >= -maxLateral
            let rightOpen = rightSlot <= maxLateral

            if alongside {
                // Hold our side of the other car
                desired = lateral >= car.lateral ? min(maxLateral, rightSlot) : max(-maxLateral, leftSlot)
                note = "Side by side"
            } else if leftOpen && (!rightOpen || abs(leftSlot - wanted) <= abs(rightSlot - wanted)) {
                desired = leftSlot
                note = "Passing left"
            } else if rightOpen {
                desired = rightSlot
                note = "Passing right"
            }
            wanted = desired

            // Until there is sideways room, do not close faster than we can brake
            if car.gap > 0 && abs(car.lateral - lateral) < 2.3 {
                let room = car.gap - 6.0
                let safe = sqrt(max(0, car.speed * car.speed + 2 * 9.0 * room))
                if safe < speedLimit {
                    speedLimit = max(3, safe)
                    if speed > speedLimit { note = "Braking for car" }
                }
            }
        }

        desired = max(-maxLateral, min(maxLateral, desired))
        return Plan(avoidOffset: desired - lineOffset, speedLimit: speedLimit, note: note)
    }

    // MARK: - Following the trajectory

    /// Pure pursuit: aim at a point further down the planned trajectory the faster we go.
    /// Returns the path curvature to drive (1/m, + = right).
    static func steeringCurvature(
        line: LagunaSecaRacingLine,
        position: SIMD3<Float>,
        heading: Float,
        trackDistance: Float,
        speed: Float,
        avoidOffset: Float
    ) -> Float {
        let lookAhead = max(7, min(22, 5 + 0.35 * speed))
        let maxLateral = LagunaSecaTrackBuilder.trackHalfWidth - 1.3
        let aimDistance = trackDistance + lookAhead
        let aimLateral = max(-maxLateral, min(maxLateral, line.offset(at: aimDistance) + avoidOffset))
        let aim = line.trackPoint(at: aimDistance, lateral: aimLateral)

        let toAim = SIMD2<Float>(aim.x - position.x, aim.z - position.z)
        let rightAxis = SIMD2<Float>(cos(heading), -sin(heading))
        let forwardAxis = SIMD2<Float>(-sin(heading), -cos(heading))
        if simd_dot(toAim, forwardAxis) < 0 {
            // Facing away after a spin: full lock toward the side the road is on
            return simd_dot(toAim, rightAxis) >= 0 ? 1.0 / 5.2 : -1.0 / 5.2
        }
        let distanceSq = max(1, simd_length_squared(toAim))
        return 2 * simd_dot(toAim, rightAxis) / distanceSq
    }
}
