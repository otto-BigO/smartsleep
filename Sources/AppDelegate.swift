import AppKit
import Foundation

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var iconController: StatusIconController!
    private var statusMenuItem: NSMenuItem!
    private var nowPlayingMenuItem: NSMenuItem!
    private var autoMenuItem: NSMenuItem!
    private var forceMenuItem: NSMenuItem!
    private var lidPermissionMenuItem: NSMenuItem!
    
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
        checkLidPermission()
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        monitor.shutdownCleanup()
    }
    
    /// Aabnes appen igen mens den koerer (fx fra Finder eller Spotlight), vises indstillingerne.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        monitor.recheckLidPermission()
        openSettings()
        return false
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
    
    // MARK: - Menulinje
    
    private func setupStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        iconController = StatusIconController(button: statusItem.button!)
        logStatusItemFrame()
        
        let menu = NSMenu()
        
        statusMenuItem = NSMenuItem(title: "Mac can sleep", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        nowPlayingMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        nowPlayingMenuItem.isEnabled = false
        nowPlayingMenuItem.isHidden = true
        menu.addItem(nowPlayingMenuItem)
        
        // Vises kun naar sudoers-reglen mangler, fx efter en installation fra DMG'en.
        lidPermissionMenuItem = makeItem("Enable Lid-Closed Mode…", action: #selector(askForLidPermission))
        lidPermissionMenuItem.isHidden = true
        menu.addItem(lidPermissionMenuItem)
        
        menu.addItem(.separator())
        
        autoMenuItem = makeItem("Keep awake while playing", action: #selector(toggleAutoMode))
        menu.addItem(autoMenuItem)
        forceMenuItem = makeItem("Always stay awake", action: #selector(toggleForceMode))
        menu.addItem(forceMenuItem)
        
        menu.addItem(.separator())
        
        menu.addItem(makeItem("Settings…", action: #selector(openSettings), key: ","))
        menu.addItem(makeItem("Quit SmartSleep", action: #selector(quitApp), key: "q"))
        
        statusItem.menu = menu
    }
    
    private func makeItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
    
    /// Position i skaermkoordinater med origo oeverst til venstre, som screencapture -R bruger.
    /// Praktisk til at optage ikonet, fordi macOS ikke viser menulinje-ikoner som app-vinduer.
    private func logStatusItemFrame() {
        DispatchQueue.main.asyncAfter(deadline: .now() + 1) { [weak self] in
            guard let frame = self?.statusItem.button?.window?.frame,
                  let screen = NSScreen.screens.first else { return }
            let top = screen.frame.height - frame.maxY
            appLog.notice("Menulinje-ikon: \(Int(frame.minX)),\(Int(top)),\(Int(frame.width)),\(Int(frame.height))")
        }
    }
    
    private func setupMonitorCallbacks() {
        monitor.addObserver(self) { [weak self] isMediaDetected, isSleepPrevented, _, source, title, _ in
            DispatchQueue.main.async {
                self?.updateUI(isMediaDetected: isMediaDetected, isSleepPrevented: isSleepPrevented, source: source, title: title)
            }
        }
        monitor.checkMediaAndUpdate()
    }
    
    private func updateUI(isMediaDetected: Bool, isSleepPrevented: Bool, source: String, title: String) {
        let isForced = monitor.isForceKeepAwake && !isMediaDetected
        
        let isPaused = !monitor.isAutoEnabled && !monitor.isForceKeepAwake
        let statusText: String
        if isPaused {
            statusText = "Paused. Mac sleeps as usual"
        } else if !isSleepPrevented {
            statusText = "Mac can sleep"
        } else if isForced {
            statusText = "Staying awake (forced)"
        } else if !source.isEmpty {
            statusText = "Staying awake: \(source)"
        } else {
            statusText = "Staying awake"
        }
        
        let symbol = StatusSymbol.name(isSleepPrevented: isSleepPrevented, isMediaDetected: isMediaDetected, isForced: monitor.isForceKeepAwake, isPaused: isPaused)
        iconController.update(symbol: symbol, isPlaying: isSleepPrevented && isMediaDetected, description: statusText)
        statusItem.button?.toolTip = "SmartSleep: \(statusText)"
        statusMenuItem.title = statusText
        
        // Lange videotitler ville goere hele menuen bred.
        nowPlayingMenuItem.title = title.count > 42 ? String(title.prefix(41)) + "…" : title
        nowPlayingMenuItem.isHidden = title.isEmpty || !isSleepPrevented
        
        autoMenuItem.state = monitor.isAutoEnabled ? .on : .off
        forceMenuItem.state = monitor.isForceKeepAwake ? .on : .off
        lidPermissionMenuItem.isHidden = monitor.hasLidPermission
    }
    
    // MARK: - Handlinger
    
    // MARK: - Tilladelse til lukket laag
    
    private static let lidPermissionDeclinedKey = "SmartSleep.lidPermissionDeclined"
    
    /// Spoerger ved foerste start hvis reglen mangler. Siger man nej, spoerges der ikke igen,
    /// men menupunktet bliver staaende.
    private func checkLidPermission() {
        lidPermissionMenuItem.isHidden = monitor.hasLidPermission
        guard !monitor.hasLidPermission,
              !UserDefaults.standard.bool(forKey: Self.lidPermissionDeclinedKey) else { return }
        DispatchQueue.main.async { [weak self] in
            self?.askForLidPermission()
        }
    }
    
    @objc private func askForLidPermission() {
        NSApp.activate(ignoringOtherApps: true)
        let alert = NSAlert()
        alert.icon = NSApp.applicationIconImage
        alert.messageText = "Keep playing with the lid closed?"
        alert.informativeText = """
        To stop your Mac from sleeping when the lid closes, SmartSleep needs to run pmset \
        without a password. macOS asks for your password once to allow it.
        
        Without it, SmartSleep still keeps the Mac awake while music plays, but only with \
        the lid open.
        """
        alert.addButton(withTitle: "Allow")
        alert.addButton(withTitle: "Not Now")
        
        if alert.runModal() == .alertFirstButtonReturn {
            if SleepPermission.install() {
                monitor.recheckLidPermission()
            }
        } else {
            UserDefaults.standard.set(true, forKey: Self.lidPermissionDeclinedKey)
        }
        lidPermissionMenuItem.isHidden = monitor.hasLidPermission
    }
    
    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow()
    }
    
    @objc private func toggleAutoMode() {
        monitor.isAutoEnabled.toggle()
        appLog.notice("Keep awake while playing slaaet \(self.monitor.isAutoEnabled ? "til" : "fra", privacy: .public) i menuen")
    }
    
    @objc private func toggleForceMode() {
        monitor.isForceKeepAwake.toggle()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
