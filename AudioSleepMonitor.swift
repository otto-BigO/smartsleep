import Foundation
import CoreAudio
import AudioToolbox
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
            if isSleepPrevented {
                if isDimBrightnessEnabled {
                    DisplayBrightnessManager.shared.dimDisplay(to: 0.0)
                } else {
                    DisplayBrightnessManager.shared.restoreDisplay()
                }
            }
        }
    }
    
    public private(set) var isMediaDetected: Bool = false
    public private(set) var isSleepPrevented: Bool = false
    public private(set) var isLidClosed: Bool = false
    public private(set) var currentDetectionSource: String = ""
    public private(set) var nowPlayingTitle: String = ""
    public private(set) var nowPlayingArtist: String = ""
    
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
    
    private var assertionID: IOPMAssertionID = 0
    private var caffeinateProcess: Process?
    private var timer: Timer?
    private var graceTimer: Timer?
    
    private let gracePeriodDuration: TimeInterval = 3.0
    private var currentOutputDeviceID: AudioObjectID = kAudioObjectUnknown
    
    private init() {
        startMonitoring()
    }
    
    public func startMonitoring() {
        timer?.invalidate()
        timer = Timer.scheduledTimer(withTimeInterval: 2.0, repeats: true) { [weak self] _ in
            self?.checkMediaAndUpdate()
        }
        
        setupCoreAudioListener()
        checkMediaAndUpdate()
    }
    
    private func setupCoreAudioListener() {
        var defaultOutputDeviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &defaultOutputDeviceID
        )
        
        guard status == noErr, defaultOutputDeviceID != kAudioObjectUnknown else { return }
        currentOutputDeviceID = defaultOutputDeviceID
        
        var runAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        AudioObjectAddPropertyListenerBlock(
            currentOutputDeviceID,
            &runAddress,
            DispatchQueue.main
        ) { [weak self] _, _ in
            self?.checkMediaAndUpdate()
        }
    }
    
    public func checkMediaAndUpdate() {
        let lidState = DisplayBrightnessManager.shared.isLidClosed()
        if lidState != isLidClosed {
            isLidClosed = lidState
            if !isLidClosed {
                DisplayBrightnessManager.shared.restoreDisplay()
            }
        }
        
        var detected = false
        var sourceDescription = ""
        var trackTitle = ""
        var trackArtist = ""
        
        let (sysVol, sysMuted) = getSystemOutputVolumeAndMute()
        let isSystemSilent = sysMuted || sysVol <= 0.001
        let isAudioRunning = checkCoreAudioPlayback()
        
        if isSystemSilent {
            detected = false
            sourceDescription = "Lydstyrke er 0 / Slået fra"
        } else if !isAudioRunning {
            // Enheden sender ingen lyd. Spring AppleScript til Spotify og Brave over, de er dyre at kalde.
            detected = false
            sourceDescription = ""
        } else if let (sTitle, sArtist) = getSpotifyTrackInfo() {
            let spotifyVol = getSpotifyVolume()
            if spotifyVol == 0 {
                detected = false
                sourceDescription = "Spotify lydstyrke er 0"
            } else {
                detected = true
                sourceDescription = "Spotify Musik"
                trackTitle = sTitle
                trackArtist = sArtist
            }
        } else if let bTitle = getBraveYouTubeTitle() {
            detected = true
            sourceDescription = "Brave YouTube Video"
            trackTitle = bTitle
            trackArtist = "Brave Browser"
        } else {
            detected = true
            sourceDescription = "Generel Lyd/Video"
            trackTitle = "System Lydafspilning"
            trackArtist = "macOS Audio Engine"
        }
        
        nowPlayingTitle = trackTitle
        nowPlayingArtist = trackArtist
        
        if detected {
            graceTimer?.invalidate()
            graceTimer = nil
            
            isMediaDetected = true
            currentDetectionSource = sourceDescription
            evaluateState()
        } else {
            if isMediaDetected {
                isMediaDetected = false
                currentDetectionSource = ""
                
                if graceTimer == nil && isSleepPrevented {
                    graceTimer = Timer.scheduledTimer(withTimeInterval: gracePeriodDuration, repeats: false) { [weak self] _ in
                        self?.graceTimer = nil
                        self?.evaluateState()
                    }
                } else if graceTimer == nil {
                    evaluateState()
                }
            } else {
                evaluateState()
            }
        }
    }
    
    // MARK: - System Volume & Mute Check
    private func getSystemOutputVolumeAndMute() -> (volume: Float, isMuted: Bool) {
        var defaultOutputDeviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &defaultOutputDeviceID
        )
        
        guard status == noErr, defaultOutputDeviceID != kAudioObjectUnknown else {
            return (0.0, true)
        }
        
        var volume: Float = 0.0
        size = UInt32(MemoryLayout<Float>.size)
        var volAddress = AudioObjectPropertyAddress(
            mSelector: kAudioHardwareServiceDeviceProperty_VirtualMainVolume,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let volStatus = AudioObjectGetPropertyData(
            defaultOutputDeviceID,
            &volAddress,
            0,
            nil,
            &size,
            &volume
        )
        
        var isMuted: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        var muteAddress = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyMute,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let muteStatus = AudioObjectGetPropertyData(
            defaultOutputDeviceID,
            &muteAddress,
            0,
            nil,
            &size,
            &isMuted
        )
        
        let muted = (muteStatus == noErr) ? (isMuted != 0) : false
        let vol = (volStatus == noErr) ? volume : 1.0
        return (vol, muted)
    }
    
    // MARK: - Spotify Track Info & Volume
    private func getSpotifyTrackInfo() -> (title: String, artist: String)? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client")
        guard let spotify = apps.first, !spotify.isTerminated else {
            return nil
        }
        
        let scriptSource = """
        tell application "Spotify"
            if player state is playing then
                return (name of current track) & "|||" & (artist of current track)
            else
                return ""
            end if
        end tell
        """
        let script = NSAppleScript(source: scriptSource)
        var error: NSDictionary?
        if let descriptor = script?.executeAndReturnError(&error), let str = descriptor.stringValue, !str.isEmpty {
            let parts = str.components(separatedBy: "|||")
            if parts.count >= 2 {
                return (parts[0], parts[1])
            } else if parts.count == 1 {
                return (parts[0], "Spotify")
            }
        }
        return nil
    }
    
    private func getSpotifyVolume() -> Int {
        let scriptSource = "tell application \"Spotify\" to get sound volume"
        let script = NSAppleScript(source: scriptSource)
        var error: NSDictionary?
        if let descriptor = script?.executeAndReturnError(&error) {
            return Int(descriptor.int32Value)
        }
        return 100
    }
    
    // MARK: - Brave YouTube Track Info
    private func getBraveYouTubeTitle() -> String? {
        let apps = NSRunningApplication.runningApplications(withBundleIdentifier: "com.brave.Browser")
        guard let brave = apps.first, !brave.isTerminated else {
            return nil
        }
        
        guard checkCoreAudioPlayback() else { return nil }
        
        let scriptSource = """
        tell application "Brave Browser"
            if not (exists window 1) then return ""
            repeat with w in windows
                repeat with t in tabs of w
                    set u to (URL of t as string)
                    if u contains "youtube.com" or u contains "youtu.be" then
                        return (title of t as string)
                    end if
                end repeat
            end repeat
            return ""
        end tell
        """
        let script = NSAppleScript(source: scriptSource)
        var error: NSDictionary?
        if let descriptor = script?.executeAndReturnError(&error), let str = descriptor.stringValue, !str.isEmpty {
            // Clean up "- YouTube" suffix if present
            var cleanTitle = str.replacingOccurrences(of: " - YouTube", with: "")
            if cleanTitle.hasPrefix("(") && cleanTitle.contains(") ") {
                if let range = cleanTitle.range(of: ") ") {
                    cleanTitle = String(cleanTitle[range.upperBound...])
                }
            }
            return cleanTitle
        }
        return nil
    }
    
    // MARK: - CoreAudio Fallback Detection
    private func checkCoreAudioPlayback() -> Bool {
        var defaultOutputDeviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0,
            nil,
            &size,
            &defaultOutputDeviceID
        )
        
        guard status == noErr, defaultOutputDeviceID != kAudioObjectUnknown else {
            return false
        }
        
        var isRunning: UInt32 = 0
        size = UInt32(MemoryLayout<UInt32>.size)
        address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceIsRunningSomewhere,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )
        
        let isRunningStatus = AudioObjectGetPropertyData(
            defaultOutputDeviceID,
            &address,
            0,
            nil,
            &size,
            &isRunning
        )
        
        return isRunningStatus == noErr && isRunning != 0
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
        
        let reason = "SmartSleep: Holding Mac awake" as CFString
        IOPMAssertionCreateWithName(
            kIOPMAssertionTypePreventSystemSleep as CFString,
            IOPMAssertionLevel(kIOPMAssertionLevelOn),
            reason,
            &assertionID
        )
        
        stopCaffeinateProcess()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/caffeinate")
        process.arguments = ["-i", "-s", "-u", "-d"]
        try? process.run()
        caffeinateProcess = process
        
        runPmsetDisableSleep(1)
        
        if isDimBrightnessEnabled && isLidClosed {
            DisplayBrightnessManager.shared.dimDisplay(to: 0.0)
        }
        
        isSleepPrevented = true
        print("[SmartSleep] 🟢 Søvn DEAKTIVERET (Title: \(nowPlayingTitle), Artist: \(nowPlayingArtist))")
        notifyObservers(source: currentDetectionSource, title: nowPlayingTitle, artist: nowPlayingArtist)
    }
    
    private func disableSleepPrevention() {
        guard isSleepPrevented else { return }
        
        if assertionID != 0 {
            IOPMAssertionRelease(assertionID)
            assertionID = 0
        }
        
        stopCaffeinateProcess()
        runPmsetDisableSleep(0)
        
        DisplayBrightnessManager.shared.restoreDisplay()
        
        isSleepPrevented = false
        print("[SmartSleep] 💤 Søvn TILLADT")
        notifyObservers(source: "", title: "", artist: "")
    }
    
    private func runPmsetDisableSleep(_ state: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/sudo")
        process.arguments = ["/usr/bin/pmset", "-a", "disablesleep", "\(state)"]
        try? process.run()
    }
    
    private func stopCaffeinateProcess() {
        if let proc = caffeinateProcess, proc.isRunning {
            proc.terminate()
        }
        caffeinateProcess = nil
    }
    
    deinit {
        timer?.invalidate()
        graceTimer?.invalidate()
        disableSleepPrevention()
    }
}
