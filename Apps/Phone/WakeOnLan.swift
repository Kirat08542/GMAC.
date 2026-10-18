import Foundation

/// Sends Wake-on-LAN magic packets over the local Wi-Fi network.
enum WakeOnLan {
    /// Sends a magic packet for `mac` ("aa:bb:cc:dd:ee:ff") to the link-local
    /// broadcast address. Returns true when the packet reached the socket.
    /// The sleeping Mac's network interface must support Wake-on-LAN.
    static func send(mac: String, port: UInt16 = 9) -> Bool {
        let parts = mac.split(separator: ":")
        guard parts.count == 6 else { return false }
        var target = [UInt8]()
        target.reserveCapacity(6)
        for part in parts {
            guard part.count == 2, let byte = UInt8(part, radix: 16) else { return false }
            target.append(byte)
        }

        var packet = [UInt8](repeating: 0xFF, count: 6)
        for _ in 0..<16 {
            packet.append(contentsOf: target)
        }

        let fd = Darwin.socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else { return false }
        defer { Darwin.close(fd) }

        var broadcast: Int32 = 1
        guard Darwin.setsockopt(fd, SOL_SOCKET, SO_BROADCAST, &broadcast,
                                socklen_t(MemoryLayout<Int32>.size)) == 0 else { return false }

        var addr = sockaddr_in()
        addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        addr.sin_family = sa_family_t(AF_INET)
        addr.sin_port = port.bigEndian
        addr.sin_addr = in_addr(s_addr: INADDR_BROADCAST)

        let sent = packet.withUnsafeBytes { raw -> Int in
            guard let base = raw.baseAddress else { return -1 }
            return withUnsafePointer(to: &addr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    Darwin.sendto(fd, base, raw.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        return sent == packet.count
    }
}
