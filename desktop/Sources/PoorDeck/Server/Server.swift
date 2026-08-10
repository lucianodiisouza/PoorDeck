import Combine
import Foundation
import Network

/// Embedded HTTP + WebSocket server.
///
/// - Serves the built Svelte client (static files) so a phone/tablet just opens
///   `http://<mac-ip>:<port>/`.
/// - Upgrades `/ws` to a WebSocket and speaks the JSON protocol in `Protocol.swift`.
/// - Advertises itself over Bonjour (`_poordeck._tcp`) for zero-config discovery.
///
/// All Network.framework callbacks run on `queue` (serial), so connection state
/// is single-threaded; UI-facing `@Published` values are mirrored onto main.
final class Server: ObservableObject, @unchecked Sendable {

    @Published private(set) var isRunning = false
    @Published private(set) var port: UInt16 = 0
    @Published private(set) var host: String = "—"
    @Published private(set) var clientCount = 0
    /// Last orientation the most recent client reported. Used by the
    /// editor's "Follow device" preview mode. `true` = portrait.
    @Published private(set) var lastDeviceOrientationIsPortrait = true

    /// Pairing URL shown in the UI and encoded into the QR code.
    var pairingURL: String { "http://\(host):\(port)" }

    private let queue = DispatchQueue(label: "dev.oprimo.poordeck.server")
    private var listener: NWListener?
    private var clients: [ObjectIdentifier: NWConnection] = [:]

    private let candidatePorts: [UInt16] = [8756, 8757, 8758, 8759, 8760]

    /// System volume bridge — observes the master output device and broadcasts
    /// changes to every connected client.
    private let systemVolume = SystemVolume()
    /// Per-app audio controller — enumerates processes, runs the tap pipeline,
    /// and publishes the list of apps currently producing audio.
    private let audio = AudioProcessController.shared

    // MARK: Lifecycle

    func start() {
        guard listener == nil else { return }
        host = NetworkInfo.primaryIPv4() ?? "localhost"
        tryListen(portIndex: 0)
        startVolumeBridge()
        startAudioBridge()
        startLayoutBridge()
    }

    /// Re-broadcast the layout to every connected client when the
    /// `ConfigurationStore` mutates. The store fires this from the editor's
    /// add / update / delete actions; we just fan it out.
    private func startLayoutBridge() {
        Task { @MainActor in
            DeckStore.shared.onLayoutChange { [weak self] in
                guard let self else { return }
                DeckStore.shared.refresh()
                let layout = DeckStore.shared.resolvedLayout()
                self.broadcast(.layout(layout))
            }
        }
    }

    private func startVolumeBridge() {
        systemVolume.onChange = { [weak self] value in
            guard let self, let value else { return }
            self.broadcast(.volume(target: .system, value: value))
        }
        systemVolume.startListening()
    }

    private func startAudioBridge() {
        // Fan out the full snapshot whenever the controller's published state
        // changes. Cheap because the controller already coalesces its poll.
        // The controller is @MainActor; we hop on to mutate it. The callback
        // dispatches back to the main actor before reading the snapshot, which
        // is what we want anyway (the controller only mutates on main).
        Task { @MainActor in
            self.audio.onChange = { [weak self] in
                Task { @MainActor in
                    guard let self else { return }
                    let list = self.audio.snapshot()
                    self.broadcast(.apps(list: list))
                }
            }
            self.audio.start()
        }
    }

