import Foundation
import GLOTRemoteCore
import IOKit.pwr_mgt

/// Asks the logged-in Mac session to sleep through the public power API.
final class MacPowerController: RemotePower, @unchecked Sendable {
    func sleep() throws {
        let port = IOPMFindPowerManagement(mach_port_t(MACH_PORT_NULL))
        guard port != IO_OBJECT_NULL else {
            throw RemoteError.invalid("The Mac could not sleep.")
        }
        defer { IOServiceClose(port) }
        guard IOPMSleepSystem(port) == kIOReturnSuccess else {
            throw RemoteError.invalid("The Mac could not sleep.")
        }
    }
}
