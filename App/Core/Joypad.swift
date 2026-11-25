import Foundation

enum GBButton: CaseIterable {
    case right, left, up, down
    case a, b, select, start
}

final class Joypad {
    /// 0 bit = pressed (active low), matching hardware.
    private var directions: UInt8 = 0x0F
    private var actions: UInt8 = 0x0F
    private var select: UInt8 = 0x30

    /// Pending interrupt request bits (bit 4 = joypad). Merged into IF by the MMU.
    var irq: UInt8 = 0

    func read() -> UInt8 {
        var result: UInt8 = 0xCF | (select & 0x30)
        if select & 0x10 == 0 { result &= 0xF0 | directions }
        if select & 0x20 == 0 { result &= 0xF0 | actions }
        return result
    }

    func write(_ value: UInt8) {
        select = value & 0x30
    }

    func set(_ button: GBButton, pressed: Bool) {
        let isDirection: Bool
        let bit: UInt8
        switch button {
        case .right:  isDirection = true;  bit = 0
        case .left:   isDirection = true;  bit = 1
        case .up:     isDirection = true;  bit = 2
        case .down:   isDirection = true;  bit = 3
        case .a:      isDirection = false; bit = 0
        case .b:      isDirection = false; bit = 1
        case .select: isDirection = false; bit = 2
        case .start:  isDirection = false; bit = 3
        }
        let mask: UInt8 = 1 << bit
        let wasPressed: Bool
        if isDirection {
            wasPressed = directions & mask == 0
            if pressed { directions &= ~mask } else { directions |= mask }
        } else {
            wasPressed = actions & mask == 0
            if pressed { actions &= ~mask } else { actions |= mask }
        }
        if pressed && !wasPressed { irq |= 0x10 }
    }
}
