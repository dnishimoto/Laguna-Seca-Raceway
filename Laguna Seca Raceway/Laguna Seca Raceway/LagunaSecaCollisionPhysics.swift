import Foundation
import simd

/// Rigid-body collisions between cars, seen from above (x, z).
///
/// Each hit applies one impulse to one car and the equal and opposite impulse to the
/// other, so total linear momentum (m·v) and angular momentum are conserved.
/// Kinetic energy is not: crumpling bodywork and scraping absorb some of it.
enum LagunaSecaCollisionPhysics {

    static let halfLength: Float = 2.35      // m, wing tip to wing tip is about 4.7 m
    static let halfWidth: Float = 1.15       // m, including the wheels

    /// 0 = cars stick together, 1 = perfectly elastic. Car bodies absorb most of a hit.
    static let restitution: Float = 0.25
    /// Sideways grip between two touching bodies.
    static let friction: Float = 0.35

    struct Body {
        var position: SIMD2<Float>           // (x, z) in meters
        var velocity: SIMD2<Float>           // (x, z) in m/s
        var heading: Float                   // radians, same convention as the cars
        var spin: Float                      // collision yaw rate, rad/s, + = heading increasing
        let mass: Float                      // kg

        /// Moment of inertia of a flat rectangle about its center
        var inertia: Float {
            let length = 2 * halfLength
            let width = 2 * halfWidth
            return mass * (length * length + width * width) / 12
        }

        var forward: SIMD2<Float> { SIMD2<Float>(-sin(heading), -cos(heading)) }
        var side: SIMD2<Float> { SIMD2<Float>(cos(heading), -sin(heading)) }

        var corners: [SIMD2<Float>] {
            let f = forward * halfLength
            let s = side * halfWidth
            return [position + f + s, position + f - s, position - f - s, position - f + s]
        }

        func contains(_ point: SIMD2<Float>) -> Bool {
            let d = point - position
            return abs(simd_dot(d, forward)) <= halfLength + 0.01
                && abs(simd_dot(d, side)) <= halfWidth + 0.01
        }

        /// Velocity of the part of the car at offset `r` from its center
        func velocity(at r: SIMD2<Float>) -> SIMD2<Float> {
            velocity + spin * SIMD2<Float>(r.y, -r.x)
        }

        /// Changes both straight-line and spinning motion
        mutating func apply(impulse: SIMD2<Float>, at r: SIMD2<Float>) {
            velocity += impulse / mass
            spin += turning(r, impulse) / inertia
        }
    }

    /// Turning effect of vector `v` acting at offset `r`
    private static func turning(_ r: SIMD2<Float>, _ v: SIMD2<Float>) -> Float {
        r.y * v.x - r.x * v.y
    }

    struct Contact {
        var normal: SIMD2<Float>             // unit vector from car A toward car B
        var depth: Float                     // how far the bodies overlap, m
        var point: SIMD2<Float>
    }

    /// Separating-axis test between the two car outlines.
    static func contact(_ a: Body, _ b: Body) -> Contact? {
        let between = b.position - a.position
        let reach = 2 * simd_length(SIMD2<Float>(halfLength, halfWidth))
        guard simd_length_squared(between) < reach * reach else { return nil }

        var depth = Float.greatestFiniteMagnitude
        var normal = SIMD2<Float>(1, 0)

        for axis in [a.forward, a.side, b.forward, b.side] {
            let radiusA = halfLength * abs(simd_dot(a.forward, axis)) + halfWidth * abs(simd_dot(a.side, axis))
            let radiusB = halfLength * abs(simd_dot(b.forward, axis)) + halfWidth * abs(simd_dot(b.side, axis))
            let distance = simd_dot(between, axis)
            let overlap = radiusA + radiusB - abs(distance)
            if overlap <= 0 { return nil }
            if overlap < depth {
                depth = overlap
                normal = distance >= 0 ? axis : -axis
            }
        }

        // Touching point: average of the corners that are inside the other car
        var inside = a.corners.filter { b.contains($0) }
        inside += b.corners.filter { a.contains($0) }
        let point: SIMD2<Float>
        if inside.isEmpty {
            point = (a.position + b.position) * 0.5
        } else {
            point = inside.reduce(SIMD2<Float>(0, 0), +) / Float(inside.count)
        }
        return Contact(normal: normal, depth: depth, point: point)
    }

    /// Resolves one pair. Returns the closing speed of the impact in m/s,
    /// or nil if the cars are not touching.
    @discardableResult
    static func resolve(_ a: inout Body, _ b: inout Body) -> Float? {
        guard let hit = contact(a, b) else { return nil }

        let rA = hit.point - a.position
        let rB = hit.point - b.position
        let normal = hit.normal

        // Separate the bodies; the lighter car moves farther, so the center of mass stays put
        let totalMass = a.mass + b.mass
        a.position -= normal * (hit.depth * b.mass / totalMass)
        b.position += normal * (hit.depth * a.mass / totalMass)

        let relative = b.velocity(at: rB) - a.velocity(at: rA)
        let closing = simd_dot(relative, normal)
        guard closing < 0 else { return 0 }   // already moving apart

        // How hard it is to change the contact speed along a direction
        let inverseMass = 1 / a.mass + 1 / b.mass
        let inertiaA = a.inertia
        let inertiaB = b.inertia
        func resistance(_ direction: SIMD2<Float>) -> Float {
            let ta = turning(rA, direction)
            let tb = turning(rB, direction)
            return inverseMass + ta * ta / inertiaA + tb * tb / inertiaB
        }

        let normalImpulse = -(1 + restitution) * closing / resistance(normal)
        var impulse = normal * normalImpulse

        // Scraping along the contact, limited by friction
        let sliding = relative - normal * closing
        let slideSpeed = simd_length(sliding)
        if slideSpeed > 0.001 {
            let tangent = sliding / slideSpeed
            let wanted = slideSpeed / resistance(tangent)
            impulse -= tangent * min(wanted, friction * normalImpulse)
        }

        // Newton's third law: equal and opposite
        b.apply(impulse: impulse, at: rB)
        a.apply(impulse: -impulse, at: rA)

        return -closing
    }
}
