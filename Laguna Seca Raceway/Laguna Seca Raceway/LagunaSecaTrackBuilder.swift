import SceneKit
import UIKit
import simd


/// The original, fictional circuits. One is picked at random each time the app launches.
/// All run clockwise and share the same main straight, so the starting grid and
/// grandstand fit every layout.
enum RaceTrack: CaseIterable {
    case sawtoothRidge
    case redMesa
    case cedarBasin

    /// Chosen once per launch. Reset restarts the race on this same track.
    static let current: RaceTrack = allCases.randomElement() ?? .sawtoothRidge

    var name: String {
        switch self {
        case .sawtoothRidge: return "Sawtooth Ridge"
        case .redMesa: return "Red Mesa"
        case .cedarBasin: return "Cedar Basin"
        }
    }

    /// Lap length in meters. The control points are scaled sideways to match it.
    var lapLength: Float {
        switch self {
        case .sawtoothRidge: return 4200
        case .redMesa: return 3600
        case .cedarBasin: return 4600
        }
    }

    var groundColor: UIColor {
        switch self {
        case .sawtoothRidge: return UIColor(red: 0.24, green: 0.31, blue: 0.19, alpha: 1.0) // olive grass
        case .redMesa: return UIColor(red: 0.52, green: 0.30, blue: 0.18, alpha: 1.0)       // red desert
        case .cedarBasin: return UIColor(red: 0.11, green: 0.26, blue: 0.17, alpha: 1.0)    // forest green
        }
    }

    /// Centerline points as (x, elevation, z). The first point is the start / finish line.
    var controlPoints: [SIMD3<Float>] {
        switch self {
        case .sawtoothRidge:
            return [
                SIMD3<Float>(  0,  0.0,  430),   // Start / Finish line
                SIMD3<Float>(  0,  0.0,  160),   // Main straight
                SIMD3<Float>(  0,  1.0, -190),
                SIMD3<Float>( 35,  2.0, -330),   // North sweeper
                SIMD3<Float>(150,  4.0, -415),
                SIMD3<Float>(300,  6.0, -420),
                SIMD3<Float>(405,  8.0, -335),
                SIMD3<Float>(385, 10.0, -225),
                SIMD3<Float>(275, 11.0, -165),   // First infield loop
                SIMD3<Float>(250, 12.0,  -65),
                SIMD3<Float>(330, 14.0,   15),
                SIMD3<Float>(470, 17.0,    5),
                SIMD3<Float>(590, 19.0, -110),   // High point
                SIMD3<Float>(740, 18.0, -125),
                SIMD3<Float>(835, 16.0,  -15),   // East loop
                SIMD3<Float>(805, 13.0,  120),
                SIMD3<Float>(680, 11.0,  175),
                SIMD3<Float>(545, 10.0,  215),   // Second infield loop
                SIMD3<Float>(500,  9.0,  310),
                SIMD3<Float>(590,  8.0,  385),
                SIMD3<Float>(730,  6.0,  415),
                SIMD3<Float>(775,  5.0,  525),   // Southeast loop
                SIMD3<Float>(690,  3.0,  625),
                SIMD3<Float>(520,  2.0,  640),
                SIMD3<Float>(380,  3.0,  560),   // South esses
                SIMD3<Float>(250,  2.0,  555),
                SIMD3<Float>(150,  1.0,  640),
                SIMD3<Float>( 45,  0.0,  590)    // Final corner onto the main straight
            ]
        case .redMesa:
            return [
                SIMD3<Float>(   0,  0.0,   430),
                SIMD3<Float>(   0,  0.0,   160),
                SIMD3<Float>(   0,  2.0,  -190),
                SIMD3<Float>(   5,  3.0,  -335),
                SIMD3<Float>(  70,  5.0,  -425),
                SIMD3<Float>( 185,  7.0,  -445),
                SIMD3<Float>( 310,  9.0,  -400),
                SIMD3<Float>( 440, 11.0,  -440),
                SIMD3<Float>( 580, 13.0,  -420),
                SIMD3<Float>( 645, 14.0,  -310),
                SIMD3<Float>( 570, 15.0,  -215),
                SIMD3<Float>( 430, 16.0,  -205),
                SIMD3<Float>( 310, 17.0,  -135),
                SIMD3<Float>( 300, 16.0,   -15),
                SIMD3<Float>( 400, 14.0,    65),
                SIMD3<Float>( 560, 12.0,    55),
                SIMD3<Float>( 690, 10.0,   115),
                SIMD3<Float>( 715,  9.0,   255),
                SIMD3<Float>( 625,  7.0,   355),
                SIMD3<Float>( 465,  6.0,   335),
                SIMD3<Float>( 335,  5.0,   385),
                SIMD3<Float>( 300,  3.0,   505),
                SIMD3<Float>( 205,  2.0,   595),
                SIMD3<Float>(  80,  1.0,   600),
                SIMD3<Float>(  10,  0.0,   535)
            ]
        case .cedarBasin:
            return [
                SIMD3<Float>(   0,  0.0,   430),
                SIMD3<Float>(   0,  0.0,   160),
                SIMD3<Float>(   0,  1.0,  -190),
                SIMD3<Float>(  10,  2.0,  -355),
                SIMD3<Float>( 110,  4.0,  -455),
                SIMD3<Float>( 255,  5.0,  -440),
                SIMD3<Float>( 330,  7.0,  -330),
                SIMD3<Float>( 305,  8.0,  -200),
                SIMD3<Float>( 370,  9.0,   -95),
                SIMD3<Float>( 500, 11.0,  -110),
                SIMD3<Float>( 600, 13.0,  -235),
                SIMD3<Float>( 750, 15.0,  -255),
                SIMD3<Float>( 860, 14.0,  -150),
                SIMD3<Float>( 850, 12.0,    10),
                SIMD3<Float>( 740, 10.0,    95),
                SIMD3<Float>( 580,  8.0,   115),
                SIMD3<Float>( 485,  7.0,   200),
                SIMD3<Float>( 500,  6.0,   325),
                SIMD3<Float>( 620,  5.0,   420),
                SIMD3<Float>( 605,  4.0,   545),
                SIMD3<Float>( 475,  3.0,   600),
                SIMD3<Float>( 340,  2.0,   525),
                SIMD3<Float>( 235,  2.0,   425),
                SIMD3<Float>( 140,  1.0,   445),
                SIMD3<Float>( 125,  1.0,   560),
                SIMD3<Float>(  60,  0.0,   615),
                SIMD3<Float>(   5,  0.0,   550)
            ]
        }
    }
}


