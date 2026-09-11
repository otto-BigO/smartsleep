import AppKit
import Foundation

@main
class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: NSStatusItem!
    private var statusMenuItem: NSMenuItem!
    private var nowPlayingMenuItem: NSMenuItem!
    private var autoMenuItem: NSMenuItem!
    private var forceMenuItem: NSMenuItem!
    
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
    }
    
    func applicationWillTerminate(_ notification: Notification) {
        monitor.shutdownCleanup()
    }
    
    /// Aabnes appen igen mens den koerer (fx fra Finder eller Spotlight), vises indstillingerne.
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
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
        setStatusIcon("moon.zzz", description: "Mac'en må sove")
        
        let menu = NSMenu()
        
        statusMenuItem = NSMenuItem(title: "Mac'en må sove", action: nil, keyEquivalent: "")
        statusMenuItem.isEnabled = false
        menu.addItem(statusMenuItem)
        
        nowPlayingMenuItem = NSMenuItem(title: "", action: nil, keyEquivalent: "")
        nowPlayingMenuItem.isEnabled = false
        nowPlayingMenuItem.isHidden = true
        menu.addItem(nowPlayingMenuItem)
        
        menu.addItem(.separator())
        
        autoMenuItem = makeItem("Automatisk ved lyd", action: #selector(toggleAutoMode))
        menu.addItem(autoMenuItem)
        forceMenuItem = makeItem("Hold altid vågen", action: #selector(toggleForceMode))
        menu.addItem(forceMenuItem)
        
        menu.addItem(.separator())
        
        menu.addItem(makeItem("Indstillinger…", action: #selector(openSettings), key: ","))
        menu.addItem(makeItem("Afslut SmartSleep", action: #selector(quitApp), key: "q"))
        
        statusItem.menu = menu
    }
    
    private func makeItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }
    
    /// Template-billede, saa ikonet foelger menulinjens lyse eller moerke udseende.
    private func setStatusIcon(_ symbol: String, description: String) {
        guard let button = statusItem.button else { return }
        let config = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
        let image = NSImage(systemSymbolName: symbol, accessibilityDescription: description)?
            .withSymbolConfiguration(config)
        image?.isTemplate = true
        button.image = image
        button.title = ""
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
        
        let statusText: String
        if !isSleepPrevented {
            statusText = "Mac'en må sove"
        } else if isForced {
            statusText = "Holder vågen (tvunget)"
        } else if !source.isEmpty {
            statusText = "Holder vågen: \(source)"
        } else {
            statusText = "Holder vågen"
        }
        
        let symbol = StatusSymbol.name(isSleepPrevented: isSleepPrevented, isMediaDetected: isMediaDetected, isForced: monitor.isForceKeepAwake)
        setStatusIcon(symbol, description: statusText)
        statusItem.button?.toolTip = "SmartSleep: \(statusText)"
        statusMenuItem.title = statusText
        
        // Lange videotitler ville goere hele menuen bred.
        nowPlayingMenuItem.title = title.count > 42 ? String(title.prefix(41)) + "…" : title
        nowPlayingMenuItem.isHidden = title.isEmpty || !isSleepPrevented
        
        autoMenuItem.state = monitor.isAutoEnabled ? .on : .off
        forceMenuItem.state = monitor.isForceKeepAwake ? .on : .off
    }
    
    // MARK: - Handlinger
    
    @objc private func openSettings() {
        SettingsWindowController.shared.showWindow()
    }
    
    @objc private func toggleAutoMode() {
        monitor.isAutoEnabled.toggle()
    }
    
    @objc private func toggleForceMode() {
        monitor.isForceKeepAwake.toggle()
    }
    
    @objc private func quitApp() {
        NSApplication.shared.terminate(nil)
    }
}
