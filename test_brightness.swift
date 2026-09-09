import Foundation
import CoreGraphics

typealias DisplayServicesGetBrightnessFunc = @convention(c) (CGDirectDisplayID, UnsafeMutablePointer<Float>) -> Int32
typealias DisplayServicesSetBrightnessFunc = @convention(c) (CGDirectDisplayID, Float) -> Int32

func testBrightness() {
    guard let handle = dlopen("/System/Library/PrivateFrameworks/DisplayServices.framework/DisplayServices", RTLD_LAZY) else {
        print("Could not open DisplayServices framework")
        return
    }
    defer { dlclose(handle) }
    
    guard let getSym = dlsym(handle, "DisplayServicesGetBrightness"),
          let setSym = dlsym(handle, "DisplayServicesSetBrightness") else {
        print("Could not find symbols")
        return
    }
    
    let getBrightness = unsafeBitCast(getSym, to: DisplayServicesGetBrightnessFunc.self)
    let setBrightness = unsafeBitCast(setSym, to: DisplayServicesSetBrightnessFunc.self)
    
    let mainDisplay = CGMainDisplayID()
    var current: Float = 0.0
    let res = getBrightness(mainDisplay, &current)
    print("GetBrightness result: \(res), Current brightness: \(current)")
}

testBrightness()
