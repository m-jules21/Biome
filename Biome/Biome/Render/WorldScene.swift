import SpriteKit
import UIKit

/// Rendu et entrées du monde : SpriteKit affiche, SwiftUI pilote.
final class WorldScene: SKScene, UIGestureRecognizerDelegate {
    weak var model: GameModel?

    private let worldNode = SKNode()
    private let animalLayer = SKNode()
    private let fxLayer = SKNode()
    private let cameraNode = SKCameraNode()
    private let selectionRing = SKShapeNode(circleOfRadius: 1)
    private var ground: SKSpriteNode?
    private var animalNodes: [Int: SKSpriteNode] = [:]
    private var renderedIDs = Set<Int>()

    private var lastUpdate: TimeInterval = 0
    private var groundClock: Double = 0
    private var uiClock: Double = 0
    private var saveClock: Double = 0
    private var dragging = false
    private var lastPaintPoint = CGPoint.zero
    private var didSetup = false

    private var circleTexture: SKTexture?
    private var triangleTexture: SKTexture?

    private var minZoom: CGFloat = 0.5
    private var maxZoom: CGFloat = 3.0

    init(size: CGSize = CGSize(width: 400, height: 800)) {
        super.init(size: size)
        scaleMode = .resizeFill
        anchorPoint = .zero
    }

    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
        scaleMode = .resizeFill
        anchorPoint = .zero
    }

    override func didMove(to view: SKView) {
        guard !didSetup else { return }
        didSetup = true

        backgroundColor = Palette.ocean.color
        worldNode.zPosition = 0
        addChild(worldNode)
        worldNode.addChild(animalLayer)
        worldNode.addChild(fxLayer)
        animalLayer.zPosition = 10
        fxLayer.zPosition = 20

        selectionRing.strokeColor = UIColor(white: 1, alpha: 0.95)
        selectionRing.lineWidth = 1.6
        selectionRing.fillColor = .clear
        selectionRing.zPosition = 30
        selectionRing.isHidden = true
        let pulse = SKAction.sequence([
            SKAction.scale(to: 1.25, duration: 0.55),
            SKAction.scale(to: 0.9, duration: 0.55)
        ])
        selectionRing.run(SKAction.repeatForever(pulse))
        worldNode.addChild(selectionRing)

        addChild(cameraNode)
        camera = cameraNode

        circleTexture = Self.makeTexture(points: false)
        triangleTexture = Self.makeTexture(points: true)

        installGestures(on: view)
        reloadWorld()
    }

    // MARK: - Construction / reconstruction

    func reloadWorld() {
        guard let model else { return }
        for node in animalNodes.values { node.removeFromParent() }
        animalNodes.removeAll(keepingCapacity: true)
        animalLayer.removeAllChildren()
        fxLayer.removeAllChildren()
        renderedIDs.removeAll(keepingCapacity: true)

        let world = model.eco.world
        let worldSize = CGSize(
            width: CGFloat(world.width) * CGFloat(Tuning.cellSize),
            height: CGFloat(world.height) * CGFloat(Tuning.cellSize)
        )

        ground?.removeFromParent()
        let node = SKSpriteNode(texture: nil, size: worldSize)
        node.anchorPoint = .zero
        node.position = .zero
        node.zPosition = 0
        if let image = GroundTexture.image(for: world, phase: model.eco.dayPhase) {
            let texture = SKTexture(image: image)
            texture.filteringMode = .nearest
            node.texture = texture
        }
        worldNode.addChild(node)
        ground = node

        worldNode.childNode(withName: "worldFrame")?.removeFromParent()
        let frame = SKShapeNode(rect: CGRect(origin: .zero, size: worldSize))
        frame.strokeColor = UIColor(white: 0.55, alpha: 0.25)
        frame.lineWidth = 2
        frame.fillColor = .clear
        frame.zPosition = 1
        frame.name = "worldFrame"
        worldNode.addChild(frame)

        cameraNode.position = CGPoint(x: worldSize.width / 2, y: worldSize.height / 2)
        fitCamera(reset: true)
        lastUpdate = 0
    }

    private func fitCamera(reset: Bool) {
        guard let view, let model else { return }
        let bounds = view.bounds.size
        guard bounds.width > 1, bounds.height > 1 else { return }
        let world = model.eco.world
        let w = CGFloat(world.width) * CGFloat(Tuning.cellSize)
        let h = CGFloat(world.height) * CGFloat(Tuning.cellSize)
        let fit = min(bounds.width / w, bounds.height / h)
        minZoom = fit * 0.85
        maxZoom = fit * 4.0
        if reset {
            cameraNode.setScale(fit)
            cameraNode.position = CGPoint(x: w / 2, y: h / 2)
        }
    }

    // MARK: - Boucle

    override func update(_ currentTime: TimeInterval) {
        guard let model else { return }
        if lastUpdate == 0 { lastUpdate = currentTime }
        var delta = currentTime - lastUpdate
        lastUpdate = currentTime
        if delta < 0 { delta = 0 }
        if delta > 0.12 { delta = 0.12 }

        model.advance(dt: delta)
        renderAnimals()
        updateSelection()

        groundClock += delta
        if groundClock >= 0.20 {
            groundClock = 0
            refreshGround()
        }

        uiClock += delta
        if uiClock >= 0.22 {
            uiClock = 0
            model.pushUI()
            drainEffects()
        }

        saveClock += delta
        if saveClock >= 45, !model.isPaused {
            saveClock = 0
            model.saveGame()
        }
    }

    private func refreshGround() {
        guard let model, let ground else { return }
        guard let image = GroundTexture.image(for: model.eco.world, phase: model.eco.dayPhase) else { return }
        let texture = SKTexture(image: image)
        texture.filteringMode = .nearest
        ground.texture = texture
    }

    // MARK: - Individus

    private func renderAnimals() {
        guard let model else { return }
        renderedIDs.removeAll(keepingCapacity: true)
        let cell = CGFloat(Tuning.cellSize)

        for animal in model.eco.animals where animal.alive {
            renderedIDs.insert(animal.id)
            let node: SKSpriteNode
            if let existing = animalNodes[animal.id] {
                node = existing
            } else {
                node = SKSpriteNode(texture: animal.species == .carnivore ? triangleTexture : circleTexture)
                node.colorBlendFactor = 1
                node.zPosition = 10
                animalNodes[animal.id] = node
                animalLayer.addChild(node)
            }
            node.position = CGPoint(x: CGFloat(animal.x), y: CGFloat(animal.y))
            let body = cell * (1.15 + animal.genome.size * 0.85)
            node.size = CGSize(width: body, height: body)
            node.zRotation = CGFloat(animal.heading)
            let saturation: CGFloat = animal.species == .carnivore ? 0.85 : 0.55
            let brightness: CGFloat = animal.energy < animal.maxEnergy * 0.25 ? 0.7 : 1.0
            node.color = UIColor(
                hue: CGFloat(animal.genome.hue),
                saturation: saturation,
                brightness: brightness,
                alpha: 1
            )
            node.alpha = animal.species == .carnivore ? 1.0 : 0.92
        }
        removeDeadNodes()
    }

    private func removeDeadNodes() {
        var dead: [Int] = []
        for (id, _) in animalNodes where !renderedIDs.contains(id) {
            dead.append(id)
        }
        guard !dead.isEmpty else { return }
        for id in dead {
            guard let node = animalNodes.removeValue(forKey: id) else { continue }
            node.run(SKAction.sequence([
                SKAction.group([
                    SKAction.fadeOut(withDuration: 0.3),
                    SKAction.scale(to: 0.05, duration: 0.3)
                ]),
                SKAction.removeFromParent()
            ]))
        }
    }

    private func updateSelection() {
        guard let model else { return }
        guard let selected = model.selected else {
            selectionRing.isHidden = true
            return
        }
        selectionRing.isHidden = false
        selectionRing.position = CGPoint(x: CGFloat(selected.x), y: CGFloat(selected.y))
        let radius = CGFloat(Tuning.cellSize) * (1.6 + selected.genome.size)
        selectionRing.path = CGPath(ellipseIn: CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2), transform: nil)
        selectionRing.strokeColor = selected.species == .carnivore
            ? UIColor(red: 1, green: 0.45, blue: 0.35, alpha: 1)
            : UIColor(red: 0.55, green: 0.95, blue: 0.75, alpha: 1)
    }

    // MARK: - Effets

    private func drainEffects() {
        guard let model else { return }
        let effects = model.eco.pullEffects()
        for point in effects.births.prefix(8) {
            burst(at: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)), color: UIColor(red: 0.7, green: 1, blue: 0.8, alpha: 1), count: 3, radius: 8)
        }
        for point in effects.deaths.prefix(8) {
            burst(at: CGPoint(x: CGFloat(point.x), y: CGFloat(point.y)), color: UIColor(red: 0.9, green: 0.55, blue: 0.4, alpha: 1), count: 4, radius: 10)
        }
    }

    private func burst(at position: CGPoint, color: UIColor, count: Int, radius: CGFloat) {
        for index in 0..<count {
            let dot = SKShapeNode(circleOfRadius: 1.4)
            dot.fillColor = color
            dot.strokeColor = .clear
            dot.position = position
            dot.zPosition = 22
            fxLayer.addChild(dot)

            let angle = CGFloat(index) / CGFloat(max(1, count)) * .pi * 2 + CGFloat.random(in: 0...0.6)
            let distance = radius * CGFloat.random(in: 0.5...1.2)
            let move = SKAction.moveBy(x: cos(angle) * distance, y: sin(angle) * distance, duration: 0.5)
            move.timingMode = .easeOut
            dot.run(SKAction.sequence([
                SKAction.group([move, SKAction.fadeOut(withDuration: 0.5)]),
                SKAction.removeFromParent()
            ]))
        }
    }

    private func shake(intensity: CGFloat) {
        let move = SKAction.sequence([
            SKAction.moveBy(x: intensity, y: -intensity, duration: 0.03),
            SKAction.moveBy(x: -intensity * 2, y: intensity, duration: 0.05),
            SKAction.moveBy(x: intensity, y: intensity, duration: 0.04),
            SKAction.moveBy(x: -intensity * 0.5, y: -intensity * 0.5, duration: 0.04)
        ])
        cameraNode.run(move)
    }

    // MARK: - Gestes caméra

    private func installGestures(on view: SKView) {
        let pinch = UIPinchGestureRecognizer(target: self, action: #selector(handlePinch(_:)))
        pinch.delegate = self
        view.addGestureRecognizer(pinch)

        let pan = UIPanGestureRecognizer(target: self, action: #selector(handlePan(_:)))
        pan.minimumNumberOfTouches = 2
        pan.maximumNumberOfTouches = 2
        pan.delegate = self
        view.addGestureRecognizer(pan)
    }

    @objc private func handlePinch(_ gesture: UIPinchGestureRecognizer) {
        guard gesture.state == .changed else { return }
        let ratio = 1 / max(0.05, gesture.scale)
        let target = cameraNode.xScale * ratio
        cameraNode.setScale(min(max(target, minZoom), maxZoom))
        gesture.scale = 1
        clampCamera()
    }

    @objc private func handlePan(_ gesture: UIPanGestureRecognizer) {
        guard gesture.state == .changed, let view else { return }
        let translation = gesture.translation(in: view)
        let scale = cameraNode.xScale
        cameraNode.position.x -= translation.x * scale
        cameraNode.position.y += translation.y * scale
        gesture.setTranslation(.zero, in: view)
        clampCamera()
    }

    private func clampCamera() {
        guard let view, let model else { return }
        let scale = cameraNode.xScale
        let halfW = view.bounds.width * 0.5 * scale
        let halfH = view.bounds.height * 0.5 * scale
        let world = model.eco.world
        let w = CGFloat(world.width) * CGFloat(Tuning.cellSize)
        let h = CGFloat(world.height) * CGFloat(Tuning.cellSize)
        var x = cameraNode.position.x
        var y = cameraNode.position.y
        x = w > halfW * 2 ? min(max(x, halfW), w - halfW) : w / 2
        y = h > halfH * 2 ? min(max(y, halfH), h - halfH) : h / 2
        cameraNode.position = CGPoint(x: x, y: y)
    }

    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }

    // MARK: - Toucher

    override func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard let model, touches.count == 1, let touch = touches.first else { return }
        let point = touch.location(in: worldNode)
        if model.tool == .inspect {
            model.select(at: point)
            return
        }
        dragging = true
        lastPaintPoint = point
        model.applyTool(at: point)
    }

    override func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent?) {
        guard dragging, let model, touches.count == 1, let touch = touches.first else { return }
        switch model.tool {
        case .inspect, .herbivore, .carnivore, .meteor:
            return
        case .water, .rock, .plant:
            break
        }
        let point = touch.location(in: worldNode)
        let dx = point.x - lastPaintPoint.x
        let dy = point.y - lastPaintPoint.y
        guard dx * dx + dy * dy > 42 else { return }
        lastPaintPoint = point
        model.applyTool(at: point)
    }

    override func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragging = false
    }

    override func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent?) {
        dragging = false
    }

    // MARK: - Textures procédurales

    private static func makeTexture(points: Bool) -> SKTexture {
        let size = CGSize(width: 40, height: 40)
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { context in
            let cg = context.cgContext
            cg.setFillColor(UIColor.white.cgColor)
            if points {
                cg.move(to: CGPoint(x: 20, y: 3))
                cg.addLine(to: CGPoint(x: 37, y: 32))
                cg.addLine(to: CGPoint(x: 3, y: 32))
                cg.closePath()
                cg.fillPath()
            } else {
                cg.fillEllipse(in: CGRect(x: 4, y: 4, width: 32, height: 32))
            }
        }
        let texture = SKTexture(image: image)
        texture.filteringMode = .linear
        return texture
    }
}
