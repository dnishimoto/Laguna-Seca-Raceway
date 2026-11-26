//
//  File.swift
//  Laguna Seca Raceway
//
//  Created by David Nishimoto on 11/25/26.
//

import Foundation
import SceneKit
import UIKit
import simd

/// A covered grandstand of cheering fans beside the start straight.
enum LagunaSecaGrandstand {

    private static let centerDistance: Float = 95     // meters past the start line
    private static let frontLateral: Float = 25       // from centerline, + = right (rail is at 22.24)
    private static let length: Float = 90
    private static let rows = 6
    private static let rowDepth: Float = 1.6
    private static let rowRise: Float = 0.75
    private static let firstRowHeight: Float = 1.5    // high enough to see over the guard rail

    // Fans are merged into a few moving groups so hundreds of them stay cheap to draw
    private static let sections = 12
    private static let groupsPerSection = 3

    static func add(to parent: SCNNode, spline: LagunaSecaTrackBuilder.TrackSpline) {
        let frame = spline.frame(atDistance: centerDistance)

        // Local axes: +x points away from the track on the right, -z is race direction
        let stand = SCNNode()
        stand.name = "Grandstand"
        stand.position = SCNVector3(frame.position.x, -0.35, frame.position.z)
        stand.eulerAngles = SCNVector3(0, atan2(-frame.forward.x, -frame.forward.z), 0)

        addStructure(to: stand)
        addCrowd(to: stand)
        addFlags(to: stand)

        parent.addChildNode(stand)
    }

    private static func material(_ color: UIColor) -> SCNMaterial {
        let m = SCNMaterial()
        m.diffuse.contents = color
        return m
    }

    private static func box(_ width: Float, _ height: Float, _ depth: Float,
                            _ material: SCNMaterial, at position: SIMD3<Float>) -> SCNNode {
        let geometry = SCNBox(width: CGFloat(width), height: CGFloat(height),
                              length: CGFloat(depth), chamferRadius: 0)
        geometry.materials = [material]
        let node = SCNNode(geometry: geometry)
        node.position = SCNVector3(position)
        return node
    }

    private static func rowTop(_ row: Int) -> Float {
        firstRowHeight + Float(row) * rowRise
    }

    // MARK: - Stand, roof and banner

    private static func addStructure(to stand: SCNNode) {
        let concrete = material(UIColor(white: 0.62, alpha: 1))
        let darkConcrete = material(UIColor(white: 0.48, alpha: 1))
        let steel = material(UIColor(white: 0.30, alpha: 1))
        let roofPaint = material(UIColor(red: 0.72, green: 0.10, blue: 0.10, alpha: 1))

        for row in 0..<rows {
            let height = rowTop(row)
            let x = frontLateral + (Float(row) + 0.5) * rowDepth
            stand.addChildNode(box(rowDepth, height, length,
                                   row % 2 == 0 ? concrete : darkConcrete,
                                   at: SIMD3<Float>(x, height / 2, 0)))
        }

        let backX = frontLateral + Float(rows) * rowDepth
        let roofHeight = rowTop(rows - 1) + 3.6

        stand.addChildNode(box(0.4, roofHeight, length, steel,
                               at: SIMD3<Float>(backX + 0.2, roofHeight / 2, 0)))
        stand.addChildNode(box(Float(rows) * rowDepth + 1.2, 0.3, length + 2, roofPaint,
                               at: SIMD3<Float>(frontLateral + Float(rows) * rowDepth / 2, roofHeight, 0)))

        // Slim posts at the two ends only, so they do not block the view of the crowd
        for z in [-length / 2, length / 2] {
            stand.addChildNode(box(0.3, roofHeight, 0.3, steel,
                                   at: SIMD3<Float>(frontLateral, roofHeight / 2, z)))
        }

        let banner = SCNPlane(width: 36, height: 2.2)
        let bannerMaterial = SCNMaterial()
        bannerMaterial.lightingModel = .constant
        bannerMaterial.diffuse.contents = bannerImage()
        banner.materials = [bannerMaterial]
        let bannerNode = SCNNode(geometry: banner)
        bannerNode.position = SCNVector3(frontLateral - 0.65, roofHeight + 1.25, 0)
        bannerNode.eulerAngles = SCNVector3(0, -Float.pi / 2, 0)   // faces the track
        stand.addChildNode(bannerNode)
    }

    private static func bannerImage() -> UIImage {
        let size = CGSize(width: 1152, height: 70)
        return UIGraphicsImageRenderer(size: size).image { context in
            UIColor(red: 0.05, green: 0.08, blue: 0.20, alpha: 1).setFill()
            context.fill(CGRect(origin: .zero, size: size))

            let style = NSMutableParagraphStyle()
            style.alignment = .center
            let attributes: [NSAttributedString.Key: Any] = [
                .font: UIFont.systemFont(ofSize: 48, weight: .heavy),
                .foregroundColor: UIColor.systemYellow,
                .paragraphStyle: style
            ]
            ("LAGUNA SECA FAN ZONE" as NSString)
                .draw(in: CGRect(x: 0, y: 6, width: size.width, height: 60), withAttributes: attributes)
        }
    }

    // MARK: - Cheering crowd

