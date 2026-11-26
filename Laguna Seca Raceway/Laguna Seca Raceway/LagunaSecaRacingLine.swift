import Foundation
import SceneKit
import UIKit
import simd

/// The best-path trajectory the agent cars follow: a smooth closed spline inside the
/// pavement that opens up each corner, plus a safe speed for every point along it.
struct LagunaSecaRacingLine {

    struct Limits {
        var lateralGrip: Float = 12.0      // m/s² cornering
        var braking: Float = 13.0          // m/s²
        var acceleration: Float = 8.0      // m/s²
        var topSpeed: Float = 42.0         // m/s (about 94 mph)
        var edgeMargin: Float = 1.6        // m kept between car center and pavement edge
    }

    let limits: Limits
    let totalLength: Float
    let spacing: Float
    private(set) var center: [SIMD3<Float>] = []
    private(set) var right: [SIMD3<Float>] = []
    private(set) var offsets: [Float] = []       // racing line offset from centerline, + = right
    private(set) var points: [SIMD3<Float>] = []
    private(set) var curvatures: [Float] = []     // 1/m along the line, + = right turn
    private(set) var cornerSpeeds: [Float] = []   // grip limit from curve and hill shape
    private(set) var targetSpeeds: [Float] = []   // cornerSpeed plus braking and acceleration

    var count: Int { points.count }

    init(spline: LagunaSecaTrackBuilder.TrackSpline, limits: Limits = Limits()) {
        self.limits = limits
        totalLength = spline.totalLength
        let n = max(16, Int(spline.totalLength / 3.0))
        spacing = spline.totalLength / Float(n)

        for i in 0..<n {
            let f = spline.frame(atDistance: Float(i) * spacing)
            center.append(f.position)
            right.append(f.right)
        }

        offsets = optimizedOffsets(maxOffset: LagunaSecaTrackBuilder.trackHalfWidth - limits.edgeMargin)
        points = (0..<n).map { center[$0] + right[$0] * offsets[$0] }
        buildCurvature()
        buildSpeedProfile()
    }

    private func wrap(_ i: Int) -> Int {
        let n = center.count
        let r = i % n
        return r < 0 ? r + n : r
    }

    /// Relaxes the line to the least total bending that still stays on the pavement.
    /// Works coarse to fine so long, sweeping corners settle quickly.
    private func optimizedOffsets(maxOffset: Float) -> [Float] {
        let n = center.count
        var result = [Float](repeating: 0, count: n)

        for stride in [16, 8, 4, 2, 1] {
            let ids = Array(Swift.stride(from: 0, to: n, by: stride))
            let m = ids.count

            for _ in 0..<400 {
                for k in 0..<m {
                    func point(_ j: Int) -> SIMD2<Float> {
                        let i = ids[(j + m) % m]
                        let p = center[i] + right[i] * result[i]
                        return SIMD2<Float>(p.x, p.z)
                    }
                    let near: SIMD2<Float> = point(k - 1) + point(k + 1)
                    let far: SIMD2<Float> = point(k - 2) + point(k + 2)
                    let ideal: SIMD2<Float> = (near * 4 - far) / 6
                    let i = ids[k]
                    let delta = ideal - SIMD2<Float>(center[i].x, center[i].z)
                    let offset = delta.x * right[i].x + delta.y * right[i].z
                    result[i] = max(-maxOffset, min(maxOffset, offset))
                }
            }

            // Fill the points between this level's nodes
            for k in 0..<m {
                let a = ids[k]
                let b = k + 1 < m ? ids[k + 1] : n
                let endValue = result[b % n]
                var i = a + 1
                while i < b {
                    let t = Float(i - a) / Float(b - a)
                    result[i] = result[a] + (endValue - result[a]) * t
                    i += 1
                }
            }
        }
        return result
    }

    private mutating func buildCurvature() {
        curvatures = (0..<count).map { i in
            let a = points[wrap(i - 3)]
            let b = points[i]
            let c = points[wrap(i + 3)]
            let ab = SIMD2<Float>(b.x - a.x, b.z - a.z)
            let bc = SIMD2<Float>(c.x - b.x, c.z - b.z)
            let ac = SIMD2<Float>(c.x - a.x, c.z - a.z)
            let cross = ab.x * bc.y - ab.y * bc.x
            let denominator = simd_length(ab) * simd_length(bc) * simd_length(ac)
            return denominator > 0.001 ? 2 * cross / denominator : 0
        }
    }

    private func slope(_ i: Int) -> Float {
        (points[wrap(i + 2)].y - points[wrap(i - 2)].y) / (4 * spacing)
    }