    private func tryListen(portIndex: Int) {
        guard portIndex < candidatePorts.count else {
            NSLog("PoorDeck: no free port in \(candidatePorts)")
            return
        }
        let wanted = candidatePorts[portIndex]
        do {
            let params = NWParameters.tcp
            params.allowLocalEndpointReuse = true
            let listener = try NWListener(using: params, on: NWEndpoint.Port(rawValue: wanted)!)
            listener.service = NWListener.Service(name: "PoorDeck", type: "_poordeck._tcp")

            listener.stateUpdateHandler = { [weak self] state in
                guard let self else { return }
                switch state {
                case .ready:
                    Task { @MainActor in
                        self.port = wanted
                        self.isRunning = true
                        NSLog("PoorDeck: listening on \(self.pairingURL)")
                    }
                case .failed(let error):
                    NSLog("PoorDeck: listener failed on \(wanted): \(error)")
                    listener.cancel()
                    Task { @MainActor in
                        self.listener = nil
                        self.tryListen(portIndex: portIndex + 1)
                    }
                default:
                    break
                }
            }
            listener.newConnectionHandler = { [weak self] conn in
                self?.accept(conn)
            }
            listener.start(queue: queue)
            self.listener = listener
        } catch {
            NSLog("PoorDeck: could not create listener on \(wanted): \(error)")
            tryListen(portIndex: portIndex + 1)
        }
    }

    // MARK: Connection handling

    private func accept(_ conn: NWConnection) {
        conn.start(queue: queue)
        readHTTPHeader(conn, buffer: Data())
    }

    /// Accumulate bytes until the end of the HTTP request header, then route.
    private func readHTTPHeader(_ conn: NWConnection, buffer: Data) {
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }

            if let terminator = buffer.range(of: Data("\r\n\r\n".utf8)) {
                let headerData = buffer.subdata(in: buffer.startIndex..<terminator.lowerBound)
                let rest = buffer.subdata(in: terminator.upperBound..<buffer.endIndex)
                self.handleRequest(conn, header: headerData, leftover: rest)
                return
            }

