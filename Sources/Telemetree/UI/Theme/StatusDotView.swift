import AppKit

/// The connection-status indicator, themed. Stands in for the source
/// spec's Touch Bar "touch dot" — the one element the spec makes each
/// theme's single accent identity most visible through.
final class StatusDotView: NSView {
    var isActive: Bool = false {
        didSet { updateAppearance() }
    }

    var theme: Theme {
        didSet { updateAppearance() }
    }

    private let gradientLayer = CAGradientLayer()
    private static let pulseKey = "pulse"

    init(theme: Theme) {
        self.theme = theme
        super.init(frame: .zero)
        wantsLayer = true
        gradientLayer.type = .radial
        gradientLayer.startPoint = CGPoint(x: 0.35, y: 0.7)
        gradientLayer.endPoint = CGPoint(x: 0.5, y: 0.5)
        layer?.addSublayer(gradientLayer)
        updateAppearance()
    }

    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func layout() {
        super.layout()
        gradientLayer.frame = bounds
        gradientLayer.cornerRadius = bounds.width / 2
    }

    private func updateAppearance() {
        gradientLayer.removeAnimation(forKey: Self.pulseKey)

        guard isActive else {
            gradientLayer.colors = [NSColor.tertiaryLabelColor.cgColor, NSColor.tertiaryLabelColor.cgColor]
            layer?.shadowOpacity = 0
            return
        }

        gradientLayer.colors = [theme.dotGradientStart.cgColor, theme.dotGradientEnd.cgColor]
        layer?.shadowColor = theme.dotGlow.cgColor
        layer?.shadowRadius = 4
        layer?.shadowOpacity = 1
        layer?.shadowOffset = .zero

        guard theme.pulseEnabled else { return }
        let pulse = CABasicAnimation(keyPath: "shadowRadius")
        pulse.fromValue = 3
        pulse.toValue = 6
        pulse.duration = 1.1
        pulse.autoreverses = true
        pulse.repeatCount = .infinity
        pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
        layer?.add(pulse, forKey: Self.pulseKey)
    }
}
