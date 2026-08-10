import Foundation

/// Bare-bones HTTP/1.1 request parser — only what the embedded server needs:
/// the request line and headers. Bodies are ignored (our routes are all GET).
struct HTTPRequest {
    let method: String
    let path: String
    private let headers: [String: String] // lowercased keys

    init?(header: Data) {
        guard let text = String(data: header, encoding: .utf8) else { return nil }
        let lines = text.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else { return nil }
        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else { return nil }

        method = String(parts[0])
        path = String(parts[1])

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else { continue }
            let key = line[..<colon].trimmingCharacters(in: .whitespaces).lowercased()
            let value = line[line.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            headers[key] = value
        }
        self.headers = headers
    }

    func header(_ name: String) -> String? { headers[name.lowercased()] }

    var isWebSocketUpgrade: Bool {
        header("upgrade")?.lowercased() == "websocket"
            && (header("connection")?.lowercased().contains("upgrade") ?? false)
    }
}

enum HTTPResponse {
    static func file(_ body: Data, contentType: String) -> Data {
        var response = Data(header(200, contentType: contentType, length: body.count).utf8)
        response.append(body)
        return response
    }

    static func plain(_ status: Int, _ body: String, contentType: String = "text/plain; charset=utf-8") -> Data {
        let bodyData = Data(body.utf8)
        var response = Data(header(status, contentType: contentType, length: bodyData.count).utf8)
        response.append(bodyData)
        return response
    }

    private static func header(_ status: Int, contentType: String, length: Int) -> String {
        let reason = reasonPhrase(status)
        return [
            "HTTP/1.1 \(status) \(reason)",
            "Content-Type: \(contentType)",
            "Content-Length: \(length)",
            "Cache-Control: no-store",
            "Connection: close",
            "\r\n",
        ].joined(separator: "\r\n")
    }

    private static func reasonPhrase(_ status: Int) -> String {
        switch status {
        case 200: return "OK"
        case 400: return "Bad Request"
        case 404: return "Not Found"
        default: return "OK"
        }
    }
}
