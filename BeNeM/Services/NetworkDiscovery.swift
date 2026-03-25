import Foundation
import Network
import Darwin

struct DiscoveredServer: Identifiable {
    let id = UUID()
    let ip: String
    let sysDescr: String
    var baseURL: String { "http://\(ip)" }

    /// True only for Core and Primary instances — the ones that expose the management API.
    var isConnectable: Bool {
        sysDescr.hasPrefix("BMC Helix Network Management Core") ||
        sysDescr.hasPrefix("BMC Helix Network Management Primary")
    }
}

class NetworkDiscovery: ObservableObject {
    @Published var servers: [DiscoveredServer] = []
    @Published var isScanning = false
    @Published var progress: Double = 0
    @Published var scannedCount: Int = 0
    @Published var totalCount: Int = 0
    @Published var errorMessage: String?

    // Max simultaneous UDP connections
    private let concurrencyLimit = 30

    /// True when the device is on a /24 (Class C) Wi-Fi subnet — the only configuration
    /// the scanner supports.
    static var isOnClassCWiFi: Bool { localNetworkInfo() != nil }

    @MainActor
    func scan() async {
        guard let info = localNetworkInfo() else {
            errorMessage = "Auto Discovery requires Wi-Fi with a /24 subnet (Class C)."
            return
        }

        isScanning = true
        servers = []
        errorMessage = nil
        scannedCount = 0
        progress = 0

        // Build candidate IPs: skip .1 (gateway) and local IP
        var ips: [String] = []
        for i in 2...254 {
            if i == info.lastOctet { continue }
            ips.append("\(info.prefix).\(i)")
        }
        totalCount = ips.count

        // Sliding-window concurrency: keep up to concurrencyLimit tasks running
        await withTaskGroup(of: DiscoveredServer?.self) { group in
            var pending = 0
            var ipIterator = ips.makeIterator()

            // Seed initial tasks
            while pending < concurrencyLimit, let ip = ipIterator.next() {
                group.addTask { await self.probe(ip: ip) }
                pending += 1
            }

            // As each task finishes, update UI and start next IP
            for await result in group {
                scannedCount += 1
                progress = Double(scannedCount) / Double(totalCount)
                if let server = result { servers.append(server) }
                pending -= 1
                if let ip = ipIterator.next() {
                    group.addTask { await self.probe(ip: ip) }
                    pending += 1
                }
            }
        }

        isScanning = false
    }

    // MARK: - SNMP probe

    /// Sends an SNMPv2c GET-NEXT for OID .1.3.6.1 to port 161.
    /// Returns a DiscoveredServer if the response contains "BMC Helix Network Management".
    nonisolated private func probe(ip: String) async -> DiscoveredServer? {
        let packet = Data(snmpGetNextPacket())
        guard let response = await sendUDP(to: ip, port: 161, data: packet, timeout: 1.0) else {
            return nil
        }
        let marker = "BMC Helix Network Management"
        guard let markerBytes = marker.data(using: .utf8),
              let markerRange = response.range(of: markerBytes) else { return nil }

        // Extract printable ASCII from the marker position onward (max 100 chars)
        let descBytes = response[markerRange.lowerBound...]
        let sysDescr = String(
            descBytes.prefix(100)
                .compactMap { b -> Character? in
                    guard b >= 0x20, b < 0x7F else { return nil }
                    return Character(UnicodeScalar(b))
                }
        )
        return DiscoveredServer(ip: ip, sysDescr: sysDescr)
    }

    // MARK: - UDP

