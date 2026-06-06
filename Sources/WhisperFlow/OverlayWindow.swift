import AppKit
import QuartzCore

enum OverlayState {
    case idle
    case recording
    case transcribing
    case error(String)
}

final class OverlayWindow {
    static let expandedSize = CGSize(width: 88, height: 30)
    static let idleSize = CGSize(width: 32, height: 6)
    private static let bottomOffset: CGFloat = 10

    private var panel: NSPanel?
    private var indicator: IndicatorView?

    func show(state: OverlayState) {
        DispatchQueue.main.async { self.present(state: state) }
    }

    /// Legacy entry point — collapses the pill back to its idle dot.
    func hide() {
        show(state: .idle)
    }

    func update(level: Float) {
        DispatchQueue.main.async { self.indicator?.updateLevel(level) }
    }

    private func present(state: OverlayState) {
        if panel == nil { build() }
        guard let panel, let indicator else { return }

        indicator.setState(state)

        if let screen = NSScreen.main {
            let size = panel.frame.size
            let origin = NSPoint(
                x: screen.frame.midX - size.width / 2,
                y: screen.frame.minY + Self.bottomOffset
            )
            panel.setFrameOrigin(origin)
        }
        panel.orderFrontRegardless()
    }

    private func build() {
        // Panel is sized to the expanded pill (plus a hair of padding for the border /
        // shadow). The visible pill is a CALayer inside that animates between the idle
        // dot and the expanded shape.
        let panelSize = CGSize(
            width: Self.expandedSize.width + 4,
            height: Self.expandedSize.height + 4
        )
        let panel = NSPanel(
            contentRect: NSRect(origin: .zero, size: panelSize),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.isFloatingPanel = true
        panel.level = .statusBar
        panel.hasShadow = true
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.ignoresMouseEvents = true

        let container = NSView(frame: panel.contentView!.bounds)
        container.wantsLayer = true
        container.layer?.backgroundColor = NSColor.clear.cgColor
        container.autoresizingMask = [.width, .height]

        let indicator = IndicatorView(frame: container.bounds)
        indicator.autoresizingMask = [.width, .height]
        container.addSubview(indicator)

        panel.contentView = container
        self.panel = panel
        self.indicator = indicator
    }
}

private final class IndicatorView: NSView {
    private let pillLayer = CALayer()
    private var barLayers: [CALayer] = []
    private var dotLayers: [CALayer] = []
    private var errorLayer: CALayer?

    private static let barCount = 11
    private var levelHistory: [Float] = Array(repeating: 0.1, count: IndicatorView.barCount)
    private let minScale: CGFloat = 0.1
    private var isRecording = false
    private var currentPillSize: CGSize = OverlayWindow.idleSize
    private var transitionID = 0

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)
        wantsLayer = true
        layer?.masksToBounds = false

        pillLayer.backgroundColor = NSColor.black.cgColor
        pillLayer.borderColor = NSColor.white.withAlphaComponent(0.75).cgColor
        pillLayer.borderWidth = 1
        pillLayer.masksToBounds = true
        layer?.addSublayer(pillLayer)

        buildBars()
        buildDots()
        buildError()

