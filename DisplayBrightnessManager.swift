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
    
    private var savedBrightness: Float?
    public private(set) var isDimmed: Bool = false
    
    private init() {
        setupFramework()
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
    
    public func getCurrentBrightness() -> Float {
        let mainDisplay = CGMainDisplayID()
        var current: Float = 0.5
        if let getFunc = getBrightnessFunc {
            _ = getFunc(mainDisplay, &current)
        }
        return current
    }
    
    public func dimDisplay(to targetBrightness: Float = 0.0) {
        guard !isDimmed else { return }
        let current = getCurrentBrightness()
        if current > targetBrightness {
            savedBrightness = current
        }
        setBrightness(targetBrightness)
        isDimmed = true
        print("[SmartSleep] 💡 Skærmlys dæmpet til \(targetBrightness) (Gemte tidligere: \(savedBrightness ?? current))")
    }
    
    public func restoreDisplay() {
        guard isDimmed else { return }
        let restoreVal = savedBrightness ?? 0.8
        setBrightness(restoreVal)
        savedBrightness = nil
        isDimmed = false
        print("[SmartSleep] 💡 Skærmlys genoprettet til \(restoreVal)")
    }
    
    private func setBrightness(_ brightness: Float) {
        let mainDisplay = CGMainDisplayID()
        if let setFunc = setBrightnessFunc {
            _ = setFunc(mainDisplay, brightness)
        }
    }
    
    deinit {
        restoreDisplay()
        if let handle = frameworkHandle {
            dlclose(handle)
        }
    }
}
