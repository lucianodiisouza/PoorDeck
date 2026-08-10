import AudioToolbox
import Combine
import CoreAudio
import Foundation

/// Enumerates every process Core Audio knows about and publishes the ones
/// currently playing audio. Polls continuously so apps that start/stop
/// playing while the client is connected are reflected in the UI without
/// having to poke anything.
@MainActor
final class AudioProcessController: ObservableObject {

    static let shared = AudioProcessController()

    /// All audio-capable processes, most-recently-active first-ish.
    @Published private(set) var processes: [AudioProcess] = []

    /// Just the ones making sound right now — what the UI shows.
    var playing: [AudioProcess] {
        processes.filter(\.isPlaying).sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    /// Polls while running so a connected client sees new/ended audio sources.
    private var pollTimer: Timer?
    private let pollInterval: TimeInterval = 1.0

    /// Serial queue for every blocking Core Audio HAL call (enumeration, tap
    /// activation/teardown, leak reaping). Keeps `coreaudiod` round-trips off
    /// the main thread so a slow or wedged HAL never freezes the UI.
    private let halQueue = DispatchQueue(label: "com.webdeck.hal", qos: .userInitiated)
    /// Coalesce reloads: skip a scan if the previous one is still on the HAL queue.
    private var reloadInFlight = false

    // MARK: Per-app volume state

    /// Active taps, one per app the user has adjusted. Created lazily.
    private var taps: [AudioObjectID: ProcessTap] = [:]
    /// Slider position per app (1.0 = unmodified). Persisted only in memory.
    @Published private(set) var volumes: [AudioObjectID: Float] = [:]
    @Published private(set) var muted: Set<AudioObjectID> = []
    /// Last error encountered creating a tap (e.g. permission denied), per app.
    @Published private(set) var tapErrors: [AudioObjectID: String] = [:]

    /// Fired on the main actor whenever the published state changes (process
    /// list, volumes, mutes). The server hooks this to fan out to clients.
    var onChange: (() -> Void)?

    /// Snapshot of the current state in the wire format the server forwards to
    /// clients. Icon data URLs are resolved lazily (AppKit, main thread).
    func snapshot() -> [AudioApp] {
        let knownVolumeIDs = Set(volumes.keys).union(muted)
        // Show: every playing process, plus any process with a non-default
        // stored volume/mute (so apps the user previously adjusted keep
        // surfacing their slider even when paused).
        var ids = Set<AudioObjectID>()
        for p in processes where p.isPlaying { ids.insert(p.id) }
        ids.formUnion(knownVolumeIDs)
        return processes
            .filter { ids.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            .map { p in
                AudioApp(
                    id: String(p.id),
                    name: p.name,
                    icon: p.bundleID.flatMap { AppLauncher.iconDataURL(bundleId: $0) },
                    playing: p.isPlaying,
                    volume: volumes[p.id] ?? 1.0,
                    muted: muted.contains(p.id)
                )
            }
    }

    /// Look up a process by its stringified id (the format the client sees).
    /// Returns nil if the process is no longer known to Core Audio.
    func process(idString: String) -> AudioProcess? {
        guard let target = UInt32(idString) else { return nil }
        return processes.first(where: { $0.id == target })
    }

    /// Whether we've ever successfully tapped audio. macOS persists the actual
    /// TCC grant, and we mirror it here so the UI stops nagging about permission
    /// once it's been given — remembered across launches via `UserDefaults`.
    @Published private(set) var audioPermissionGranted: Bool =
        UserDefaults.standard.bool(forKey: "hasGrantedAudioTap")
    private static let permissionKey = "hasGrantedAudioTap"

    /// Range the UI exposes: full mute up to 2x boost.
    static let maxGain: Float = 2.0

    func volume(for process: AudioProcess) -> Float { volumes[process.id] ?? 1.0 }
    func isMuted(_ process: AudioProcess) -> Bool { muted.contains(process.id) }

    func setVolume(_ value: Float, for process: AudioProcess) {
        volumes[process.id] = value
        if value > 0 { muted.remove(process.id) }
        applyGain(for: process)
        onChange?()
    }

    func toggleMute(_ process: AudioProcess) {
        if muted.contains(process.id) {
            muted.remove(process.id)
        } else {
            muted.insert(process.id)
        }
        applyGain(for: process)
        onChange?()
    }

    /// Effective gain = 0 when muted, else the slider value.
    private func applyGain(for process: AudioProcess) {
        let effective: Float = muted.contains(process.id) ? 0 : (volumes[process.id] ?? 1.0)
        guard let tap = ensureTap(for: process) else { return }
        tap.gain = effective
    }

    /// Lazily create a tap the first time an app is adjusted, then activate it
    /// off the main thread. The tap is registered immediately so the caller's
    /// `tap.gain = …` write lands on the right object; the pointer-backed gain
    /// is read once the IOProc actually starts, so setting it before activation
    /// finishes is fine. Activation makes blocking HAL calls, so it must not
    /// run on the main thread.
    private func ensureTap(for process: AudioProcess) -> ProcessTap? {
        if let existing = taps[process.id] { return existing }
        let tap = ProcessTap(process: process)
        taps[process.id] = tap
        tapErrors[process.id] = nil

        let id = process.id
        let name = process.name
        halQueue.async { [weak self] in
            do {
                try tap.activate()
                Task { @MainActor in self?.rememberPermissionGranted() }
            } catch {
                let message = String(describing: error)
                log.error("Tap activation failed for \(name, privacy: .public): \(message, privacy: .public)")
                Task { @MainActor in
                    guard let self else { return }
                    if self.taps[id] === tap {
                        self.taps.removeValue(forKey: id)
                        self.tapErrors[id] = message
                    }
                }
            }
        }
        return tap
    }

    private func rememberPermissionGranted() {
        guard !audioPermissionGranted else { return }
        audioPermissionGranted = true
        UserDefaults.standard.set(true, forKey: Self.permissionKey)
    }

    /// Tear down taps whose process has exited so we don't leak aggregate devices.
    private func pruneVanishedTaps(livingIDs: Set<AudioObjectID>) {
        for (id, tap) in taps where !livingIDs.contains(id) {
            halQueue.async { tap.invalidate() }
            taps.removeValue(forKey: id)
            volumes.removeValue(forKey: id)
            muted.remove(id)
            tapErrors.removeValue(forKey: id)
        }
    }

    private var started = false

    func start() {
        guard !started else { return }
        started = true
        log.info("WebDeck audio controller starting; enumerating audio processes")
        // Sweep away any aggregate devices / taps leaked by a previous crash
        // before we start creating new ones — they otherwise pile up in
        // coreaudiod and can wedge the whole audio HAL.
        halQueue.async { ProcessTap.reapLeakedDevices() }
        reload()
        beginLiveUpdates()
    }

    func stop() {
        pollTimer?.invalidate()
        pollTimer = nil
        for tap in taps.values { halQueue.async { tap.invalidate() } }
        taps.removeAll()
    }

    // MARK: Live updates

    /// Refresh immediately, then poll on a light timer. Polling — rather than
    /// Core Audio property listeners — keeps this simple and reliably catches
    /// apps that start/stop playing while the client is connected.
    func beginLiveUpdates() {
        reload()
        pollTimer?.invalidate()
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.reload() }
        }
    }