final class LagunaSecaTrackBuilder {

    struct TrackSpline {
        let controlPoints: [SIMD3<Float>]
        let sampledPoints: [SIMD3<Float>]
        let cumulativeLengths: [Float]
        let totalLength: Float

        func sample(atDistance distance: Float) -> (position: SIMD3<Float>, tangent: SIMD3<Float>, curvature: Float, elevationDeltaAhead: Float) {
            guard sampledPoints.count >= 2, totalLength > 0.01 else {
                return (.zero, SIMD3<Float>(0, 0, -1), 0, 0)
            }

            var d = distance.truncatingRemainder(dividingBy: totalLength)
            if d < 0 { d += totalLength }

            var idx = 0
            while idx < cumulativeLengths.count - 2 && cumulativeLengths[idx + 1] < d {
                idx += 1
            }

            let segStartLen = cumulativeLengths[idx]
            let segEndLen = cumulativeLengths[idx + 1]
            let segLen = max(0.0001, segEndLen - segStartLen)
            let alpha = min(1, max(0, (d - segStartLen) / segLen))

            let p0 = sampledPoints[idx]
            let p1 = sampledPoints[idx + 1]
            let pos = simd_mix(p0, p1, SIMD3<Float>(repeating: alpha))

            let pNext = sampledPoints[(idx + 2) % sampledPoints.count]

            let t1 = simd_normalize(SIMD3<Float>(p1.x - p0.x, 0, p1.z - p0.z))
            let t2 = simd_normalize(SIMD3<Float>(pNext.x - p1.x, 0, pNext.z - p1.z))
            let crossY = t1.x * t2.z - t1.z * t2.x
            let curvature = crossY * 18.0

            // 75 m look-ahead for hills
            let lookAheadDist = (d + 75.0).truncatingRemainder(dividingBy: totalLength)
            let aheadSample = pointAt(distance: lookAheadDist)
            let elevationDeltaAhead = aheadSample.y - pos.y

            let tangent = simd_normalize(p1 - p0)
            return (pos, tangent, curvature, elevationDeltaAhead)
        }

