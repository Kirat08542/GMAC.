import Foundation

/// Link-layer helpers.
public enum NetworkInterface {
    /// MAC address of the first active, non-loopback `en*` interface (usually Wi-Fi),
    /// formatted as "aa:bb:cc:dd:ee:ff". Shared with a paired iPhone so it can
    /// send Wake-on-LAN magic packets. Nil when no suitable interface exists.
    public static func primaryMACAddress() -> String? {
        var head: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&head) == 0, let head else { return nil }
        defer { freeifaddrs(head) }
        var cursor: UnsafeMutablePointer<ifaddrs>? = head
        while let current = cursor {
            let flags = current.pointee.ifa_flags
            let up = (flags & UInt32(IFF_UP)) != 0
            let loopback = (flags & UInt32(IFF_LOOPBACK)) != 0
            if up, !loopback, let addr = current.pointee.ifa_addr,
               addr.pointee.sa_family == sa_family_t(AF_LINK) {
                let sdl = addr.withMemoryRebound(to: sockaddr_dl.self, capacity: 1) { $0.pointee }
                if sdl.sdl_alen == 6, sdl.sdl_nlen > 0, Int(sdl.sdl_nlen) + 6 <= 12 {
                    let name: String = withUnsafeBytes(of: sdl.sdl_data) { raw in
                        String(cString: raw.baseAddress!.assumingMemoryBound(to: CChar.self))
                    }
                    if name.hasPrefix("en") {
                        let mac: [UInt8] = withUnsafeBytes(of: sdl.sdl_data) { raw in
                            let base = raw.baseAddress!.advanced(by: Int(sdl.sdl_nlen))
                            return Array(UnsafeBufferPointer(
                                start: base.assumingMemoryBound(to: UInt8.self),
                                count: 6
                            ))
                        }
                        return mac.map { String(format: "%02x", $0) }.joined(separator: ":")
                    }
                }
            }
            cursor = current.pointee.ifa_next
        }
        return nil
    }
}