    // MARK: Enumeration

    /// Kick off a scan on the HAL queue and publish the result back on the
    /// main thread. Coalesced: a scan that fires while another is still
    /// running is dropped (the poll will pick it up next tick).
    func reload() {
        guard !reloadInFlight else { return }
        reloadInFlight = true
        halQueue.async { [weak self] in
            let result = Self.enumerateProcesses()
            Task { @MainActor in
                guard let self else { return }
                self.reloadInFlight = false
                self.processes = result
                let living = Set(result.map(\.id))
                self.pruneVanishedTaps(livingIDs: living)
                self.onChange?()
            }
        }
    }

    /// Blocking HAL enumeration of every audio-capable process. Runs on the
    /// HAL queue; touches no actor-isolated state.
    nonisolated private static func enumerateProcesses() -> [AudioProcess] {
        do {
            let objectIDs: [AudioObjectID] = try AudioObjectID.system.readArray(
                kAudioHardwarePropertyProcessObjectList)

            var result: [AudioProcess] = []
            result.reserveCapacity(objectIDs.count)
            for objectID in objectIDs where objectID.isValid {
                guard let process = makeProcess(objectID) else { continue }
                result.append(process)
            }
            return result
        } catch {
            log.error("Failed to read process list: \(String(describing: error))")
            return []
        }
    }

    /// Our own pid — never list or tap ourselves. Because we re-play the audio
    /// we tap, Core Audio attributes that output to us, so we'd otherwise
    /// appear as a "playing" app; tapping ourselves would mute-and-reroute our
    /// own output into our own input, a feedback loop that kills all audio.
    nonisolated private static let ownPID: pid_t = ProcessInfo.processInfo.processIdentifier

    nonisolated private static func makeProcess(_ objectID: AudioObjectID) -> AudioProcess? {
        let pid: pid_t = (try? objectID.read(kAudioProcessPropertyPID, default: pid_t(-1))) ?? -1
        guard pid > 0, pid != ownPID else { return nil }

        let bundleID: String? = try? objectID.readCF(kAudioProcessPropertyBundleID, as: String.self) ?? nil
        let isRunningOutput: UInt32 = (try? objectID.read(
            kAudioProcessPropertyIsRunningOutput, default: UInt32(0))) ?? 0

        return AudioProcess(objectID: objectID,
                            pid: pid,
                            bundleID: bundleID,
                            isPlaying: isRunningOutput != 0)
    }
}
