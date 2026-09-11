import Foundation
import CoreAudio
import AudioToolbox
import AppKit

/// En app der lige nu sender lyd ud.
struct AudioSource: Equatable {
    let pid: pid_t
    let bundleID: String
    let name: String
    
    var isSpotify: Bool { bundleID.hasPrefix("com.spotify.client") }
    var isBrave: Bool { bundleID.hasPrefix("com.brave.Browser") }
    var priority: Int { isSpotify ? 0 : (isBrave ? 1 : 2) }
}

enum AudioActivity {
    private static let knownApps: [(prefix: String, name: String)] = [
        ("com.spotify.client", "Spotify"),
        ("com.brave.Browser", "Brave"),
        ("com.google.Chrome", "Chrome"),
        ("com.apple.Safari", "Safari"),
        ("com.apple.WebKit", "Safari"),
        ("com.apple.Music", "Musik"),
        ("com.apple.TV", "TV"),
        ("com.apple.podcasts", "Podcasts"),
        ("org.mozilla.firefox", "Firefox"),
        ("company.thebrowser.Browser", "Arc"),
        ("com.microsoft.edgemac", "Edge"),
        ("org.videolan.vlc", "VLC"),
    ]
    
    /// Systemlyd som ingen lytter til. Diktering (CoreSpeech) afspiller en kort lyd naar den
    /// starter og holder udgangen aaben et stykke tid efter, og skal ikke holde Mac'en vaagen.
    private static let ignoredBundlePrefixes = ["com.apple.CoreSpeech"]
    
    static func isIgnored(bundleID: String) -> Bool {
        ignoredBundlePrefixes.contains { bundleID.hasPrefix($0) }
    }
    
    static func defaultOutputDevice() -> AudioObjectID? {
        guard let id = readUInt32(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice),
              id != kAudioObjectUnknown else { return nil }
        return id
    }
    
    static func isDeviceRunning(_ device: AudioObjectID) -> Bool {
        (readUInt32(device, kAudioDevicePropertyDeviceIsRunningSomewhere) ?? 0) != 0
    }
    
    static func outputVolumeAndMute(_ device: AudioObjectID) -> (volume: Float, isMuted: Bool) {
        var address = makeAddress(kAudioHardwareServiceDeviceProperty_VirtualMainVolume, scope: kAudioDevicePropertyScopeOutput)
        var volume: Float = 1.0
        var size = UInt32(MemoryLayout<Float>.size)
        if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &volume) != noErr {
            // Fx HDMI har ingen softwarelydstyrke. Gaa ud fra at der er lyd.
            volume = 1.0
        }
        let muted = (readUInt32(device, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput) ?? 0) != 0
        return (volume, muted)
    }
    
    /// Apps der lige nu sender lyd ud, Spotify og Brave foerst.
    /// nil paa macOS under 14.2, hvor CoreAudios proces-API ikke findes.
    static func activeOutputSources() -> [AudioSource]? {
        guard #available(macOS 14.2, *) else { return nil }
        
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = makeAddress(kAudioHardwarePropertyProcessObjectList)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr else { return nil }
        guard size > 0 else { return [] }
        
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return nil }
        
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var sources: [AudioSource] = []
        for object in objects {
            guard readUInt32(object, kAudioProcessPropertyIsRunningOutput) == 1 else { continue }
            let pid = pid_t(bitPattern: readUInt32(object, kAudioProcessPropertyPID) ?? 0)
            guard pid != ownPID else { continue }
            let bundleID = readString(object, kAudioProcessPropertyBundleID) ?? ""
            guard !isIgnored(bundleID: bundleID) else { continue }
            sources.append(AudioSource(pid: pid, bundleID: bundleID, name: displayName(bundleID: bundleID, pid: pid)))
        }
        return sources.sorted { $0.priority < $1.priority }
    }
    
    private static func displayName(bundleID: String, pid: pid_t) -> String {
        if let known = knownApps.first(where: { bundleID.hasPrefix($0.prefix) }) {
            return known.name
        }
        if let name = NSRunningApplication(processIdentifier: pid)?.localizedName, !name.isEmpty {
            // Hjaelpeprocesser hedder fx "Foo Helper (Renderer)". Vis app-navnet.
            return name.components(separatedBy: " Helper").first ?? name
        }
        return bundleID.isEmpty ? "pid \(pid)" : bundleID
    }
    
    // MARK: - CoreAudio-hjaelpere
    
    private static func makeAddress(_ selector: AudioObjectPropertySelector,
                                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }
    
    private static func readUInt32(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector,
                                   scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> UInt32? {
        var address = makeAddress(selector, scope: scope)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
    
    private static func readString(_ object: AudioObjectID, _ selector: AudioObjectPropertySelector) -> String? {
        var address = makeAddress(selector)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr,
              let string = value else { return nil }
        return string.takeRetainedValue() as String
    }
}
