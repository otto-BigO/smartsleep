import Foundation
import CoreGraphics
import IOKit

public class DisplayBrightnessManager {
    public static let shared = DisplayBrightnessManager()
    
    private typealias DisplayServicesGetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
    private typealias DisplayServicesSetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32
    
    private var getBrightnessFunc: DisplayServicesGetBrightnessFunc?
    private var setBrightnessFunc: DisplayServicesSetBrightnessFunc?
    private var frameworkHandle: UnsafeMutableRawPointer?
    
    /// Gemmes ogsaa i UserDefaults. Doer appen mens skaermen er daempet, kan naeste opstart gendanne den.
    private static let savedBrightnessKey = "SmartSleep.savedBrightness"
    private var savedBrightness: Float?
    private var builtInDisplayID: CGDirectDisplayID = CGMainDisplayID()
    private var restoreGeneration = 0
    public private(set) var isDimmed: Bool = false
    
    private init() {
        setupFramework()
        refreshBuiltInDisplayID()
        
        if UserDefaults.standard.object(forKey: Self.savedBrightnessKey) != nil {
            let stored = UserDefaults.standard.float(forKey: Self.savedBrightnessKey)
            savedBrightness = stored
            isDimmed = true
            appLog.notice("Fandt gemt lysstyrke \(stored) fra en tidligere koersel")
        }
    }
    
    private func setupFramework() {
        frameworkHandle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY)
        guard let handle = frameworkHandle else { return }
        
        if let getSym = dlsym(handle, "DisplayServicesGetBrightness") {
            getBrightnessFunc = unsafeBitCast(getSym, to: DisplayServicesGetBrightnessFunc.self)
        }
        if let setSym = dlsym(handle, "DisplayServicesSetBrightness") {
            setBrightnessFunc = unsafeBitCast(setSym, to: DisplayServicesSetBrightnessFunc.self)
        }
    }
    
    public func isLidClosed() -> Bool {
        let service = IOServiceGetMatchingService(kIOMainPortDefault, IOServiceMatching("IOPMrootDomain"))
        guard service != 0 else { return false }
        defer { IOObjectRelease(service) }
        
        guard let property = IORegistryEntryCreateCFProperty(service, "AppleClamshellState" as CFString, kCFAllocatorDefault, 0) else {
            return false
        }
        
        let value = property.takeRetainedValue()
        if let isClosed = value as? Bool {
            return isClosed
        }
        return false
    }
    
    /// Brug den indbyggede skaerm, ikke CGMainDisplayID. Med en ekstern skaerm som hovedskaerm
    /// ville vi ellers daempe den forkerte. ID'et huskes, hvis skaermen forsvinder med lukket laag.
    public func refreshBuiltInDisplayID() {
        var ids = [CGDirectDisplayID](repeating: 0, count: 16)
        var count: UInt32 = 0
        guard CGGetOnlineDisplayList(16, &ids, &count) == .success else { return }
        if let id = ids.prefix(Int(count)).first(where: { CGDisplayIsBuiltin($0) != 0 }) {
            builtInDisplayID = id
        }
    }
    
    public func getCurrentBrightness() -> Float? {
        guard let getFunc = getBrightnessFunc else { return nil }
        var current: Float = 0
        return getFunc(builtInDisplayID, &current) == 0 ? current : nil
    }
    
    public func dimDisplay(to targetBrightness: Float = 0.0) {
        guard !isDimmed else { return }
        let current = getCurrentBrightness() ?? 0.75
        savedBrightness = current
        UserDefaults.standard.set(current, forKey: Self.savedBrightnessKey)
        restoreGeneration += 1
        let ok = setBrightness(targetBrightness)
        isDimmed = true
        appLog.notice("Skaermlys daempet til \(targetBrightness) fra \(current) (ok: \(ok))")
    }
    
    public func restoreDisplay() {
        guard isDimmed else { return }
        let value = savedBrightness ?? 0.75
        let ok = setBrightness(value)
        savedBrightness = nil
        UserDefaults.standard.removeObject(forKey: Self.savedBrightnessKey)
        isDimmed = false
        appLog.notice("Skaermlys gendannet til \(value) (ok: \(ok))")
        
        // Lige efter laaget aabnes er panelet ved at vaagne og kan overskrive vores vaerdi.
        // Tjek et par gange mere og saet den igen hvis den ikke holdt.
        restoreGeneration += 1
        let generation = restoreGeneration
        for delay in [1.5, 4.0] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
                guard let self, self.restoreGeneration == generation, !self.isDimmed else { return }
                if let current = self.getCurrentBrightness(), current < value - 0.02 {
                    self.setBrightness(value)
                    appLog.notice("Skaermlys sat igen til \(value), stod paa \(current)")
                }
            }
        }
    }
    
    /// Slukker skaermen helt uden at sende Mac'en i dvale.
    public func sleepDisplayNow() {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/pmset")
        process.arguments = ["displaysleepnow"]
        do {
            try process.run()
            appLog.notice("Skaerm slukket med displaysleepnow")
        } catch {
            appLog.error("displaysleepnow fejlede: \(error.localizedDescription, privacy: .public)")
        }
    }
    
    @discardableResult
    private func setBrightness(_ brightness: Float) -> Bool {
        guard let setFunc = setBrightnessFunc else { return false }
        return setFunc(builtInDisplayID, brightness) == 0
    }
    
    deinit {
        restoreDisplay()
        if let handle = frameworkHandle {
            dlclose(handle)
        }
    }
}
