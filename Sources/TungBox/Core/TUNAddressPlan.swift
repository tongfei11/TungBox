import Foundation

/// One address plan for both Core's automatic TUN DNS and the launchd service.
/// Core reserves the address after the first TUN IPv4 address for DNS; requests
/// sent elsewhere in the Fake-IP pool reach ordinary routing and may fail lookup.
enum TUNAddressPlan {
    static let interfaceIPv4 = "198.19.0.1"
    static let dnsIPv4 = dnsAddress(after: interfaceIPv4)!

    static func dnsAddress(after address: String) -> String? {
        let parts = address.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 4 else { return nil }
        let octets = parts.compactMap { UInt8($0) }
        guard octets.count == 4 else { return nil }
        let value = octets.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        // Managed TUN prefixes are /30; never wrap across a subnet boundary.
        guard value & 3 < 3 else { return nil }
        let next = value + 1
        return [24, 16, 8, 0].map { String((next >> $0) & 255) }.joined(separator: ".")
    }
}
