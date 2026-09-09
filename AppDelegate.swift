import AppKit
import Foundation

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var lidMenuItem: NSMenuItem!
    private var autoMenuItem: NSMenuItem!
    private var forceMenuItem: NSMenuItem!
    private var dimMenuItem: NSMenuItem!
    private var launchAtLoginItem: NSMenuItem!
    
    private let monitor = AudioSleepMonitor.shared
    private var signalSources: [DispatchSourceSignal] = []
    
    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.run()
    }
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        setupStatusItem()
        setupMonitorCallbacks()
        setupSignalHandlers()
        updateLaunchAtLoginState()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        monitor.shutdownCleanup()
    }
    
    /// `pkill` sender SIGTERM, blandt andet fra install.sh. Uden det her ville
    /// disablesleep blive staaende paa 1 og Mac'en ville aldrig sove igen.
    /// SIGKILL kan ikke fanges, det daekkes af nulstillingen ved opstart.
    private func setupSignalHandlers() {
        for sig in [SIGTERM, SIGINT, SIGHUP] {
            signal(sig, SIG_IGN)
            let source = DispatchSource.makeSignalSource(signal: sig, queue: .main)
            source.setEventHandler {
                AudioSleepMonitor.shared.shutdownCleanup()
                exit(0)
            }
            source.resume()
            signalSources.append(source)
        }
    }
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        
        if let button = statusItem.button {
            button.title = "💤"
            button.toolTip = "SmartSleep: Overvåger Spotify og Brave"
        }
        
        let menu = NSMenu()
        
        // Status header
        statusMenuItem = NSMenuItem(title: "Status: Søvn tilladt", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        // Lid state header
        lidMenuItem = NSMenuItem(title: "Skærmlåg: Åbent 💻", action: nil, keyEquivalent: "")
        lidMenuItem.isEnabled = false
        menu.addItem(lidMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Settings GUI window trigger
        let settingsItem = NSMenuItem(title: "Indstillinger...", action: #selector(openSettings), keyEquivalent: "")
        settingsItem.target = self
        menu.addItem(settingsItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Auto mode toggle
        autoMenuItem = NSMenuItem(title: "Automatisk dvalestyring (Spotify / Brave)", action: #selector(toggleAutoMode), keyEquivalent: "")
        autoMenuItem.target = self
        autoMenuItem.state = monitor.isAutoEnabled ? .on : .off
        menu.addItem(autoMenuItem)
        
        // Force wake toggle
        forceMenuItem = NSMenuItem(title: "Tving forbliv vågen (altid)", action: #selector(toggleForceMode), keyEquivalent: "")
        forceMenuItem.target = self
        forceMenuItem.state = monitor.isForceKeepAwake ? .on : .off
        menu.addItem(forceMenuItem)
        
        // Dim brightness toggle
        dimMenuItem = NSMenuItem(title: "Skru helt ned for skærmlys ved afspilning (spar strøm)", action: #selector(toggleDimMode), keyEquivalent: "")
        dimMenuItem.target = self
        dimMenuItem.state = monitor.isDimBrightnessEnabled ? .on : .off
        menu.addItem(dimMenuItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Launch at login toggle
        launchAtLoginItem = NSMenuItem(title: "Start automatisk ved login", action: #selector(toggleLaunchAtLogin), keyEquivalent: "")
        launchAtLoginItem.target = self
        menu.addItem(launchAtLoginItem)
        
        menu.addItem(NSMenuItem.separator())
        
        // Quit
        let quitItem = NSMenuItem(title: "Afslut SmartSleep", action: #selector(quitApp), keyEquivalent: "")
        quitItem.target = self
        menu.addItem(quitItem)
        
        statusItem.menu = menu
    }
    
    private func setupMonitorCallbacks() {
        monitor.addObserver(self) { [weak self] isMediaDetected, isSleepPrevented, isLidClosed, source, title, _ in
            DispatchQueue.main.async {
                self?.updateUI(isMediaDetected: isMediaDetected, isSleepPrevented: isSleepPrevented, isLidClosed: isLidClosed, source: source, title: title)
            }
        }
        monitor.checkMediaAndUpdate()
    }
    
    private func updateUI(isMediaDetected: Bool, isSleepPrevented: Bool, isLidClosed: Bool, source: String, title: String) {
        guard let button = statusItem.button else { return }
        
        lidMenuItem.title = isLidClosed ? "Skærmlåg: Lukket 📁" : "Skærmlåg: Åbent 💻"
        
        if isSleepPrevented {
            button.title = "🎵"
            let trackInfo = title.isEmpty ? source : "\(title) (\(source))"
            let srcText = source.isEmpty ? (monitor.isForceKeepAwake ? "Tvunget vågen" : "Aktiv lyd") : trackInfo
            statusMenuItem.title = "Status: 🟢 Søvn deaktiveret (\(srcText))"
            button.toolTip = "SmartSleep: Mac holdes vågen (\(srcText))"
        } else {
            button.title = "💤"
            statusMenuItem.title = "Status: 💤 Søvn tilladt (Ingen afspilning)"
            button.toolTip = "SmartSleep: Mac sover normalt ved lukket låg"
        }
        
        autoMenuItem.state = monitor.isAutoEnabled ? .on : .off
        forceMenuItem.state = monitor.isForceKeepAwake ? .on : .off
        dimMenuItem.state = monitor.isDimBrightnessEnabled ? .on : .off
    }
    
    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow()
    }
    
    @objc private func toggleAutoMode() {
        monitor.isAutoEnabled.toggle()
        autoMenuItem.state = monitor.isAutoEnabled ? .on : .off
    }
    
    @objc private func toggleForceMode() {
        monitor.isForceKeepAwake.toggle()
        forceMenuItem.state = monitor.isForceKeepAwake ? .on : .off
    }
    
    @objc private func toggleDimMode() {
        monitor.isDimBrightnessEnabled.toggle()
        dimMenuItem.state = monitor.isDimBrightnessEnabled ? .on : .off
    }
    
    @objc private func toggleLaunchAtLogin() {
        let plistPath = launchAgentPlistPath()
        let fm = FileManager.default
        
        if fm.fileExists(atPath: plistPath) {
            try? fm.removeItem(atPath: plistPath)
            launchAtLoginItem.state = .off
        } else {
            createLaunchAgentPlist()
            launchAtLoginItem.state = .on
        }
    }
    
    private func updateLaunchAtLoginState() {
        let plistPath = launchAgentPlistPath()
        launchAtLoginItem.state = FileManager.default.fileExists(atPath: plistPath) ? .on : .off
    }
    
    private func launchAgentPlistPath() -> String {
        let home = NSHomeDirectory()
        return "\(home)/Library/LaunchAgents/com.personal.SmartSleep.plist"
    }
    
    private func createLaunchAgentPlist() {
        let appPath = Bundle.main.bundlePath
        let executablePath = "\(appPath)/Contents/MacOS/SmartSleep"
        
        let plistContent = """
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
        <plist version="1.0">
        <dict>
            <key>Label</key>
            <string>com.personal.SmartSleep</string>
            <key>ProgramArguments</key>
            <array>
                <string>\(executablePath)</string>
            </array>
            <key>RunAtLoad</key>
            <true/>
            <key>KeepAlive</key>
            <false/>
        </dict>
        </plist>
        """
        
        let folder = (launchAgentPlistPath() as NSString).deletingLastPathComponent
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true)
        try? plistContent.write(toFile: launchAgentPlistPath(), atomically: true, encoding: .utf8)
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
