import AppKit
import QuartzCore

enum OverlayState {
    case idle
    case recording
    case transcribing
    case error(String)
}

final class OverlayWindow {
    static let expandedSize = CGSize(width: 79.2, height: 30)
    static let idleSize = CGSize(width: 28.8, height: 6)
    private static let bottomOffset: CGFloat = 10
    /// How long the small pill rises before it starts expanding, so the growth happens
    /// after it has cleared the bottom edge rather than while still hidden below it.
    private static let expandDelay: TimeInterval = 0.09

    private var panel: NSPanel?
    private var indicator: IndicatorView?

    /// When true, the pill is parked off-screen below the bottom edge while idle and
    /// only rises into view (sliding up + expanding) while dictating.
    private var hideWhenIdle = false
    /// Whether the panel is currently up in view (at its resting spot) vs parked below.
    private var panelVisible = false
    /// Whether the most recent state was idle — a hide-mode toggle uses this to decide
    /// whether to re-present now or wait until dictation ends.
    private var lastStateWasIdle = true
    /// The first show snaps into place without a slide (nothing should move on launch).
    private var hasPresented = false
    /// Bumped on every present() so a stale slide completion can't hide a panel that
    /// has since been shown again.
    private var slideToken = 0

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

    /// Turn hide mode on/off. When idle, the change animates immediately: turning it on
    /// slides the pill down off the bottom edge; turning it off slides it back up and
    /// settles it as the idle dot. While dictating, it takes effect the next time the
    /// pill returns to idle.
    func setHideWhenIdle(_ value: Bool) {
        DispatchQueue.main.async {
            guard self.hideWhenIdle != value else { return }
            self.hideWhenIdle = value
            if self.lastStateWasIdle { self.present(state: .idle) }
        }
    }

    private func restingOrigin(size: CGSize, screen: NSScreen) -> NSPoint {
        NSPoint(x: screen.frame.midX - size.width / 2,
                y: screen.frame.minY + Self.bottomOffset)
    }

    private func hiddenOrigin(size: CGSize, screen: NSScreen) -> NSPoint {
        // Fully below the bottom edge so nothing (not even the shadow) peeks through.
        NSPoint(x: screen.frame.midX - size.width / 2,
                y: screen.frame.minY - size.height)
    }

    private func present(state: OverlayState) {
        if panel == nil { build() }
        guard let panel, let indicator, let screen = NSScreen.main else { return }

        let size = panel.frame.size
        let resting = restingOrigin(size: size, screen: screen)
        let hidden = hiddenOrigin(size: size, screen: screen)
        let isIdle: Bool = { if case .idle = state { return true } else { return false } }()
        lastStateWasIdle = isIdle

        // The pill belongs on screen for any active state, and for idle only when hide
        // mode is off. Idle + hide mode is the one case it should be parked below.
        let wantVisible = !isIdle || !hideWhenIdle

        // Any new presentation supersedes a pending slide's completion (prevents a stale
        // "sink down" from hiding a panel that Fn has just brought back up).
        slideToken += 1
        let token = slideToken

        // First show ever just snaps into place — nothing should slide on launch.
        if !hasPresented {
            hasPresented = true
            indicator.setState(wantVisible ? state : .idle)
            panel.setFrameOrigin(wantVisible ? resting : hidden)
            if wantVisible { panel.orderFrontRegardless() } else { panel.orderOut(nil) }
            panelVisible = wantVisible
            return
        }

        if wantVisible {
            if panelVisible {
                // Already up — the pill just resizes in place.
                indicator.setState(state)
            } else {
                // Emerge from the bottom as the small idle pill, then expand into the
                // active shape once it has cleared the edge — so the growth is visible.
                indicator.setState(.idle)
                panel.setFrameOrigin(hidden)
                panel.orderFrontRegardless()
                slide(panel, size: size, to: resting, completion: nil)
                DispatchQueue.main.asyncAfter(deadline: .now() + Self.expandDelay) { [weak self] in
                    guard let self, self.slideToken == token else { return }
                    self.indicator?.setState(state)
                }
            }
            panelVisible = true
        } else {
            if panelVisible {
                // Mirror of the entrance: collapse toward the small pill *while* it sinks
                // (rather than fully collapsing first), then park it out of sight.
                indicator.setState(.idle)
                slide(panel, size: size, to: hidden) { [weak self] in
                    guard let self, self.slideToken == token else { return }
                    panel.orderOut(nil)
                }
            } else {
                // Already parked below.
                indicator.setState(.idle)
                panel.setFrameOrigin(hidden)
                panel.orderOut(nil)
            }
            panelVisible = false
        }
    }

