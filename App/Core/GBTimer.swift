import Foundation

/// DIV / TIMA / TMA / TAC. Named GBTimer to avoid clashing with Foundation.Timer.
final class GBTimer {
    private var counter: UInt16 = 0xABCC   // internal 16-bit divider; DIV is the top byte
    var tima: UInt8 = 0
    var tma: UInt8 = 0
    private(set) var tac: UInt8 = 0xF8

    /// Pending interrupt request bits (bit 2 = timer). Merged into IF by the MMU.
    var irq: UInt8 = 0

    var div: UInt8 { UInt8(counter >> 8) }

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
            tima = tma
            irq |= 0x04
        } else {
            tima += 1
        }
    }

    /// `cycles` is in T-cycles and is always a multiple of 4.
    func step(_ cycles: Int) {
        var remaining = cycles
        while remaining > 0 {
            let before = signal(counter)
            counter &+= 4
            if before && !signal(counter) { increment() }
            remaining -= 4
        }
    }

    func resetDivider() {
        let before = signal(counter)
        counter = 0
        if before { increment() }
    }

    func writeTAC(_ value: UInt8) {
        let before = signal(counter)
        tac = value | 0xF8
        if before && !signal(counter) { increment() }
    }
}