        func pointAt(distance: Float) -> SIMD3<Float> {
            let n = min(sampledPoints.count, cumulativeLengths.count)
            guard n >= 2, distance.isFinite, totalLength.isFinite, totalLength > 0.01 else {
                return sampledPoints.first ?? .zero
            }

            var d = distance.truncatingRemainder(dividingBy: totalLength)
            if d < 0 { d += totalLength }

            var idx = 0
            while idx < n - 2 && cumulativeLengths[idx + 1] < d {
                idx += 1
            }

            let segLen = max(0.0001, cumulativeLengths[idx + 1] - cumulativeLengths[idx])
            let alpha = min(1, max(0, (d - cumulativeLengths[idx]) / segLen))
            return simd_mix(sampledPoints[idx], sampledPoints[idx + 1], SIMD3<Float>(repeating: alpha))
        }

        func closestTrackInfo(to worldPos: SIMD3<Float>) -> (distanceAlong: Float, lateralOffset: Float, trackCenter: SIMD3<Float>, tangent: SIMD3<Float>, curvature: Float, elevationDeltaAhead: Float) {
            guard !sampledPoints.isEmpty else {
                return (0, 0, .zero, SIMD3<Float>(0, 0, -1), 0, 0)
            }

            var bestIdx = 0
            var bestDistSq = Float.greatestFiniteMagnitude

            for (i, pt) in sampledPoints.enumerated() {
                let dx = worldPos.x - pt.x
                let dz = worldPos.z - pt.z
                let distSq = dx * dx + dz * dz
                if distSq < bestDistSq {
                    bestDistSq = distSq
                    bestIdx = i
                }
            }

            let center = sampledPoints[bestIdx]
            let nextPt = sampledPoints[(bestIdx + 1) % sampledPoints.count]
            let prevPt = sampledPoints[(bestIdx - 1 + sampledPoints.count) % sampledPoints.count]

            let tangent3D = simd_normalize(nextPt - prevPt)
            let flatTangent = simd_normalize(SIMD3<Float>(tangent3D.x, 0, tangent3D.z))
            let rightVec = SIMD3<Float>(-flatTangent.z, 0, flatTangent.x)

            let delta = SIMD3<Float>(worldPos.x - center.x, 0, worldPos.z - center.z)
            let lateralOffset = simd_dot(delta, rightVec)

            let tPrev = simd_normalize(SIMD3<Float>(center.x - prevPt.x, 0, center.z - prevPt.z))
            let tNext = simd_normalize(SIMD3<Float>(nextPt.x - center.x, 0, nextPt.z - center.z))
            let curvature = (tPrev.x * tNext.z - tPrev.z * tNext.x) * 18.0

            let distAlong = cumulativeLengths[bestIdx]
            let lookAhead = pointAt(distance: (distAlong + 75.0).truncatingRemainder(dividingBy: totalLength))
            let elevationDeltaAhead = lookAhead.y - center.y

            return (distAlong, lateralOffset, center, flatTangent, curvature, elevationDeltaAhead)
        }
    }

    /// Asphalt is 14 m wide (half-width = 7.0 m)
    static let trackHalfWidth: Float = 7.0

    /// Builds the centerline for one of the circuits. 1 unit = 1 meter.
    static func makeLagunaSecaSpline(for track: RaceTrack) -> TrackSpline {
        let rawPoints = track.controlPoints

        func sampleClosedCatmullRom(_ pts: [SIMD3<Float>], steps: Int) -> [SIMD3<Float>] {
            var result: [SIMD3<Float>] = []
            let count = pts.count
            for i in 0..<count {
                let p0 = pts[(i - 1 + count) % count]
                let p1 = pts[i]
                let p2 = pts[(i + 1) % count]
                let p3 = pts[(i + 2) % count]
                for s in 0..<steps {
                    let t = Float(s) / Float(steps)
                    let t2 = t * t
                    let t3 = t2 * t
                    let pt = 0.5 * (
                        (2 * p1) +
                        (-p0 + p2) * t +
                        (2 * p0 - 5 * p1 + 4 * p2 - p3) * t2 +
                        (-p0 + 3 * p1 - 3 * p2 + p3) * t3
                    )
                    result.append(pt)
                }
            }
            return result
        }

        // Measure the unscaled length, then scale XZ to the target lap length
        let initialSample = sampleClosedCatmullRom(rawPoints, steps: 32)
        var rawLength: Float = 0
        for i in 1..<initialSample.count {
            rawLength += simd_distance(initialSample[i - 1], initialSample[i])
        }
        rawLength += simd_distance(initialSample.last!, initialSample.first!)

        let targetLength = track.lapLength
        let xzScale = rawLength > 1 ? (targetLength / rawLength) : 1.0
        let scaledControlPoints = rawPoints.map {
            SIMD3<Float>($0.x * xzScale, $0.y, $0.z * xzScale)
        }

        let sampled = sampleClosedCatmullRom(scaledControlPoints, steps: 48)

        var lengths: [Float] = [0]
        var total: Float = 0
        for i in 1..<sampled.count {
            total += simd_distance(sampled[i - 1], sampled[i])
            lengths.append(total)
        }
        total += simd_distance(sampled.last!, sampled.first!)
        lengths.append(total)

        return TrackSpline(
            controlPoints: scaledControlPoints,
            sampledPoints: sampled,
            cumulativeLengths: lengths,
            totalLength: total
        )
    }

