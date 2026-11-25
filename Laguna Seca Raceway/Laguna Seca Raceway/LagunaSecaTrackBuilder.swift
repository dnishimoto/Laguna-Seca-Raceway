import SceneKit
import UIKit
import simd

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

            // 75 m look-ahead scaled for 3,602 m circuit
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

    /// Real-world Laguna Seca asphalt width is ~14 m (half-width = 7.0 m)
    static let trackHalfWidth: Float = 7.0

    /// 1:1 Meter-scale Laguna Seca circuit (~3,602 m lap length, 55 m climb to Corkscrew)
    static func makeLagunaSecaSpline() -> TrackSpline {
        // Base control points modeled on actual Laguna Seca geometry (1 unit = 1 meter)
        let rawPoints: [SIMD3<Float>] = [
            SIMD3<Float>(   0,  0.0,  340),   // Start / Finish line
            SIMD3<Float>(   0,  0.5, -180),   // Front straight into Turn 1 crest
            SIMD3<Float>( -55,  2.5, -340),   // Turn 1 fast left kink
            SIMD3<Float>(-195,  1.0, -455),   // Turn 2 (Andretti Hairpin) entry
            SIMD3<Float>(-275,  1.5, -365),   // Turn 2 hairpin apex & exit
            SIMD3<Float>(-240,  4.0, -170),   // Short chute to Turn 3
            SIMD3<Float>(-350,  6.5,  -75),   // Turn 3 right-hander
            SIMD3<Float>(-490,  9.5, -135),   // Straight toward Turn 4
            SIMD3<Float>(-620, 12.0,  -20),   // Turn 4 right-hander
            SIMD3<Float>(-645, 16.5,  230),   // Straight to Turn 5
            SIMD3<Float>(-565, 22.0,  390),   // Turn 5 uphill left-hander
            SIMD3<Float>(-415, 34.0,  475),   // Rahal Straight climb
            SIMD3<Float>(-330, 44.0,  615),   // Turn 6 fast uphill left
            SIMD3<Float>(-210, 52.5,  695),   // Steep climb toward Turn 7
            SIMD3<Float>(-125, 55.0,  645),   // Turn 7 crest / Corkscrew approach (+55 m peak)
            SIMD3<Float>( -85, 49.0,  575),   // Turn 8 (Corkscrew left entry)
            SIMD3<Float>( -35, 37.0,  535),   // Turn 8A (Corkscrew plunge -18 m drop)
            SIMD3<Float>(  35, 24.5,  615),   // Turn 9 (Rainey Curve fast downhill left)
            SIMD3<Float>( 195, 11.0,  675),   // Approach to Turn 10
            SIMD3<Float>( 335,  3.5,  585),   // Turn 10 downhill right-hander
            SIMD3<Float>( 285,  1.0,  435),   // Straight to Turn 11
            SIMD3<Float>( 145,  0.0,  455),   // Turn 11 tight hairpin onto main straight
            SIMD3<Float>(  20,  0.0,  415)    // Final straight alignment
        ]

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

        // Measure unscaled length and normalize XZ to exact 3,602 m official circuit length
        let initialSample = sampleClosedCatmullRom(rawPoints, steps: 32)
        var rawLength: Float = 0
        for i in 1..<initialSample.count {
            rawLength += simd_distance(initialSample[i - 1], initialSample[i])
        }
        rawLength += simd_distance(initialSample.last!, initialSample.first!)

        let targetLength: Float = 3602.0
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

    static func buildTrack(in scene: SCNScene, spline: TrackSpline) {
        let trackRoot = SCNNode()
        trackRoot.name = "LagunaSecaTrackRoot"

        let ground = SCNFloor()
        ground.reflectivity = 0.04
        let groundMat = SCNMaterial()
        groundMat.diffuse.contents = UIColor(red: 0.24, green: 0.31, blue: 0.19, alpha: 1.0)
        ground.materials = [groundMat]
        let groundNode = SCNNode(geometry: ground)
        groundNode.name = "LagunaGround"
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
        roadNode.name = "LagunaAsphalt"
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
