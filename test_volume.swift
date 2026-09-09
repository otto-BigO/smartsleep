import Foundation
import CoreAudio
import AudioToolbox

func getOutputVolumeAndMute() -> (volume: Float, isMuted: Bool) {
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

let result = getOutputVolumeAndMute()
print("System Volume: \(result.volume), Muted: \(result.isMuted)")
