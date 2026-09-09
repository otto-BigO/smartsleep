import Foundation
import IOKit

func isLidClosed() -> Bool {
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

print("Is MacBook Lid Closed right now? \(isLidClosed())")