    nonisolated private func sendUDP(to ip: String, port: UInt16, data: Data, timeout: TimeInterval) async -> Data? {
        await withCheckedContinuation { continuation in
            let conn = NWConnection(
                host: NWEndpoint.Host(ip),
                port: NWEndpoint.Port(integerLiteral: port),
                using: .udp
            )
            var finished = false
            let lock = NSLock()

            func finish(_ result: Data?) {
                lock.lock()
                defer { lock.unlock() }
                guard !finished else { return }
                finished = true
                conn.cancel()
                continuation.resume(returning: result)
            }

            conn.stateUpdateHandler = { state in
                switch state {
                case .ready:
                    conn.send(content: data, completion: .contentProcessed { _ in })
                    conn.receiveMessage { content, _, _, _ in finish(content) }
                case .failed, .cancelled:
                    finish(nil)
                default:
                    break
                }
            }
            conn.start(queue: .global(qos: .userInitiated))
            DispatchQueue.global().asyncAfter(deadline: .now() + timeout) { finish(nil) }
        }
    }

    // MARK: - SNMP packet

    /// SNMPv2c GET-NEXT request for OID .1.3.6.1, community "snmp4netreo".
    /// BER-encoded, 43 bytes total.
    nonisolated private func snmpGetNextPacket() -> [UInt8] {
        [
            0x30, 0x29,                               // SEQUENCE (41 bytes)
            0x02, 0x01, 0x01,                         // INTEGER: version 1 (SNMPv2c)
            0x04, 0x0B,                               // OCTET STRING (11 bytes): community
            0x73, 0x6E, 0x6D, 0x70, 0x34,            // "snmp4"
            0x6E, 0x65, 0x74, 0x72, 0x65, 0x6F,      // "netreo"
            0xA1, 0x17,                               // GetNextRequest-PDU (23 bytes)
            0x02, 0x04, 0x00, 0x00, 0x00, 0x01,       // INTEGER: request-id = 1
            0x02, 0x01, 0x00,                         // INTEGER: error-status = 0
            0x02, 0x01, 0x00,                         // INTEGER: error-index = 0
            0x30, 0x09,                               // SEQUENCE: varbind-list (9 bytes)
            0x30, 0x07,                               // SEQUENCE: varbind (7 bytes)
            0x06, 0x03, 0x2B, 0x06, 0x01,             // OID: .1.3.6.1
            0x05, 0x00                                // NULL
        ]
    }
}

// MARK: - Network info helpers

struct LocalNetworkInfo {
    let prefix: String    // e.g. "192.168.1"
    let lastOctet: Int    // local IP's last octet, to skip self
}

func localNetworkInfo() -> LocalNetworkInfo? {
    var ifaddr: UnsafeMutablePointer<ifaddrs>?
    guard getifaddrs(&ifaddr) == 0 else { return nil }
    defer { freeifaddrs(ifaddr) }

    var ptr = ifaddr
    while let cur = ptr {
        defer { ptr = cur.pointee.ifa_next }

        let flags = Int32(cur.pointee.ifa_flags)
        guard (flags & IFF_UP) != 0,
              (flags & IFF_LOOPBACK) == 0,
              let addr = cur.pointee.ifa_addr,
              addr.pointee.sa_family == UInt8(AF_INET),
              String(cString: cur.pointee.ifa_name) == "en0", // Wi-Fi only
              let netmask = cur.pointee.ifa_netmask else { continue }

        // Verify /24 subnet mask
        var maskBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(netmask, socklen_t(netmask.pointee.sa_len),
                    &maskBuf, socklen_t(maskBuf.count), nil, 0, NI_NUMERICHOST)
        guard String(cString: maskBuf) == "255.255.255.0" else { return nil }

        // Get local IP
        var ipBuf = [CChar](repeating: 0, count: Int(NI_MAXHOST))
        getnameinfo(addr, socklen_t(addr.pointee.sa_len),
                    &ipBuf, socklen_t(ipBuf.count), nil, 0, NI_NUMERICHOST)
        let ip = String(cString: ipBuf)

        let parts = ip.split(separator: ".")
        guard parts.count == 4, let last = Int(parts[3]) else { return nil }
        return LocalNetworkInfo(prefix: parts.prefix(3).joined(separator: "."), lastOctet: last)
    }
    return nil
}
