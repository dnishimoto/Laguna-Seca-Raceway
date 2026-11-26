//
//  File.swift
//  Laguna Seca Raceway
//
//  Created by David Nishimoto on 11/25/26.
//

import Foundation
import SwiftUI
import SceneKit


struct LagunaSecaRaceSceneRepresentable: UIViewRepresentable {
    @Binding var thumbInput: ThumbInputState
    @Binding var animationSpeed: Double
    @Binding var resetCounter: Int
    @Binding var telemetry: [RaceCarTelemetry]
    @Binding var caGeneration: Int
    @Binding var caLiveCells: Int

    final class Holder {
        var coordinator: LagunaSecaRaceCoordinator?
        var lastResetCounter: Int = 0
    }

    func makeCoordinator() -> Holder {
        Holder()
    }

    func makeUIView(context: Context) -> SCNView {
        let view = SCNView(frame: .zero)
        let scene = SCNScene()
        scene.background.contents = UIColor(red: 0.55, green: 0.74, blue: 0.92, alpha: 1.0)

        let spline = LagunaSecaTrackBuilder.makeLagunaSecaSpline()
        LagunaSecaTrackBuilder.buildTrack(in: scene, spline: spline)

        let ambient = SCNNode()
        let ambientLight = SCNLight()
        ambientLight.type = .ambient
        ambientLight.intensity = 550
        ambient.light = ambientLight
        scene.rootNode.addChildNode(ambient)

        let sun = SCNNode()
        let sunLight = SCNLight()
        sunLight.type = .directional
        sunLight.intensity = 1100
        sunLight.castsShadow = true
        sun.light = sunLight
        sun.eulerAngles = SCNVector3(-Float.pi / 3, Float.pi / 5, 0)
        scene.rootNode.addChildNode(sun)

        let coord = LagunaSecaRaceCoordinator(scene: scene, spline: spline)
        coord.animationSpeed = animationSpeed
        coord.onTelemetryUpdate = { items, gen, live in
            self.telemetry = items
            self.caGeneration = gen
            self.caLiveCells = live
        }

        context.coordinator.coordinator = coord
        view.scene = scene
        if let fpCam = scene.rootNode.childNode(withName: "FirstPersonDriverCamera", recursively: true) {
            view.pointOfView = fpCam
        }
        view.delegate = coord
        view.isPlaying = true
        view.rendersContinuously = true
        view.allowsCameraControl = false

        return view
    }

    func updateUIView(_ uiView: SCNView, context: Context) {
        guard let coord = context.coordinator.coordinator else { return }
        coord.thumbInput = thumbInput
        coord.animationSpeed = animationSpeed

        if resetCounter != context.coordinator.lastResetCounter {
            context.coordinator.lastResetCounter = resetCounter
            // The coordinator also switches the view to the new driver camera
            coord.resetRace()
        }
    }
}