            if error != nil || isComplete {
                conn.cancel()
                return
            }
            if buffer.count > 256 * 1024 { // runaway header guard
                conn.cancel()
                return
            }
            self.readHTTPHeader(conn, buffer: buffer)
        }
    }

    private func handleRequest(_ conn: NWConnection, header: Data, leftover: Data) {
        guard let request = HTTPRequest(header: header) else {
            send(conn, HTTPResponse.plain(400, "Bad Request"), close: true)
            return
        }

        if request.isWebSocketUpgrade, let key = request.header("sec-websocket-key") {
            upgradeToWebSocket(conn, key: key, leftover: leftover)
            return
        }

        serveStatic(conn, path: request.path)
    }

    // MARK: Static file serving

    private func serveStatic(_ conn: NWConnection, path: String) {
        let webRoot = Self.webRoot()
        var relative = path
        if let q = relative.firstIndex(of: "?") { relative = String(relative[..<q]) }
        if relative == "/" || relative.isEmpty { relative = "/index.html" }

        // Prevent path traversal.
        let clean = relative.split(separator: "/").filter { $0 != ".." }.joined(separator: "/")
        let fileURL = webRoot.appendingPathComponent(clean)

        if let data = try? Data(contentsOf: fileURL) {
            send(conn, HTTPResponse.file(data, contentType: Self.contentType(for: fileURL)), close: true)
            return
        }

        // SPA fallback: unknown non-asset path -> index.html.
        if !clean.contains(".") {
            let indexURL = webRoot.appendingPathComponent("index.html")
            if let data = try? Data(contentsOf: indexURL) {
                send(conn, HTTPResponse.file(data, contentType: "text/html; charset=utf-8"), close: true)
                return
            }
            send(conn, HTTPResponse.plain(200, Self.placeholderPage(pairingURL: "http://\(host):\(port)")),
                 close: true, contentType: "text/html; charset=utf-8")
            return
        }

        send(conn, HTTPResponse.plain(404, "Not Found"), close: true)
    }

    // MARK: WebSocket

    private func upgradeToWebSocket(_ conn: NWConnection, key: String, leftover: Data) {
        let accept = WebSocket.acceptKey(for: key)
        let handshake = [
            "HTTP/1.1 101 Switching Protocols",
            "Upgrade: websocket",
            "Connection: Upgrade",
            "Sec-WebSocket-Accept: \(accept)",
            "\r\n",
        ].joined(separator: "\r\n")

        conn.send(content: Data(handshake.utf8), completion: .contentProcessed { [weak self] error in
            guard let self else { return }
            if let error {
                NSLog("PoorDeck: ws handshake send failed: \(error)")
                conn.cancel()
                return
            }
            self.registerClient(conn)
            self.sendLayout(to: conn)
            self.readWebSocket(conn, buffer: leftover)
        })
    }

    private func registerClient(_ conn: NWConnection) {
        clients[ObjectIdentifier(conn)] = conn
        let count = clients.count
        Task { @MainActor in self.clientCount = count }
        // Push the current system volume so the slider reflects reality on
        // first paint instead of waiting for the next local change.
        if let value = SystemVolume.get() {
            sendServerMessage(.volume(target: .system, value: value), to: conn)
        }
        // Push the current per-app snapshot so the new client doesn't have
        // to wait for the next poll tick. Snapshot reads @MainActor state,
        // so we hop on briefly.
        Task { @MainActor in
            let snapshot = self.audio.snapshot()
            if !snapshot.isEmpty {
                self.sendServerMessage(.apps(list: snapshot), to: conn)
            }
        }
    }

    private func unregisterClient(_ conn: NWConnection) {
        clients.removeValue(forKey: ObjectIdentifier(conn))
        let count = clients.count
        Task { @MainActor in self.clientCount = count }
        conn.cancel()
    }

    private func readWebSocket(_ conn: NWConnection, buffer: Data) {
        var buffer = buffer
        // Drain any complete frames already sitting in the buffer.
        while let frame = WebSocket.decodeOne(from: &buffer) {
            handleFrame(frame, conn: conn)
        }
        conn.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            if let data { buffer.append(data) }
            while let frame = WebSocket.decodeOne(from: &buffer) {
                self.handleFrame(frame, conn: conn)
            }
            if error != nil || isComplete {
                self.unregisterClient(conn)
                return
            }
            self.readWebSocket(conn, buffer: buffer)
        }
    }

    private func handleFrame(_ frame: WebSocket.Frame, conn: NWConnection) {
        switch frame.opcode {
        case .text:
            guard let message = try? JSONDecoder().decode(ClientMessage.self, from: frame.payload) else {
                NSLog("PoorDeck: undecodable client message")
                return
            }
            handle(message, conn: conn)
        case .ping:
            conn.send(content: WebSocket.encode(frame.payload, opcode: .pong), completion: .idempotent)
        case .close:
            unregisterClient(conn)
        default:
            break
        }
    }

    private func handle(_ message: ClientMessage, conn: NWConnection) {
        switch message {
        case .hello(let name):
            NSLog("PoorDeck: client said hello (\(name ?? "anon"))")
        case .press(let buttonId):
            Task { @MainActor in
                let button = DeckStore.shared.button(id: buttonId)
                var ok = false
                switch button?.action.kind {
                case .openApp:
                    if let bundleId = button?.action.bundleId {
                        ok = AppLauncher.openApp(bundleId: bundleId)
                    }
                case .keyShortcut:
                    if let shortcut = button?.action.shortcut {
                        ok = KeyEmitter.send(shortcut, activating: button?.action.bundleId)
                    }
                default:
                    break
                }
                self.sendServerMessage(.ack(buttonId: buttonId, ok: ok), to: conn)
            }
        case .volume(let target, let value):
            // Fire-and-forget: apply, then broadcast so every client (and
            // this one too) converges to the new level. We don't echo back
            // the same value we just wrote — CoreAudio's own listener will
            // fire and the systemVolume bridge will fan it out, so a manual
            // broadcast here would just be a duplicate.
            switch target {
            case .system:
                _ = SystemVolume.set(value)
            }
        case .setAppVolume(let id, let value, let muted):
            Task { @MainActor in
                guard let process = self.audio.process(idString: id) else { return }
                if muted {
                    self.audio.toggleMute(process)
                } else {
                    self.audio.setVolume(value, for: process)
                }
                // Broadcast the resulting level to all clients (including the
                // sender). The sender drops the echo with its own isEcho
                // check, so the only effect is keeping other clients in sync.
                self.broadcast(.appVolume(id: id,
                                           volume: self.audio.volume(for: process),
                                           muted: self.audio.isMuted(process)))
            }
        case .deviceOrientation(let isPortrait):
            // Update the server's last-known device orientation. The
            // editor's "Follow device" canvas mode reads this to
            // re-render the preview the same way the phone is held.
            self.lastDeviceOrientationIsPortrait = isPortrait
        }
    }

    private func sendLayout(to conn: NWConnection) {
        Task { @MainActor in
            let layout = DeckStore.shared.resolvedLayout()
            self.sendServerMessage(.layout(layout), to: conn)
        }
    }

    private func sendServerMessage(_ message: ServerMessage, to conn: NWConnection) {
        guard let data = try? JSONEncoder().encode(message),
              let text = String(data: data, encoding: .utf8) else { return }
        conn.send(content: WebSocket.encode(text: text), completion: .idempotent)
    }

    /// Send the same message to every connected client. Used for system
    /// events (volume changes) that should reach all peers, not just the
    /// socket that triggered them. Hopped onto the network queue because
    /// `clients` is owned by that queue.
    private func broadcast(_ message: ServerMessage) {
        queue.async { [weak self] in
            guard let self else { return }
            guard let data = try? JSONEncoder().encode(message),
                  let text = String(data: data, encoding: .utf8) else { return }
            let frame = WebSocket.encode(text: text)
            for conn in self.clients.values {
                conn.send(content: frame, completion: .idempotent)
            }
        }
    }

    // MARK: HTTP send helper

    private func send(_ conn: NWConnection, _ response: Data, close: Bool, contentType: String? = nil) {
        conn.send(content: response, completion: .contentProcessed { _ in
            if close { conn.cancel() }
        })
    }

    // MARK: Web root + content types

    static func webRoot() -> URL {
        if let override = ProcessInfo.processInfo.environment["POORDECK_WEBROOT"] {
            return URL(fileURLWithPath: override, isDirectory: true)
        }
        return Bundle.main.resourceURL?.appendingPathComponent("web", isDirectory: true)
            ?? URL(fileURLWithPath: NSTemporaryDirectory())
    }

    static func contentType(for url: URL) -> String {
        switch url.pathExtension.lowercased() {
        case "html": return "text/html; charset=utf-8"
        case "js", "mjs": return "text/javascript; charset=utf-8"
        case "css": return "text/css; charset=utf-8"
        case "json": return "application/json; charset=utf-8"
        case "png": return "image/png"
        case "jpg", "jpeg": return "image/jpeg"
        case "svg": return "image/svg+xml"
        case "ico": return "image/x-icon"
        case "webmanifest": return "application/manifest+json"
        case "woff2": return "font/woff2"
        case "map": return "application/json"
        default: return "application/octet-stream"
        }
    }

    /// Fallback page shown when the Svelte client hasn't been built yet.
    static func placeholderPage(pairingURL: String) -> String {
        """
        <!doctype html><meta charset=utf-8>
        <title>PoorDeck</title>
        <body style="font-family:-apple-system,sans-serif;background:#0f1115;color:#e7e9ee;text-align:center;padding:3rem">
        <h1>PoorDeck server is running</h1>
        <p>The client bundle isn't built yet.</p>
        <p>Run <code>npm run build</code> in <code>client/</code>, or start with
        <code>POORDECK_WEBROOT=…/client/dist</code>.</p>
        <p>Paired at <b>\(pairingURL)</b></p>
        </body>
        """
    }
}