    private func slide(_ panel: NSPanel, size: CGSize, to origin: NSPoint, completion: (() -> Void)?) {
        // Animate the window's *frame* (its animatable property) — animating
        // setFrameOrigin alone does not tween, it jumps.
        NSAnimationContext.runAnimationGroup({ context in
            context.duration = 0.22
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(CGRect(origin: origin, size: size), display: true)
        }, completionHandler: completion)
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

final class IndicatorView: NSView {
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
        pillLayer.borderColor = NSColor.white.withAlphaComponent(0.5175).cgColor
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

    /// `completion` fires once the pill has finished resizing to `state` (or immediately
    /// if a newer state superseded this one). Used to chain the collapse → slide-down.
    func setState(_ state: OverlayState, completion: (() -> Void)? = nil) {
        transitionID += 1
        let currentTransitionID = transitionID

        stopAnimations()
        hideAllIndicators()
        // Ignore startup levels while the pill opens. Otherwise a key/click or mic
        // startup transient is already in the history when the bars appear, then
        // travels left across the waveform for the next half second.
        isRecording = false

        let target: CGSize
        let revealIndicators: () -> Void
        switch state {
        case .idle:
            target = OverlayWindow.idleSize
            revealIndicators = {}
        case .recording:
            target = OverlayWindow.expandedSize
            levelHistory = Array(repeating: 0.1, count: IndicatorView.barCount)
            revealIndicators = { [weak self] in
                guard let self else { return }
                self.barLayers.forEach { $0.isHidden = false }
                self.isRecording = true
            }
        case .transcribing:
            target = OverlayWindow.expandedSize
            revealIndicators = { [weak self] in
                guard let self else { return }
                self.dotLayers.forEach { $0.isHidden = false }
                self.startDotAnimation()
            }
        case .error:
            target = OverlayWindow.expandedSize
            revealIndicators = { [weak self] in
                self?.errorLayer?.isHidden = false
            }
        }
        currentPillSize = target
        applyLevels(animated: false)
        layoutPill(size: target, animated: true) { [weak self] in
            guard let self, self.transitionID == currentTransitionID else { completion?(); return }
            // Visibility must snap after the resize, just as it does when hiding.
            // An implicit `hidden` animation can reveal indicators during the resize.
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            revealIndicators()
            CATransaction.commit()
            completion?()
        }
    }

    func updateLevel(_ level: Float) {
        guard isRecording else { return }
        levelHistory.removeFirst()
        levelHistory.append(level)
        applyLevels(animated: true)
    }

    private func hideAllIndicators() {
        // Disable implicit actions so `isHidden` snaps off instantly. Otherwise the dots
        // fade out over the default ~0.25s while `removeAllAnimations()` has just snapped
        // their opacity back to full — which reads as a flicker as the pill collapses.
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        barLayers.forEach { $0.isHidden = true }
        dotLayers.forEach { $0.isHidden = true }
        errorLayer?.isHidden = true
        CATransaction.commit()
    }

    private func stopAnimations() {
        CATransaction.begin()
        CATransaction.setDisableActions(true)
        (barLayers + dotLayers).forEach { $0.removeAllAnimations() }
        CATransaction.commit()
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
            l.backgroundColor = NSColor(white: 0.8625, alpha: 1).cgColor
            l.cornerRadius = 1.1
            l.anchorPoint = CGPoint(x: 0.5, y: 0.5)
            l.isHidden = true
            pillLayer.addSublayer(l)
            barLayers.append(l)
        }
    }

    private func layoutBars() {
        let barWidth: CGFloat = 2.2
        let spacing: CGFloat = 2.5
        let count = CGFloat(barLayers.count)
        let totalWidth = count * barWidth + (count - 1) * spacing
        let pb = pillLayer.bounds
        let startX = (pb.width - totalWidth) / 2
        let midY = pb.height / 2
        let h: CGFloat = max(pb.height - 4, 4)
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
