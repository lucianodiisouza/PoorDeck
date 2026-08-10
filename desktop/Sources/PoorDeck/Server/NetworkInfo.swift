import Foundation

enum NetworkInfo {
    /// Best-guess LAN IPv4 address for building the pairing URL / QR code.
    /// Prefers Wi-Fi (`en0`), then other `enX` interfaces. Returns nil if the
    /// Mac isn't on a network.
    static func primaryIPv4() -> String? {
        var candidates: [(iface: String, ip: String)] = []
        var ifaddr: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&ifaddr) == 0, let first = ifaddr else { return nil }
        defer { freeifaddrs(ifaddr) }

        var ptr: UnsafeMutablePointer<ifaddrs>? = first
        while let cur = ptr {
            let flags = Int32(cur.pointee.ifa_flags)
            let addr = cur.pointee.ifa_addr
            if let addr,
               addr.pointee.sa_family == UInt8(AF_INET),
               (flags & IFF_UP) == IFF_UP,
               (flags & IFF_LOOPBACK) == 0 {
                let name = String(cString: cur.pointee.ifa_name)
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                if getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                               &host, socklen_t(host.count),
                               nil, 0, NI_NUMERICHOST) == 0 {
                    candidates.append((name, String(cString: host)))
                }
            }
            ptr = cur.pointee.ifa_next
        }

        return candidates.first(where: { $0.iface == "en0" })?.ip
            ?? candidates.first(where: { $0.iface.hasPrefix("en") })?.ip
            ?? candidates.first?.ip
    }
}
