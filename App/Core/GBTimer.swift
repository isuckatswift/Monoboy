import Foundation

/// DIV / TIMA / TMA / TAC. Named GBTimer to avoid clashing with Foundation.Timer.
///
/// Models the hardware's falling-edge detection on the divider bit selected by TAC,
/// including the one machine-cycle delay between TIMA overflowing and the reload
/// from TMA / interrupt request.
final class GBTimer {
    private var counter: UInt16 = 0xABCC   // internal 16-bit divider; DIV is the top byte
    var tima: UInt8 = 0
    var tma: UInt8 = 0
    private(set) var tac: UInt8 = 0xF8

    /// Pending interrupt request bits (bit 2 = timer). Merged into IF by the MMU.
    var irq: UInt8 = 0

    /// TIMA overflowed during the previous machine cycle: it reads 0x00 and the
    /// reload + interrupt happen on the next machine cycle.
    private var overflowPending = false
    /// This machine cycle is the one in which TIMA was reloaded from TMA.
    private var reloadCycle = false

    var div: UInt8 { UInt8(counter >> 8) }

    /// Divider bit watched for each TAC clock select: 4096 Hz, 262144 Hz, 65536 Hz, 16384 Hz.
    private var mask: UInt16 {
        switch tac & 0x03 {
        case 0: return 0x0200
        case 1: return 0x0008
        case 2: return 0x0020
        default: return 0x0080
        }
    }

    private func signal(_ value: UInt16) -> Bool {
        return tac & 0x04 != 0 && value & mask != 0
    }

    private func increment() {
        if tima == 0xFF {
            tima = 0x00
            overflowPending = true
        } else {
            tima += 1
        }
    }

    /// `cycles` is in T-cycles and is always a multiple of 4 (one machine cycle per iteration).
    func step(_ cycles: Int) {
        var remaining = cycles
        while remaining > 0 {
            reloadCycle = false
            if overflowPending {
                overflowPending = false
                tima = tma
                irq |= 0x04
                reloadCycle = true
            }

            let before = signal(counter)
            counter &+= 4
            if before && !signal(counter) { increment() }
            remaining -= 4
        }
    }

    // MARK: - Register writes

    /// Writing DIV resets the divider, which can produce a falling edge.
    func resetDivider() {
        let before = signal(counter)
        counter = 0
        if before { increment() }
    }

    /// Changing TAC can also produce a falling edge.
    func writeTAC(_ value: UInt8) {
        let before = signal(counter)
        tac = value | 0xF8
        if before && !signal(counter) { increment() }
    }

    /// A write while TIMA reads 0 after overflow cancels the reload and the interrupt.
    /// A write during the reload cycle itself is ignored (TMA wins).
    func writeTIMA(_ value: UInt8) {
        if reloadCycle { return }
        overflowPending = false
        tima = value
    }

    /// A write during the reload cycle is also copied into TIMA.
    func writeTMA(_ value: UInt8) {
        tma = value
        if reloadCycle { tima = value }
    }
}