    static func buildTrack(in scene: SCNScene, spline: TrackSpline, track: RaceTrack) {
        let trackRoot = SCNNode()
        trackRoot.name = "RaceTrackRoot"

        let ground = SCNFloor()
        ground.reflectivity = 0.04
        let groundMat = SCNMaterial()
        groundMat.diffuse.contents = track.groundColor
        ground.materials = [groundMat]
        let groundNode = SCNNode(geometry: ground)
        groundNode.name = "TrackGround"
        groundNode.position = SCNVector3(0, -0.35, 0)
        groundNode.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        trackRoot.addChildNode(groundNode)

        var vertices: [SCNVector3] = []
        var indices: [Int32] = []
        var leftCurbVerts: [SCNVector3] = []
        var rightCurbVerts: [SCNVector3] = []
        var curbIndices: [Int32] = []

        let n = spline.sampledPoints.count
        for i in 0..<n {
            let curr = spline.sampledPoints[i]
            let next = spline.sampledPoints[(i + 1) % n]
            let prev = spline.sampledPoints[(i - 1 + n) % n]

            let tangent = simd_normalize(SIMD3<Float>(next.x - prev.x, 0, next.z - prev.z))
            let right = SIMD3<Float>(-tangent.z, 0, tangent.x)

            let halfW = trackHalfWidth
            let leftOuter = curr - right * halfW + SIMD3<Float>(0, 0.06, 0)
            let rightOuter = curr + right * halfW + SIMD3<Float>(0, 0.06, 0)

            vertices.append(SCNVector3(leftOuter))
            vertices.append(SCNVector3(rightOuter))

            let curbInnerW = halfW - 0.85
            leftCurbVerts.append(SCNVector3(curr - right * halfW + SIMD3<Float>(0, 0.11, 0)))
            leftCurbVerts.append(SCNVector3(curr - right * curbInnerW + SIMD3<Float>(0, 0.11, 0)))

            rightCurbVerts.append(SCNVector3(curr + right * curbInnerW + SIMD3<Float>(0, 0.11, 0)))
            rightCurbVerts.append(SCNVector3(curr + right * halfW + SIMD3<Float>(0, 0.11, 0)))

            let base = Int32(i * 2)
            let nextBase = Int32(((i + 1) % n) * 2)

            indices.append(contentsOf: [base, nextBase, base + 1])
            indices.append(contentsOf: [base + 1, nextBase, nextBase + 1])

            curbIndices.append(contentsOf: [base, nextBase, base + 1])
            curbIndices.append(contentsOf: [base + 1, nextBase, nextBase + 1])
        }

        let roadSource = SCNGeometrySource(vertices: vertices)
        let roadElement = SCNGeometryElement(indices: indices, primitiveType: .triangles)
        let roadGeo = SCNGeometry(sources: [roadSource], elements: [roadElement])
        let roadMat = SCNMaterial()
        roadMat.diffuse.contents = UIColor(red: 0.14, green: 0.15, blue: 0.18, alpha: 1.0)
        roadMat.roughness.contents = 0.75
        roadMat.isDoubleSided = true
        roadGeo.materials = [roadMat]

        let roadNode = SCNNode(geometry: roadGeo)
        roadNode.name = "TrackAsphalt"
        roadNode.physicsBody = SCNPhysicsBody(type: .static, shape: nil)
        trackRoot.addChildNode(roadNode)

        let curbElement = SCNGeometryElement(indices: curbIndices, primitiveType: .triangles)
        func makeCurbNode(verts: [SCNVector3], color: UIColor, name: String) -> SCNNode {
            let src = SCNGeometrySource(vertices: verts)
            let geo = SCNGeometry(sources: [src], elements: [curbElement])
            let mat = SCNMaterial()
            mat.diffuse.contents = color
            mat.isDoubleSided = true
            geo.materials = [mat]
            let node = SCNNode(geometry: geo)
            node.name = name
            return node
        }

        trackRoot.addChildNode(makeCurbNode(verts: leftCurbVerts, color: UIColor.systemRed.withAlphaComponent(0.9), name: "LeftCurb"))
        trackRoot.addChildNode(makeCurbNode(verts: rightCurbVerts, color: UIColor.white.withAlphaComponent(0.9), name: "RightCurb"))

        let startSample = spline.sample(atDistance: 0)
        let gantry = SCNNode()
        gantry.name = "StartFinishGantry"
        gantry.position = SCNVector3(startSample.position)
        let yaw = atan2(-startSample.tangent.x, -startSample.tangent.z)
        gantry.eulerAngles = SCNVector3(0, yaw, 0)

        let postGeo = SCNBox(width: 0.5, height: 7.5, length: 0.5, chamferRadius: 0.05)
        let postMat = SCNMaterial()
        postMat.diffuse.contents = UIColor.systemYellow
        postGeo.materials = [postMat]

        let leftPost = SCNNode(geometry: postGeo)
        leftPost.position = SCNVector3(-trackHalfWidth - 0.6, 3.75, 0)
        let rightPost = SCNNode(geometry: postGeo)
        rightPost.position = SCNVector3(trackHalfWidth + 0.6, 3.75, 0)

        let bannerGeo = SCNBox(width: CGFloat(trackHalfWidth * 2 + 1.7), height: 1.3, length: 0.4, chamferRadius: 0.04)
        let bannerMat = SCNMaterial()
        bannerMat.diffuse.contents = UIColor.systemRed
        bannerGeo.materials = [bannerMat]
        let banner = SCNNode(geometry: bannerGeo)
        banner.position = SCNVector3(0, 7.1, 0)

        gantry.addChildNode(leftPost)
        gantry.addChildNode(rightPost)
        gantry.addChildNode(banner)
        trackRoot.addChildNode(gantry)

        buildGuideFeatures(in: trackRoot, spline: spline)
        LagunaSecaGrandstand.add(to: trackRoot, spline: spline, trackName: track.name)

        scene.rootNode.addChildNode(trackRoot)
    }