    private static func addCrowd(to stand: SCNNode) {
        let shirtColors: [UIColor] = [.systemRed, .systemBlue, .systemYellow, .systemGreen,
                                      .systemOrange, .systemPurple, .white, .systemTeal]
        let skinColors: [UIColor] = [
            UIColor(red: 0.96, green: 0.80, blue: 0.67, alpha: 1),
            UIColor(red: 0.78, green: 0.57, blue: 0.41, alpha: 1),
            UIColor(red: 0.45, green: 0.30, blue: 0.20, alpha: 1)
        ]

        // Shared geometry: one torso and arm per shirt color, one head per skin tone
        let torsos: [SCNGeometry] = shirtColors.map { color in
            let g = SCNBox(width: 0.34, height: 0.78, length: 0.52, chamferRadius: 0.08)
            g.materials = [material(color)]
            return g
        }
        let arms: [SCNGeometry] = shirtColors.map { color in
            let g = SCNBox(width: 0.12, height: 0.68, length: 0.12, chamferRadius: 0)
            g.materials = [material(color)]
            return g
        }
        let heads: [SCNGeometry] = skinColors.map { color in
            let g = SCNSphere(radius: 0.22)
            g.segmentCount = 8
            g.materials = [material(color)]
            return g
        }

        let groups: [SCNNode] = (0..<(sections * groupsPerSection)).map { _ in SCNNode() }
        let seatSpacing: Float = 1.05
        let seats = Int((length - 2) / seatSpacing)

        for row in 0..<rows {
            for seat in 0..<seats where Float.random(in: 0..<1) < 0.92 {
                let z = -length / 2 + 1.5 + Float(seat) * seatSpacing + Float.random(in: -0.12...0.12)
                let x = frontLateral + (Float(row) + 0.5) * rowDepth + Float.random(in: -0.2...0.2)

                let shirt = Int.random(in: 0..<torsos.count)
                let fan = SCNNode()
                fan.position = SCNVector3(x, rowTop(row), z)
                let size = Float.random(in: 0.88...1.1)
                fan.scale = SCNVector3(size, size, size)

                let torso = SCNNode(geometry: torsos[shirt])
                torso.position = SCNVector3(0, 0.39, 0)
                fan.addChildNode(torso)

                let head = SCNNode(geometry: heads.randomElement())
                head.position = SCNVector3(0, 1.0, 0)
                fan.addChildNode(head)

                // Arms raised in a cheering V
                let spread = Float.random(in: 0.25...0.75)
                for sideSign: Float in [-1, 1] {
                    let arm = SCNNode(geometry: arms[shirt])
                    arm.position = SCNVector3(0, 1.02, sideSign * 0.40)
                    arm.eulerAngles = SCNVector3(sideSign * spread, 0, 0)
                    fan.addChildNode(arm)
                }

                let section = min(sections - 1, seat * sections / seats)
                groups[section * groupsPerSection + Int.random(in: 0..<groupsPerSection)].addChildNode(fan)
            }
        }

        for (index, group) in groups.enumerated() {
            let merged = group.flattenedClone()
            merged.castsShadow = false
            stand.addChildNode(merged)

            let section = index / groupsPerSection
            let jumpHeight = CGFloat.random(in: 0.22...0.5)
            let jumpTime = Double.random(in: 0.16...0.28)

            let up = SCNAction.moveBy(x: 0, y: jumpHeight, z: 0, duration: jumpTime)
            up.timingMode = .easeOut
            let down = SCNAction.moveBy(x: 0, y: -jumpHeight, z: 0, duration: jumpTime)
            down.timingMode = .easeIn
            let pause = SCNAction.wait(duration: 0.12, withRange: 0.2)

            let cheer = SCNAction.sequence([up, down, up, down, up, down, pause])
            // Staggered starts make the cheering ripple along the stand like a wave
            let startDelay = SCNAction.wait(duration: Double(section) * 0.14, withRange: 0.15)
            merged.runAction(.sequence([startDelay, .repeatForever(cheer)]))
        }
    }

    // MARK: - Waving flags

    private static func addFlags(to stand: SCNNode) {
        let poleMaterial = material(UIColor(white: 0.85, alpha: 1))
        let colors: [UIColor] = [.systemRed, .white, .systemBlue, .systemYellow]
        let flagCount = 12

        for i in 0..<flagCount {
            let row = i % rows
            let x = frontLateral + (Float(row) + 0.5) * rowDepth - 0.35
            let z = -length / 2 + (Float(i) + 0.5) * length / Float(flagCount)

            // The holder pivots at the fan's hands
            let holder = SCNNode()
            holder.position = SCNVector3(x, rowTop(row) + 1.2, z)
            holder.eulerAngles = SCNVector3(-0.45, 0, 0)
            holder.addChildNode(box(0.07, 2.0, 0.07, poleMaterial, at: SIMD3<Float>(0, 1.0, 0)))

            let cloth = box(0.04, 0.8, 1.3, material(colors[i % colors.count]),
                            at: SIMD3<Float>(0, 1.6, 0.68))
            holder.addChildNode(cloth)

            let swing = SCNAction.rotateBy(x: 0.9, y: 0, z: 0, duration: Double.random(in: 0.35...0.6))
            swing.timingMode = .easeInEaseOut
            holder.runAction(.repeatForever(.sequence([swing, swing.reversed()])))
            stand.addChildNode(holder)
        }
    }
}