    private mutating func buildSpeedProfile() {
        let gravity: Float = 9.81
        let gripRatio = limits.lateralGrip / gravity

        cornerSpeeds = (0..<count).map { i in
            // Crests unload the tires (negative), dips press them down (positive)
            let verticalCurve = (slope(i + 4) - slope(i - 4)) / (8 * spacing)
            let demand = abs(curvatures[i]) - gripRatio * verticalCurve
            guard demand > 0.0001 else { return limits.topSpeed }
            return min(limits.topSpeed, sqrt(limits.lateralGrip / demand))
        }

        targetSpeeds = cornerSpeeds
        // Two laps in each direction so limits carry across the start line
        for step in 0..<(count * 2) {
            let i = wrap(count * 2 - 1 - step)
            let next = targetSpeeds[wrap(i + 1)]
            let decel = max(4, limits.braking + gravity * slope(i))     // downhill brakes longer
            targetSpeeds[i] = min(targetSpeeds[i], sqrt(next * next + 2 * decel * spacing))
        }
        for step in 0..<(count * 2) {
            let i = wrap(step)
            let previous = targetSpeeds[wrap(i - 1)]
            let accel = max(2, limits.acceleration - gravity * slope(i)) // uphill pulls slower
            targetSpeeds[i] = min(targetSpeeds[i], sqrt(previous * previous + 2 * accel * spacing))
        }
    }

    // MARK: - Queries

    private func interpolate(_ values: [Float], at distance: Float) -> Float {
        let u = distance / spacing
        let base = Int(floor(u))
        let t = u - Float(base)
        return values[wrap(base)] * (1 - t) + values[wrap(base + 1)] * t
    }

    private func interpolate(_ values: [SIMD3<Float>], at distance: Float) -> SIMD3<Float> {
        let u = distance / spacing
        let base = Int(floor(u))
        let t = u - Float(base)
        return values[wrap(base)] * (1 - t) + values[wrap(base + 1)] * t
    }

    func offset(at distance: Float) -> Float { interpolate(offsets, at: distance) }
    func curvature(at distance: Float) -> Float { interpolate(curvatures, at: distance) }
    func cornerSpeed(at distance: Float) -> Float { interpolate(cornerSpeeds, at: distance) }
    func targetSpeed(at distance: Float) -> Float { interpolate(targetSpeeds, at: distance) }
    func point(at distance: Float) -> SIMD3<Float> { interpolate(points, at: distance) }

    /// A point at a given sideways offset from the centerline.
    func trackPoint(at distance: Float, lateral: Float) -> SIMD3<Float> {
        interpolate(center, at: distance) + simd_normalize(interpolate(right, at: distance)) * lateral
    }

    /// Lap distance and signed sideways offset of a world position (smooth, not snapped to samples).
    func project(_ position: SIMD3<Float>) -> (distance: Float, lateral: Float) {
        var best = 0
        var bestDistSq = Float.greatestFiniteMagnitude
        for i in 0..<count {
            let dx = position.x - center[i].x
            let dz = position.z - center[i].z
            let d = dx * dx + dz * dz
            if d < bestDistSq {
                bestDistSq = d
                best = i
            }
        }
        let r = right[best]
        let forward = SIMD2<Float>(r.z, -r.x)
        let delta = SIMD2<Float>(position.x - center[best].x, position.z - center[best].z)
        var distance = Float(best) * spacing + simd_dot(delta, forward)
        if distance < 0 { distance += totalLength }
        if distance >= totalLength { distance -= totalLength }
        return (distance, delta.x * r.x + delta.y * r.z)
    }

    // MARK: - On-screen line

    /// Thin ribbon painted on the road so you can see the path the agents aim for.
    func makeNode() -> SCNNode {
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        let halfWidth: Float = 0.18

        for i in 0..<count {
            let lift = SIMD3<Float>(0, 0.13, 0)
            vertices.append(SCNVector3(points[i] - right[i] * halfWidth + lift))
            vertices.append(SCNVector3(points[i] + right[i] * halfWidth + lift))
            let a = Int32(i * 2)
            let b = Int32(((i + 1) % count) * 2)
            indices.append(contentsOf: [a, b, a + 1, a + 1, b, b + 1])
        }

        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = UIColor.cyan.withAlphaComponent(0.75)
        material.isDoubleSided = true
        geometry.materials = [material]

        let node = SCNNode(geometry: geometry)
        node.name = "RacingLine"
        node.castsShadow = false
        return node
    }
}
