import Foundation
import CoreAudio
import AppKit
import IOKit.pwr_mgt

public class AudioSleepMonitor {
    public static let shared = AudioSleepMonitor()
    
    private enum DefaultsKey {
        static let auto = "SmartSleep.isAutoEnabled"
        static let force = "SmartSleep.isForceKeepAwake"
        static let dim = "SmartSleep.isDimBrightnessEnabled"
    }
    
    private static func storedBool(_ key: String, fallback: Bool) -> Bool {
        guard UserDefaults.standard.object(forKey: key) != nil else { return fallback }
        return UserDefaults.standard.bool(forKey: key)
    }
    
    public var isAutoEnabled: Bool = AudioSleepMonitor.storedBool(DefaultsKey.auto, fallback: true) {
        didSet {
            UserDefaults.standard.set(isAutoEnabled, forKey: DefaultsKey.auto)
            evaluateState()
        }
    }
    
    public var isForceKeepAwake: Bool = AudioSleepMonitor.storedBool(DefaultsKey.force, fallback: false) {
        didSet {
            UserDefaults.standard.set(isForceKeepAwake, forKey: DefaultsKey.force)
            evaluateState()
        }
    }
    
    public var isDimBrightnessEnabled: Bool = AudioSleepMonitor.storedBool(DefaultsKey.dim, fallback: true) {
        didSet {
            UserDefaults.standard.set(isDimBrightnessEnabled, forKey: DefaultsKey.dim)
            applyDisplayPolicy()
        }
    }
    
    public private(set) var isMediaDetected: Bool = false
    public private(set) var isSleepPrevented: Bool = false
    public private(set) var isLidClosed: Bool = false
    public private(set) var currentDetectionSource: String = ""
    public private(set) var nowPlayingTitle: String = ""
    public private(set) var nowPlayingArtist: String = ""
    public private(set) var nowPlayingArtworkURL: URL?
    
    public typealias StateObserver = (_ isMediaDetected: Bool, _ isSleepPrevented: Bool, _ isLidClosed: Bool, _ source: String, _ title: String, _ artist: String) -> Void
    
    private var observers: [ObjectIdentifier: StateObserver] = [:]
    
    /// Menulinjen og indstillingsvinduet lytter samtidig, derfor et register i stedet for en enkelt closure.
    public func addObserver(_ owner: AnyObject, _ block: @escaping StateObserver) {
        observers[ObjectIdentifier(owner)] = block
        block(isMediaDetected, isSleepPrevented, isLidClosed, currentDetectionSource, nowPlayingTitle, nowPlayingArtist)
    }
    
    public func removeObserver(_ owner: AnyObject) {
        observers.removeValue(forKey: ObjectIdentifier(owner))
    }
    
    private func notifyObservers(source: String, title: String, artist: String) {
        for block in Array(observers.values) {
            block(isMediaDetected, isSleepPrevented, isLidClosed, source, title, artist)
        }
    }
    
    private var systemSleepAssertionID: IOPMAssertionID = 0
    private var idleSleepAssertionID: IOPMAssertionID = 0
    private var timer: Timer?
    private var lidTimer: Timer?
    private var graceTimer: Timer?
    
    private let pollInterval: TimeInterval = 2.0
    private let lidPollInterval: TimeInterval = 0.5
    private let gracePeriodDuration: TimeInterval = 3.0
    private let nowPlayingRefreshInterval: TimeInterval = 10.0
    
    private var listenedDeviceID = AudioObjectID(kAudioObjectUnknown)
    private var deviceRunningListener: AudioObjectPropertyListenerBlock?
    
    /// Den app der spiller lige nu, ogsaa hvis den er sorteret fra (fx Spotify paa lydstyrke 0).
    private var topSource: AudioSource?
    private var lastNowPlayingFetch = Date.distantPast
    private var spotifyVolume: Int?
    private var lastLoggedSources = ""
    private var lastLoggedTitle = ""
    
    private init() {
        // Sikkerhedsnet. Blev appen draebt med SIGKILL mens den holdt Mac'en vaagen,
        // staar disablesleep stadig paa 1 og Mac'en vil aldrig sove. Ryd op ved opstart.
        runPmsetDisableSleep(0)
        isLidClosed = DisplayBrightnessManager.shared.isLidClosed()
        startMonitoring()
        // Doede appen mens skaermen var daempet, gendannes lysstyrken her.
        applyDisplayPolicy()
    }
    
    public func startMonitoring() {
        timer?.invalidate()
        timer = makeTimer(pollInterval, repeats: true) { [weak self] in
            self?.checkMediaAndUpdate()
        }
        
        // Laaget tjekkes oftere end lyden. Det er en enkelt registry-opslag og koster intet,
        // og skaermen skal slukkes med det samme laaget lukkes.
        lidTimer?.invalidate()
        lidTimer = makeTimer(lidPollInterval, repeats: true) { [weak self] in
            self?.checkLid()
        }
        
        setupCoreAudioListeners()
        checkMediaAndUpdate()
    }
    