    static func makeRaceCarNode(
        name: String,
        role: RaceCarRole,
        bodyColor: UIColor,
        accentColor: UIColor
    ) -> (root: SCNNode, cockpitCamera: SCNNode?) {
        let root = SCNNode()
        root.name = name

        let chassisMat = SCNMaterial()
        chassisMat.diffuse.contents = bodyColor
        chassisMat.roughness.contents = 0.25
        chassisMat.metalness.contents = 0.65

        let cabinMat = SCNMaterial()
        cabinMat.diffuse.contents = UIColor(red: 0.08, green: 0.10, blue: 0.14, alpha: 0.92)
        cabinMat.roughness.contents = 0.1

        let accentMat = SCNMaterial()
        accentMat.diffuse.contents = accentColor

        let tireMat = SCNMaterial()
        tireMat.diffuse.contents = UIColor(red: 0.07, green: 0.07, blue: 0.08, alpha: 1.0)
        tireMat.roughness.contents = 0.85

        // Real GT / prototype race car footprint (~4.6 m length, ~1.95 m width)
        let bodyGeo = SCNBox(width: 1.95, height: 0.62, length: 4.5, chamferRadius: 0.14)
        bodyGeo.materials = [chassisMat]
        let bodyNode = SCNNode(geometry: bodyGeo)
        bodyNode.name = "\(name)_Body"
        bodyNode.position = SCNVector3(0, 0.55, 0)
        root.addChildNode(bodyNode)

        let cabinGeo = SCNBox(width: 1.48, height: 0.46, length: 1.85, chamferRadius: 0.12)
        cabinGeo.materials = [cabinMat]
        let cabinNode = SCNNode(geometry: cabinGeo)
        cabinNode.position = SCNVector3(0, 1.02, 0.15)
        root.addChildNode(cabinNode)

        let wingGeo = SCNBox(width: 2.0, height: 0.12, length: 0.55, chamferRadius: 0.02)
        wingGeo.materials = [accentMat]
        let frontWing = SCNNode(geometry: wingGeo)
        frontWing.position = SCNVector3(0, 0.26, -2.15)
        root.addChildNode(frontWing)

        let rearWing = SCNNode(geometry: wingGeo)
        rearWing.position = SCNVector3(0, 1.08, 2.05)
        root.addChildNode(rearWing)

        let wheelGeo = SCNCylinder(radius: 0.36, height: 0.34)
        wheelGeo.materials = [tireMat]
        let wheelOffsets: [SCNVector3] = [
            SCNVector3(-1.02, 0.36, -1.45),
            SCNVector3( 1.02, 0.36, -1.45),
            SCNVector3(-1.02, 0.36,  1.45),
            SCNVector3( 1.02, 0.36,  1.45)
        ]

        for (idx, offset) in wheelOffsets.enumerated() {
            let wheel = SCNNode(geometry: wheelGeo)
            wheel.name = "\(name)_Wheel_\(idx)"
            wheel.position = offset
            wheel.eulerAngles = SCNVector3(0, 0, Float.pi / 2)
            root.addChildNode(wheel)
        }

        var cockpitCamera: SCNNode? = nil
        if role == .firstPersonPlayer {
            cabinNode.isHidden = true
            frontWing.isHidden = true
            let camNode = SCNNode()
            camNode.name = "FirstPersonDriverCamera"
            camNode.position = SCNVector3(0, 1.25, 0.1)
            camNode.camera = SCNCamera()
            camNode.camera?.fieldOfView = 76
            camNode.camera?.zNear = 0.2
            camNode.camera?.zFar = 1600
            root.addChildNode(camNode)
            cockpitCamera = camNode
        }

        return (root, cockpitCamera)
    }
}