        // Start collapsed.
        layoutPill(size: currentPillSize, animated: false)
    }
    required init?(coder: NSCoder) { fatalError() }

    override func layout() {
        super.layout()
        layoutPill(size: currentPillSize, animated: false)
    }

    func setState(_ state: OverlayState) {
        transitionID += 1
        let currentTransitionID = transitionID

        stopAnimations()
        hideAllIndicators()

        let target: CGSize
        let revealIndicators: () -> Void
        switch state {
        case .idle:
            isRecording = false
            target = OverlayWindow.idleSize
            revealIndicators = {}
        case .recording:
            isRecording = true
            target = OverlayWindow.expandedSize
            levelHistory = Array(repeating: 0.1, count: IndicatorView.barCount)
            revealIndicators = { [weak self] in
                self?.barLayers.forEach { $0.isHidden = false }
            }
        case .transcribing:
            isRecording = false
            target = OverlayWindow.expandedSize
            revealIndicators = { [weak self] in
                guard let self else { return }
                self.dotLayers.forEach { $0.isHidden = false }
                self.startDotAnimation()
            }
        case .error:
            isRecording = false
            target = OverlayWindow.expandedSize
            revealIndicators = { [weak self] in
                self?.errorLayer?.isHidden = false
            }
        }
        currentPillSize = target
        applyLevels(animated: false)
        layoutPill(size: target, animated: true) { [weak self] in
            guard let self, self.transitionID == currentTransitionID else { return }
            revealIndicators()
        }
    }

    func updateLevel(_ level: Float) {
        guard isRecording else { return }
        levelHistory.removeFirst()
        levelHistory.append(level)
        applyLevels(animated: true)
    }

    private func hideAllIndicators() {
        barLayers.forEach { $0.isHidden = true }
        dotLayers.forEach { $0.isHidden = true }
        errorLayer?.isHidden = true
    }

    private func stopAnimations() {
        (barLayers + dotLayers).forEach { $0.removeAllAnimations() }
    }

    private func layoutPill(size: CGSize, animated: Bool, completion: (() -> Void)? = nil) {
        let frame = CGRect(
            x: (bounds.width - size.width) / 2,
            y: (bounds.height - size.height) / 2,
            width: size.width, height: size.height
        )
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.12)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        CATransaction.setCompletionBlock(completion)
        pillLayer.frame = frame
        pillLayer.cornerRadius = size.height / 2

        CATransaction.begin()
        CATransaction.setDisableActions(true)
        layoutBars()
        layoutDots()
        layoutError()
        CATransaction.commit()

        CATransaction.commit()
    }

    // MARK: - Recording bars

    private func buildBars() {
        for _ in 0..<IndicatorView.barCount {
            let l = CALayer()
            l.backgroundColor = NSColor.white.cgColor
            l.cornerRadius = 1.25
            l.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            l.isHidden = true
            pillLayer.addSublayer(l)
            barLayers.append(l)
        }
    }

    private func layoutBars() {
        let barWidth: CGFloat = 2.5
        let spacing: CGFloat = 3
        let count = CGFloat(barLayers.count)
        let totalWidth = count * barWidth + (count - 1) * spacing
        let pb = pillLayer.bounds
        let startX = (pb.width - totalWidth) / 2
        let midY = pb.height / 2
        let h: CGFloat = max(pb.height - 2, 4)
        for (i, bar) in barLayers.enumerated() {
            let x = startX + CGFloat(i) * (barWidth + spacing)
            bar.bounds = CGRect(x: 0, y: 0, width: barWidth, height: h)
            bar.position = CGPoint(x: x + barWidth / 2, y: midY)
        }
    }

    private func applyLevels(animated: Bool) {
        CATransaction.begin()
        if animated {
            CATransaction.setAnimationDuration(0.08)
            CATransaction.setAnimationTimingFunction(CAMediaTimingFunction(name: .easeOut))
        } else {
            CATransaction.setDisableActions(true)
        }
        for (i, bar) in barLayers.enumerated() {
            let v = max(minScale, min(1.0, CGFloat(levelHistory[i])))
            bar.transform = CATransform3DMakeScale(1, v, 1)
        }
        CATransaction.commit()
    }

    // MARK: - Transcribing dots

    private func buildDots() {
        for _ in 0..<3 {
            let l = CALayer()
            l.backgroundColor = NSColor.white.cgColor
            l.isHidden = true
            pillLayer.addSublayer(l)
            dotLayers.append(l)
        }
    }

    private func layoutDots() {
        let dotSize: CGFloat = 5
        let spacing: CGFloat = 6
        let count = CGFloat(dotLayers.count)
        let totalWidth = count * dotSize + (count - 1) * spacing
        let pb = pillLayer.bounds
        let startX = (pb.width - totalWidth) / 2
        let midY = pb.height / 2
        for (i, dot) in dotLayers.enumerated() {
            let x = startX + CGFloat(i) * (dotSize + spacing)
            dot.frame = CGRect(x: x, y: midY - dotSize / 2, width: dotSize, height: dotSize)
            dot.cornerRadius = dotSize / 2
        }
    }

    private func startDotAnimation() {
        for (i, dot) in dotLayers.enumerated() {
            let anim = CAKeyframeAnimation(keyPath: "opacity")
            anim.values = [0.25, 1.0, 0.25]
            anim.keyTimes = [0, 0.5, 1.0]
            anim.duration = 1.0
            anim.repeatCount = .infinity
            anim.timeOffset = Double(i) * 0.2
            anim.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            dot.add(anim, forKey: "dots")
        }
    }

    // MARK: - Error dot

    private func buildError() {
        let l = CALayer()
        l.backgroundColor = NSColor.systemRed.cgColor
        l.isHidden = true
        pillLayer.addSublayer(l)
        errorLayer = l
    }

    private func layoutError() {
        let s: CGFloat = 8
        let pb = pillLayer.bounds
        errorLayer?.frame = CGRect(
            x: (pb.width - s) / 2,
            y: (pb.height - s) / 2,
            width: s, height: s
        )
        errorLayer?.cornerRadius = s / 2
    }
}
