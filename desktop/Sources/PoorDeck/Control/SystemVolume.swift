import CoreAudio
import Foundation

/// Reads and writes the system's master output volume (the default output
/// device). Values are 0…1 scalars, matching the client slider. Falls back from
/// the device's "main" volume element to per-channel scalars, since not every
/// device exposes a single master control.
///
/// Also exposes a change listener so the server can push slider updates back
/// to clients when the volume changes from another source (macOS menu bar,
/// keyboard, etc.).
final class SystemVolume {

    /// Closure invoked on the main queue whenever the master volume changes
    /// from any source. The argument is the new 0…1 scalar, or nil if the
    /// system reported a change but the value can't be read right now.
    var onChange: ((Float?) -> Void)?

    /// Starts listening for default-device and volume changes. Safe to call
    /// multiple times; subsequent calls are no-ops.
    func startListening() {
        guard listenerProc == nil else { return }

        // We need a stable C function pointer that we can register with
        // CoreAudio. It can't capture `self` directly, so we hop through a
        // user-info pointer (an `UnsafeMutableRawPointer` to `self`).
        let proc: AudioObjectPropertyListenerProc = { _, _, _, userInfo in
            guard let userInfo else { return noErr }
            let volume = Unmanaged<SystemVolume>.fromOpaque(userInfo).takeUnretainedValue()
            let value = SystemVolume.get()
            DispatchQueue.main.async {
                volume.onChange?(value)
            }
            return noErr
        }
        listenerProc = proc

        let userInfo = Unmanaged.passUnretained(self).toOpaque()
        var defaultAddr = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        AudioObjectAddPropertyListener(
            AudioObjectID(kAudioObjectSystemObject), &defaultAddr, proc, userInfo)

        // Subscribe to each settable volume element on the current default
        // device. We re-evaluate on every fire so the listener survives
        // device changes — extra subscriptions on a stale device are harmless.
        guard let device = SystemVolume.defaultOutputDevice() else { return }
        for element in SystemVolume.elements {
            var addr = SystemVolume.volumeAddress(element: element)
            guard AudioObjectHasProperty(device, &addr) else { continue }
            AudioObjectAddPropertyListener(device, &addr, proc, userInfo)
        }
    }

    deinit {
        // Listeners are best-effort cleaned up here; in practice the singleton
        // lives for the app's lifetime, so this rarely runs.
        if let proc = listenerProc {
            let userInfo = Unmanaged.passUnretained(self).toOpaque()
            var defaultAddr = AudioObjectPropertyAddress(
                mSelector: kAudioHardwarePropertyDefaultOutputDevice,
                mScope: kAudioObjectPropertyScopeGlobal,
                mElement: kAudioObjectPropertyElementMain)
            AudioObjectRemovePropertyListener(
                AudioObjectID(kAudioObjectSystemObject), &defaultAddr, proc, userInfo)

            if let device = SystemVolume.defaultOutputDevice() {
                for element in SystemVolume.elements {
                    var addr = SystemVolume.volumeAddress(element: element)
                    guard AudioObjectHasProperty(device, &addr) else { continue }
                    AudioObjectRemovePropertyListener(device, &addr, proc, userInfo)
                }
            }
        }
    }

    private var listenerProc: AudioObjectPropertyListenerProc?
}

extension SystemVolume {
    private static func defaultOutputDevice() -> AudioObjectID? {
        var deviceID = AudioObjectID(kAudioObjectUnknown)
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain)
        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &deviceID)
        return status == noErr ? deviceID : nil
    }

    fileprivate static func volumeAddress(element: UInt32) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyVolumeScalar,
            mScope: kAudioDevicePropertyScopeOutput,
            mElement: element)
    }

    /// Elements to try, in order: main (0), then left/right channels (1, 2).
    fileprivate static let elements: [UInt32] = [kAudioObjectPropertyElementMain, 1, 2]

    /// Current master volume as a 0…1 scalar. Prefers the device's main
    /// element when it's readable, since that's what `set()` writes to. Falls
    /// back to averaging per-channel scalars (left/right) only when the main
    /// element is missing — otherwise we'd report stale channel values that
    /// `set()` deliberately doesn't touch.
    static func get() -> Float? {
        guard let device = defaultOutputDevice() else { return nil }
        var mainAddr = volumeAddress(element: kAudioObjectPropertyElementMain)
        if AudioObjectHasProperty(device, &mainAddr) {
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &mainAddr, 0, nil, &size, &value) == noErr {
                return value
            }
        }
        var readings: [Float] = []
        for element in elements where element != kAudioObjectPropertyElementMain {
            var address = volumeAddress(element: element)
            guard AudioObjectHasProperty(device, &address) else { continue }
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectGetPropertyData(device, &address, 0, nil, &size, &value) == noErr {
                readings.append(value)
            }
        }
        guard !readings.isEmpty else { return nil }
        return readings.reduce(0, +) / Float(readings.count)
    }

    /// Set the master volume (0…1). Writes the main element if it's settable,
    /// otherwise every settable channel. Returns whether anything was written.
    @discardableResult
    static func set(_ scalar: Float) -> Bool {
        guard let device = defaultOutputDevice() else { return false }
        let clamped = max(0, min(1, scalar))
        var wrote = false
        for element in elements {
            var address = volumeAddress(element: element)
            var settable: DarwinBoolean = false
            guard AudioObjectHasProperty(device, &address),
                  AudioObjectIsPropertySettable(device, &address, &settable) == noErr,
                  settable.boolValue else { continue }
            var value = Float32(clamped)
            let size = UInt32(MemoryLayout<Float32>.size)
            if AudioObjectSetPropertyData(device, &address, 0, nil, size, &value) == noErr {
                wrote = true
                // If the main element took it, no need to also poke channels.
                if element == kAudioObjectPropertyElementMain { break }
            }
        }
        return wrote
    }
}