extension LagunaSecaTrackBuilder.TrackSpline {

    /// Closest point on the centerline polyline (XZ plane). Projects onto segments,
    /// so the result is smooth between samples.
    func nearestCenterlinePoint(to worldPos: SIMD3<Float>) -> (point: SIMD3<Float>, tangent: SIMD3<Float>, distance: Float) {
        var bestPoint = sampledPoints.first ?? .zero
        var bestTangent = SIMD3<Float>(0, 0, -1)
        var bestDistSq = Float.greatestFiniteMagnitude
        let count = sampledPoints.count

        for i in 0..<count {
            let a = sampledPoints[i]
            let b = sampledPoints[(i + 1) % count]
            let abX = b.x - a.x
            let abZ = b.z - a.z
            let lenSq = abX * abX + abZ * abZ
            if lenSq < 0.0001 { continue }

            let t = max(0, min(1, ((worldPos.x - a.x) * abX + (worldPos.z - a.z) * abZ) / lenSq))
            let p = simd_mix(a, b, SIMD3<Float>(repeating: t))
            let dx = worldPos.x - p.x
            let dz = worldPos.z - p.z
            let distSq = dx * dx + dz * dz
            if distSq < bestDistSq {
                bestDistSq = distSq
                bestPoint = p
                bestTangent = simd_normalize(SIMD3<Float>(abX, 0, abZ))
            }
        }
        return (bestPoint, bestTangent, sqrt(bestDistSq))
    }

    /// Centerline position, flat forward direction and right direction at a lap distance.
    func frame(atDistance distance: Float) -> (position: SIMD3<Float>, forward: SIMD3<Float>, right: SIMD3<Float>) {
        let position = pointAt(distance: distance)
        let delta = pointAt(distance: distance + 3) - pointAt(distance: distance - 3)
        let forward = simd_normalize(SIMD3<Float>(delta.x, 0, delta.z))
        let right = SIMD3<Float>(-forward.z, 0, forward.x)
        return (position, forward, right)
    }
}

// MARK: - Turn arrows and guide barriers

extension LagunaSecaTrackBuilder {

    /// Guide barriers sit 50 ft (15.24 m) beyond each edge of the asphalt.
    static let barrierSetback: Float = 50.0 * 0.3048
    /// Distance from the centerline to each barrier.
    static let barrierOffset: Float = trackHalfWidth + barrierSetback

    private static let barrierHeight: Float = 1.1

    struct TrackTurn {
        var startDistance: Float
        var endDistance: Float
        var isRight: Bool
        var totalAngle: Float   // radians, always positive
    }

    /// Finds the turns from the track geometry itself, so arrows always match the road.
    static func detectTurns(spline: TrackSpline) -> [TrackTurn] {
        let step: Float = 2.0
        let count = Int(spline.totalLength / step)
        guard count > 12 else { return [] }

        func wrap(_ i: Int) -> Int { (i + count) % count }

        let headings: [Float] = (0..<count).map { i in
            let f = spline.frame(atDistance: Float(i) * step).forward
            return atan2(f.x, -f.z)   // increases when turning right
        }

        // Signed curvature (radians per meter), positive = right
        let curvature: [Float] = (0..<count).map { i in
            var d = headings[wrap(i + 3)] - headings[wrap(i - 3)]
            d = atan2(sin(d), cos(d))
            return d / (6 * step)
        }

        let threshold: Float = 1.0 / 160.0
        var turns: [TrackTurn] = []
        var i = 0
        while i < count {
            guard abs(curvature[i]) > threshold else {
                i += 1
                continue
            }
            let isRight = curvature[i] > 0
            var j = i
            var angle: Float = 0
            while j < count && abs(curvature[j]) > threshold && (curvature[j] > 0) == isRight {
                angle += abs(curvature[j]) * step
                j += 1
            }
            let turn = TrackTurn(
                startDistance: Float(i) * step,
                endDistance: Float(j - 1) * step,
                isRight: isRight,
                totalAngle: angle
            )
            if var last = turns.last, last.isRight == isRight, turn.startDistance - last.endDistance <= 20 {
                last.endDistance = turn.endDistance
                last.totalAngle += turn.totalAngle
                turns[turns.count - 1] = last
            } else {
                turns.append(turn)
            }
            i = j
        }

        // Ignore gentle kinks under 20 degrees
        return turns.filter { $0.totalAngle >= 20.0 * .pi / 180.0 }
    }

