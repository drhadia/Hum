import CoreAudio
import Foundation

struct AudioOutput: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
    let isAirPlay: Bool
}

/// Thin wrapper over the CoreAudio HAL calls the app needs.
enum CoreAudioKit {
    private static func fourCC(_ s: String) -> UInt32 {
        s.utf8.reduce(0) { ($0 << 8) | UInt32($1) }
    }

    private static let virtualMainVolume = fourCC("vmvc")
    private static let transportAirPlay = fourCC("airp")

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func get<T: BitwiseCopyable>(_ id: AudioObjectID, _ addr: AudioObjectPropertyAddress, default def: T) -> T? {
        var a = addr
        guard AudioObjectHasProperty(id, &a) else { return nil }
        var value = def
        var size = UInt32(MemoryLayout<T>.size)
        let status = AudioObjectGetPropertyData(id, &a, 0, nil, &size, &value)
        return status == noErr ? value : nil
    }

    private static func set<T: BitwiseCopyable>(_ id: AudioObjectID, _ addr: AudioObjectPropertyAddress, _ value: T) {
        var a = addr
        var v = value
        guard AudioObjectHasProperty(id, &a) else { return }
        AudioObjectSetPropertyData(id, &a, 0, nil, UInt32(MemoryLayout<T>.size), &v)
    }

    // MARK: Devices

    static func outputs() -> [AudioOutput] {
        var a = address(kAudioHardwarePropertyDevices)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size) == noErr else { return [] }
        var ids = [AudioDeviceID](repeating: 0, count: Int(size) / MemoryLayout<AudioDeviceID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &a, 0, nil, &size, &ids) == noErr else { return [] }
        return ids.compactMap { id in
            guard hasOutputStreams(id) else { return nil }
            let transport: UInt32 = get(id, address(kAudioDevicePropertyTransportType), default: 0) ?? 0
            return AudioOutput(id: id, name: name(of: id), isAirPlay: transport == transportAirPlay)
        }
    }

    private static func hasOutputStreams(_ id: AudioDeviceID) -> Bool {
        var a = address(kAudioDevicePropertyStreams, scope: kAudioObjectPropertyScopeOutput)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(id, &a, 0, nil, &size) == noErr && size > 0
    }

    private static func name(of id: AudioDeviceID) -> String {
        var a = address(kAudioObjectPropertyName)
        var cf: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(id, &a, 0, nil, &size, &cf) == noErr, let cf else { return "Unknown" }
        return cf.takeRetainedValue() as String
    }

    static func defaultOutput() -> AudioDeviceID {
        get(AudioObjectID(kAudioObjectSystemObject), address(kAudioHardwarePropertyDefaultOutputDevice), default: AudioDeviceID(0)) ?? 0
    }

    static func setDefaultOutput(_ id: AudioDeviceID) {
        set(AudioObjectID(kAudioObjectSystemObject), address(kAudioHardwarePropertyDefaultOutputDevice), id)
        set(AudioObjectID(kAudioObjectSystemObject), address(kAudioHardwarePropertyDefaultSystemOutputDevice), id)
    }

    // MARK: Volume / mute / activity

    static func volume(of id: AudioDeviceID) -> Float? {
        get(id, address(virtualMainVolume, scope: kAudioObjectPropertyScopeOutput), default: Float32(0))
    }

    static func setVolume(_ v: Float, of id: AudioDeviceID) {
        set(id, address(virtualMainVolume, scope: kAudioObjectPropertyScopeOutput), Float32(min(max(v, 0), 1)))
    }

    static func supportsMute(_ id: AudioDeviceID) -> Bool {
        var a = address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput)
        return AudioObjectHasProperty(id, &a)
    }

    static func isMuted(_ id: AudioDeviceID) -> Bool {
        (get(id, address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput), default: UInt32(0)) ?? 0) != 0
    }

    static func setMuted(_ muted: Bool, of id: AudioDeviceID) {
        set(id, address(kAudioDevicePropertyMute, scope: kAudioObjectPropertyScopeOutput), UInt32(muted ? 1 : 0))
    }

    /// True while some process is sending audio to the device.
    static func isActive(_ id: AudioDeviceID) -> Bool {
        (get(id, address(kAudioDevicePropertyDeviceIsRunningSomewhere), default: UInt32(0)) ?? 0) != 0
    }
}
