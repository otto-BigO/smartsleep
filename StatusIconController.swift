import AppKit

enum IconAnimation: String, CaseIterable {
    case bars, pulse, off
    
    static let defaultsKey = "SmartSleep.iconAnimation"
    static let changedNotification = Notification.Name("SmartSleep.iconAnimationChanged")
    
    var title: String {
        switch self {
        case .bars: return "Bjælker"
        case .pulse: return "Puls"
        case .off: return "Fra"
        }
    }
    
    static var current: IconAnimation {
        get { IconAnimation(rawValue: UserDefaults.standard.string(forKey: defaultsKey) ?? "") ?? .bars }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: defaultsKey)
            NotificationCenter.default.post(name: changedNotification, object: nil)
        }
    }
}

/// Tegner ikonet i menulinjen. Et stille symbol naar intet spiller, og en animation
/// naar musik holder Mac'en vaagen.
final class StatusIconController {
    private let button: NSStatusBarButton
    private var symbol = "moon.zzz"
    private var isPlaying = false
    private var iconDescription = "SmartSleep"
    private var screensAsleep = false
    
    private var barsTimer: Timer?
    private var bars: [Bar] = (0..<4).map { _ in Bar() }
    private var pulseView: NSImageView?
    
    /// Symbolet til Apples indbyggede animation. Skal have variable lag for at kunne animeres.
    static let pulseSymbolName = "waveform"
    private let symbolConfig = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    
    /// En bjaelke glider mod et tilfaeldigt maal og vaelger et nyt naar den er fremme.
    /// Det giver en roligere bevaegelse end at hoppe direkte mellem tilfaeldige hoejder.
    private struct Bar {
        var height = CGFloat.random(in: 0.2...1)
        var target = CGFloat.random(in: 0.2...1)
        var speed = CGFloat.random(in: 0.2...0.4)
        
        mutating func step() {
            height += (target - height) * speed
            if abs(target - height) < 0.05 {
                target = .random(in: 0.15...1)
                speed = .random(in: 0.18...0.4)
            }
        }
    }
    
    init(button: NSStatusBarButton) {
        self.button = button
        
        NotificationCenter.default.addObserver(forName: IconAnimation.changedNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        // Ingen grund til at tegne naar skaermen er slukket, fx med lukket laag.
        let workspace = NSWorkspace.shared.notificationCenter
        workspace.addObserver(forName: NSWorkspace.screensDidSleepNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = true
            self?.refresh()
        }
        workspace.addObserver(forName: NSWorkspace.screensDidWakeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.screensAsleep = false
            self?.refresh()
        }
        workspace.addObserver(forName: NSWorkspace.accessibilityDisplayOptionsDidChangeNotification, object: nil, queue: .main) { [weak self] _ in
            self?.refresh()
        }
        refresh()
    }
    
    func update(symbol: String, isPlaying: Bool, description: String) {
        self.symbol = symbol
        self.isPlaying = isPlaying
        self.iconDescription = description
        refresh()
    }
    
    private var activeAnimation: IconAnimation {
        guard isPlaying, !screensAsleep, !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion else { return .off }
        return IconAnimation.current
    }
    
    private func refresh() {
        switch activeAnimation {
        case .bars:
            stopPulse()
            startBars()
        case .pulse:
            stopBars()
            if !startPulse() { showStatic() }
        case .off:
            stopBars()
            stopPulse()
            showStatic()
        }
    }
    
    private func showStatic() {
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: iconDescription)?
            .withSymbolConfiguration(symbolConfig)
        image?.isTemplate = true
        button.image = image
    }
    
    // MARK: - Bjaelker
    
    private func startBars() {
        guard barsTimer == nil else { return }
        drawBars()
        // .common saa den ogsaa animerer mens menuen er aaben.
        let timer = Timer(timeInterval: 1.0 / 15.0, repeats: true) { [weak self] _ in
            guard let self else { return }
            for index in self.bars.indices {
                self.bars[index].step()
            }
            self.drawBars()
        }
        RunLoop.main.add(timer, forMode: .common)
        barsTimer = timer
    }
    
    private func stopBars() {
        barsTimer?.invalidate()
        barsTimer = nil
    }
    
    private func drawBars() {
        let heights = bars.map { $0.height }
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { rect in
            let barWidth: CGFloat = 2.5
            let gap: CGFloat = 1.8
            let minHeight: CGFloat = 3
            let maxHeight: CGFloat = 14
            let totalWidth = CGFloat(heights.count) * barWidth + CGFloat(heights.count - 1) * gap
            var x = (rect.width - totalWidth) / 2
            NSColor.black.setFill()
            for height in heights {
                let barHeight = minHeight + (maxHeight - minHeight) * height
                let bar = NSRect(x: x, y: (rect.height - barHeight) / 2, width: barWidth, height: barHeight)
                NSBezierPath(roundedRect: bar, xRadius: barWidth / 2, yRadius: barWidth / 2).fill()
                x += barWidth + gap
            }
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = iconDescription
        button.image = image
    }
    
    // MARK: - Puls (Apples indbyggede symbol-animation, macOS 14+)
    
    private func startPulse() -> Bool {
        guard #available(macOS 14.0, *) else { return false }
        if pulseView != nil { return true }
        guard let image = NSImage(systemSymbolName: Self.pulseSymbolName, accessibilityDescription: iconDescription)?
            .withSymbolConfiguration(symbolConfig) else { return false }
        image.isTemplate = true
        
        let view = NSImageView(image: image)
        view.translatesAutoresizingMaskIntoConstraints = false
        button.image = nil
        button.addSubview(view)
        NSLayoutConstraint.activate([
            view.centerXAnchor.constraint(equalTo: button.centerXAnchor),
            view.centerYAnchor.constraint(equalTo: button.centerYAnchor),
        ])
        view.addSymbolEffect(.variableColor.iterative.reversing, options: .repeating)
        pulseView = view
        return true
    }
    
    private func stopPulse() {
        guard let view = pulseView else { return }
        if #available(macOS 14.0, *) {
            view.removeAllSymbolEffects()
        }
        view.removeFromSuperview()
        pulseView = nil
    }
}