    static func buildGuideFeatures(in parent: SCNNode, spline: TrackSpline) {
        let turns = detectTurns(spline: spline)
        parent.addChildNode(makeRoadArrows(spline: spline, turns: turns))
        parent.addChildNode(makeBarriers(spline: spline))
        parent.addChildNode(makeChevronBoards(spline: spline, turns: turns))
    }

    // MARK: Road arrows

    private static func makeRoadArrows(spline: TrackSpline, turns: [TrackTurn]) -> SCNNode {
        var vertices: [SCNVector3] = []
        var indices: [Int32] = []

        // Arrow outline in (right, forward) meters, drawn bending to the right.
        let pieces: [[SIMD2<Float>]] = [
            // Straight shaft, split so it follows hills
            [SIMD2(-0.45, 0), SIMD2(0.45, 0), SIMD2(0.45, 2), SIMD2(-0.45, 2)],
            [SIMD2(-0.45, 2), SIMD2(0.45, 2), SIMD2(0.45, 4), SIMD2(-0.45, 4)],
            // Angled shaft
            [SIMD2(-0.45, 4), SIMD2(0.45, 4), SIMD2(2.20, 5.75), SIMD2(1.30, 6.65)],
            // Head
            [SIMD2(0.76, 7.19), SIMD2(2.74, 5.21), SIMD2(3.31, 7.76)]
        ]

        func addArrow(at distance: Float, isRight: Bool) {
            let mirror: Float = isRight ? 1 : -1
            for piece in pieces {
                let base = Int32(vertices.count)
                for corner in piece {
                    let f = spline.frame(atDistance: distance + corner.y)
                    let p = f.position + f.right * (corner.x * mirror) + SIMD3<Float>(0, 0.14, 0)
                    vertices.append(SCNVector3(p))
                }
                for k in 1..<(piece.count - 1) {
                    indices.append(contentsOf: [base, base + Int32(k), base + Int32(k + 1)])
                }
            }
        }

        for turn in turns {
            // Warning arrows on the approach, skipping any that would sit in another turn
            for lead: Float in [60, 38, 16] {
                let d = turn.startDistance - lead
                let insideOtherTurn = turns.contains { d + 8 >= $0.startDistance && d <= $0.endDistance }
                if !insideOtherTurn {
                    addArrow(at: d, isRight: turn.isRight)
                }
            }
            // Arrows through the turn
            var d = turn.startDistance + 6
            while d < turn.endDistance - 6 {
                addArrow(at: d, isRight: turn.isRight)
                d += 22
            }
        }

        let node = makeFlatNode(vertices: vertices, indices: indices, color: .systemYellow)
        node.name = "TurnArrows"
        node.castsShadow = false
        return node
    }

    // MARK: Guide barriers

    /// Point on one barrier line, or nil where that offset would fold back inside the
    /// run-off area (inside of tight turns).
    private static func barrierPoint(spline: TrackSpline, distance: Float, side: Float) -> SIMD3<Float>? {
        let f = spline.frame(atDistance: distance)
        let p = f.position + f.right * (side * barrierOffset)
        let nearest = spline.nearestCenterlinePoint(to: p)
        return nearest.distance >= barrierOffset - 0.3 ? p : nil
    }