    /// .common saa timerne ogsaa koerer mens menuen i menulinjen er aaben.
    private func makeTimer(_ interval: TimeInterval, repeats: Bool, _ block: @escaping () -> Void) -> Timer {
        let timer = Timer(timeInterval: interval, repeats: repeats) { _ in block() }
        RunLoop.main.add(timer, forMode: .common)
        return timer
    }
    
    // MARK: - CoreAudio-lyttere
    
    private func setupCoreAudioListeners() {
        // Skifter standard-udgangen (fx naar AirPods forbinder), flyttes lytteren med.
        var defaultDeviceAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &defaultDeviceAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.attachDeviceListener()
            self?.checkMediaAndUpdate()
        }
        attachDeviceListener()
    }
    
    private func attachDeviceListener() {
        guard let device = AudioActivity.defaultOutputDevice(), device != listenedDeviceID else { return }
        
        var runningAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        if listenedDeviceID != kAudioObjectUnknown, let old = deviceRunningListener {
            AudioObjectRemovePropertyListenerBlock(listenedDeviceID, &runningAddress, DispatchQueue.main, old)
        }
        
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.checkMediaAndUpdate()
        }
        if AudioObjectAddPropertyListenerBlock(device, &runningAddress, DispatchQueue.main, block) == noErr {
            listenedDeviceID = device
            deviceRunningListener = block
            appLog.notice("Lytter paa lydenhed \(device)")
        }
    }
    
    // MARK: - Laag
    
    private func checkLid() {
        let closed = DisplayBrightnessManager.shared.isLidClosed()
        guard closed != isLidClosed else { return }
        isLidClosed = closed
        appLog.notice("Laag \(closed ? "lukket" : "aabnet", privacy: .public)")
        
        if !closed {
            DisplayBrightnessManager.shared.refreshBuiltInDisplayID()
        }
        applyDisplayPolicy()
        notifyObservers(source: currentDetectionSource, title: nowPlayingTitle, artist: nowPlayingArtist)
    }
    
    /// Skaermen slukkes kun naar alle tre er sande: Mac'en holdes vaagen, laaget er lukket,
    /// og indstillingen er slaaet til. Kaldes ved enhver aendring af de tre.
    private func applyDisplayPolicy() {
        let display = DisplayBrightnessManager.shared
        if isSleepPrevented && isLidClosed && isDimBrightnessEnabled {
            guard !display.isDimmed else { return }
            display.dimDisplay(to: 0.0)
            display.sleepDisplayNow()
        } else if !isLidClosed {
            // Gendan kun med aabent laag. Med lukket laag sover panelet og tager ikke altid
            // imod en ny lysstyrke. Naar laaget aabnes, koerer vi her igen.
            display.restoreDisplay()
        }
    }
    
    // MARK: - Lyd
    
    public func checkMediaAndUpdate() {
        var detected = false
        var description = ""
        var sources: [AudioSource] = []
        
        if let device = AudioActivity.defaultOutputDevice() {
            let (volume, muted) = AudioActivity.outputVolumeAndMute(device)
            if muted || volume <= 0.001 {
                description = "Volume is 0 or muted"
            } else if let active = AudioActivity.activeOutputSources() {
                sources = active
                if let first = active.first {
                    if first.isSpotify && active.count == 1 && spotifyVolume == 0 {
                        description = "Spotify volume is 0"
                    } else {
                        detected = true
                        description = first.name
                    }
                }
            } else if AudioActivity.isDeviceRunning(device) {
                // macOS under 14.2: vi ved kun at der spiller noget, ikke hvad.
                detected = true
                description = "Playing audio"
            }
        }
        
        updateNowPlaying(for: sources.first)
        
        let sourceList = sources.map { $0.name }.joined(separator: ", ")
        let logLine = "\(detected ? "ja" : "nej") [\(sourceList)] \(description)"
        if logLine != lastLoggedSources {
            appLog.notice("Lyd: \(logLine, privacy: .public)")
            lastLoggedSources = logLine
        }
        
        if detected {
            graceTimer?.invalidate()
            graceTimer = nil
            isMediaDetected = true
            currentDetectionSource = description
            evaluateState()
        } else if isMediaDetected {
            isMediaDetected = false
            currentDetectionSource = ""
            if isSleepPrevented && graceTimer == nil {
                graceTimer = makeTimer(gracePeriodDuration, repeats: false) { [weak self] in
                    self?.graceTimer = nil
                    self?.evaluateState()
                }
            } else {
                evaluateState()
            }
        } else {
            evaluateState()
        }
    }
    
    private func updateNowPlaying(for source: AudioSource?) {
        let changed = source?.bundleID != topSource?.bundleID
        topSource = source
        if changed {
            nowPlayingTitle = ""
            nowPlayingArtist = ""
            nowPlayingArtworkURL = nil
            spotifyVolume = nil
        }
        
        guard let source, source.isSpotify || source.isBrave else { return }
        guard changed || Date().timeIntervalSince(lastNowPlayingFetch) >= nowPlayingRefreshInterval else { return }
        lastNowPlayingFetch = Date()
        
        NowPlayingFetcher.shared.fetch(for: source) { [weak self] info in
            guard let self, self.topSource?.bundleID == source.bundleID else { return }
            self.nowPlayingTitle = info?.title ?? ""
            self.nowPlayingArtist = info?.artist ?? ""
            self.nowPlayingArtworkURL = info?.artworkURL
            if source.isSpotify {
                self.spotifyVolume = info?.spotifyVolume
            }
            let title = info?.title ?? "(ingen)"
            if title != self.lastLoggedTitle {
                appLog.notice("Titel fra \(source.name, privacy: .public): \(title, privacy: .public)")
                self.lastLoggedTitle = title
            }
            self.notifyObservers(source: self.currentDetectionSource, title: self.nowPlayingTitle, artist: self.nowPlayingArtist)
        }
    }
    
    // MARK: - Power Assertions
    
    /// Assertions ejes af processen. Kernen frigiver dem automatisk naar processen doer,
    /// derfor kan de ikke blive haengende som en caffeinate-underproces kunne.
    /// Der tages bevidst ingen assertion paa skaermen: den maa gerne slukke mens musikken spiller,
    /// og videoafspillere holder selv skaermen taendt.
    private func createAssertion(_ type: String, into id: inout IOPMAssertionID) {
        guard id == 0 else { return }
        var newID: IOPMAssertionID = 0
        let reason = "SmartSleep: Holding Mac awake" as CFString
        let result = IOPMAssertionCreateWithName(
            type as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &newID
        )
        if result == kIOReturnSuccess {
            id = newID
        } else {
            appLog.error("Kunne ikke oprette assertion \(type, privacy: .public): \(result)")
        }
    }
    
    private func releaseAssertion(_ id: inout IOPMAssertionID) {
        guard id != 0 else { return }
        IOPMAssertionRelease(id)
        id = 0
    }
    
    private func releaseAllAssertions() {
        releaseAssertion(&systemSleepAssertionID)
        releaseAssertion(&idleSleepAssertionID)
    }
    
    /// Kaldes ved afslutning og fra signalhaandteringen. Skal kunne kaldes flere gange uden skade.
    public func shutdownCleanup() {
        timer?.invalidate()
        timer = nil
        lidTimer?.invalidate()
        lidTimer = nil
        graceTimer?.invalidate()
        graceTimer = nil
        
        releaseAllAssertions()
        
        // Med lukket laag bliver den gemte lysstyrke liggende, og naeste opstart gendanner den.
        if !DisplayBrightnessManager.shared.isLidClosed() {
            DisplayBrightnessManager.shared.restoreDisplay()
        }
        
        // Vent paa pmset her. Processen er paa vej ud, og en detached underproces
        // naar ikke at koere faerdig.
        runPmsetDisableSleep(0, waitForExit: true)
        
        isSleepPrevented = false
        appLog.notice("Afsluttet, dvale er givet fri igen")
    }
    
    private func evaluateState() {
        let shouldPreventSleep = isForceKeepAwake || (isAutoEnabled && (isMediaDetected || graceTimer != nil))
        
        if shouldPreventSleep && !isSleepPrevented {
            enableSleepPrevention()
        } else if !shouldPreventSleep && isSleepPrevented {
            disableSleepPrevention()
        } else {
            notifyObservers(source: currentDetectionSource, title: nowPlayingTitle, artist: nowPlayingArtist)
        }
    }
    
    private func enableSleepPrevention() {
        guard !isSleepPrevented else { return }
        
        createAssertion(kIOPMAssertionTypePreventSystemSleep, into: &systemSleepAssertionID)
        createAssertion(kIOPMAssertPreventUserIdleSystemSleep, into: &idleSleepAssertionID)
        runPmsetDisableSleep(1)
        
        isSleepPrevented = true
        applyDisplayPolicy()
        appLog.notice("Soevn deaktiveret (\(self.currentDetectionSource, privacy: .public))")
        notifyObservers(source: currentDetectionSource, title: nowPlayingTitle, artist: nowPlayingArtist)
    }
    
    private func disableSleepPrevention() {
        guard isSleepPrevented else { return }
        
        releaseAllAssertions()
        runPmsetDisableSleep(0)
        
        isSleepPrevented = false
        applyDisplayPolicy()
        appLog.notice("Soevn tilladt")
        notifyObservers(source: "", title: "", artist: "")
    }
    
    /// -n gør at sudo fejler med det samme i stedet for at haenge og vente paa et kodeord,
    /// hvis sudoers-reglen i /etc/sudoers.d/smartsleep mangler.
    private func runPmsetDisableSleep(_ state: Int, waitForExit: Bool = false) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["-n", "/usr/bin/pmset", "-a", "disablesleep", "\(state)"]
        do {
            try process.run()
            if waitForExit { process.waitUntilExit() }
        } catch {
            appLog.error("Kunne ikke koere pmset: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    deinit {
        shutdownCleanup()
    }
}