    private static func makeBarriers(spline: TrackSpline) -> SCNNode {
        let root = SCNNode()
        root.name = "GuideBarriers"

        var redVerts: [SCNVector3] = []
        var redIndices: [Int32] = []
        var whiteVerts: [SCNVector3] = []
        var whiteIndices: [Int32] = []

        let step: Float = 2.0
        let count = Int(ceil(spline.totalLength / step))
        let up = SIMD3<Float>(0, barrierHeight, 0)

        func addWall(_ a: SIMD3<Float>, _ b: SIMD3<Float>, _ verts: inout [SCNVector3], _ idx: inout [Int32]) {
            let base = Int32(verts.count)
            verts.append(contentsOf: [SCNVector3(a), SCNVector3(b), SCNVector3(b + up), SCNVector3(a + up)])
            idx.append(contentsOf: [base, base + 1, base + 2, base, base + 2, base + 3])
        }

        for side: Float in [-1, 1] {
            let points: [SIMD3<Float>] = (0..<count).compactMap {
                barrierPoint(spline: spline, distance: Float($0) * step, side: side)
            }
            guard points.count > 1 else { continue }

            var run: Float = 0
            for i in points.indices {
                let a = points[i]
                let b = points[(i + 1) % points.count]
                let length = simd_distance(a, b)
                if length > 14 { continue }
                // Alternate red and white every 6 m so speed and distance are easy to read
                if Int(run / 6) % 2 == 0 {
                    addWall(a, b, &redVerts, &redIndices)
                } else {
                    addWall(a, b, &whiteVerts, &whiteIndices)
                }
                run += length
            }
        }

        root.addChildNode(makeFlatNode(vertices: redVerts, indices: redIndices, color: .systemRed))
        root.addChildNode(makeFlatNode(vertices: whiteVerts, indices: whiteIndices, color: UIColor(white: 0.92, alpha: 1)))
        return root
    }

    // MARK: Chevron boards on the outside of each turn

    private static func makeChevronBoards(spline: TrackSpline, turns: [TrackTurn]) -> SCNNode {
        let root = SCNNode()
        root.name = "ChevronBoards"

        func makeBoardGeometry(isRight: Bool) -> SCNPlane {
            let plane = SCNPlane(width: 3.2, height: 1.8)
            let material = SCNMaterial()
            material.lightingModel = .constant
            material.diffuse.contents = chevronImage(isRight: isRight)
            plane.materials = [material]
            return plane
        }

        let rightGeometry = makeBoardGeometry(isRight: true)
        let leftGeometry = makeBoardGeometry(isRight: false)

        for turn in turns {
            let outside: Float = turn.isRight ? -1 : 1
            var d = turn.startDistance - 8
            while d <= turn.endDistance {
                defer { d += 14 }
                guard let base = barrierPoint(spline: spline, distance: d, side: outside) else { continue }

                let f = spline.frame(atDistance: d)
                let inward = f.right * -outside
                // Angle each board halfway between the road and oncoming drivers
                let facing = simd_normalize(inward - f.forward)

                let board = SCNNode(geometry: turn.isRight ? rightGeometry : leftGeometry)
                board.position = SCNVector3(base + inward * 0.2 + SIMD3<Float>(0, barrierHeight + 0.9, 0))
                board.eulerAngles = SCNVector3(0, atan2(facing.x, facing.z), 0)
                board.castsShadow = false
                root.addChildNode(board)
            }
        }
        return root
    }

    private static func chevronImage(isRight: Bool) -> UIImage {
        let size = CGSize(width: 256, height: 144)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor.systemYellow.setFill()
            context.fill(CGRect(origin: .zero, size: size))

            UIColor.black.setFill()
            for offset: CGFloat in [20, 96, 172] {
                // Right-pointing chevron, mirrored for left turns
                let outline = [
                    CGPoint(x: offset, y: 16), CGPoint(x: offset + 30, y: 16),
                    CGPoint(x: offset + 66, y: 72), CGPoint(x: offset + 30, y: 128),
                    CGPoint(x: offset, y: 128), CGPoint(x: offset + 36, y: 72)
                ].map { CGPoint(x: isRight ? $0.x : size.width - $0.x, y: $0.y) }

                let path = UIBezierPath()
                path.move(to: outline[0])
                outline.dropFirst().forEach { path.addLine(to: $0) }
                path.close()
                path.fill()
            }
        }
    }

    // MARK: Shared mesh helper

    private static func makeFlatNode(vertices: [SCNVector3], indices: [Int32], color: UIColor) -> SCNNode {
        let geometry = SCNGeometry(
            sources: [SCNGeometrySource(vertices: vertices)],
            elements: [SCNGeometryElement(indices: indices, primitiveType: .triangles)]
        )
        let material = SCNMaterial()
        material.lightingModel = .constant
        material.diffuse.contents = color
        material.isDoubleSided = true
        geometry.materials = [material]
        return SCNNode(geometry: geometry)
    }
}
