import Foundation

/// Raised when the CPU fetches one of the 11 undefined LR35902 opcodes.
/// Real hardware locks up permanently; the emulator does the same and reports it.
struct IllegalOpcode: LocalizedError {
    let opcode: UInt8
    let address: UInt16

    var errorDescription: String? {
        String(format: "The game executed an illegal instruction (0x%02X at 0x%04X) and the CPU locked up.",
               Int(opcode), Int(address))
    }
}

/// Sharp LR35902 (Game Boy CPU) interpreter.
/// Instructions execute atomically and return their cost in T-cycles.
final class CPU {
    // Registers (post-boot-ROM values)
    var a: UInt8 = 0x01
    var f: UInt8 = 0xB0
    var b: UInt8 = 0x00
    var c: UInt8 = 0x13
    var d: UInt8 = 0x00
    var e: UInt8 = 0xD8
    var h: UInt8 = 0x01
    var l: UInt8 = 0x4D
    var sp: UInt16 = 0xFFFE
    var pc: UInt16 = 0x0100

    private var ime = false
    private var eiPending = false
    private var halted = false
    private var haltBug = false

    /// True after STOP until a button is pressed. The whole system is frozen meanwhile.
    private(set) var isStopped = false
    /// Non-nil once an illegal opcode has been executed. The CPU stays locked up.
    private(set) var illegalOpcode: IllegalOpcode?

    unowned private let mmu: MMU

    init(mmu: MMU) {
        self.mmu = mmu
    }

    // MARK: - Register pairs

    var af: UInt16 {
        get { (UInt16(a) << 8) | UInt16(f) }
        set { a = UInt8(newValue >> 8); f = UInt8(newValue & 0xF0) }
    }
    var bc: UInt16 {
        get { (UInt16(b) << 8) | UInt16(c) }
        set { b = UInt8(newValue >> 8); c = UInt8(newValue & 0xFF) }
    }
    var de: UInt16 {
        get { (UInt16(d) << 8) | UInt16(e) }
        set { d = UInt8(newValue >> 8); e = UInt8(newValue & 0xFF) }
    }
    var hl: UInt16 {
        get { (UInt16(h) << 8) | UInt16(l) }
        set { h = UInt8(newValue >> 8); l = UInt8(newValue & 0xFF) }
    }

    private func getRR(_ i: Int) -> UInt16 {
        switch i {
        case 0: return bc
        case 1: return de
        case 2: return hl
        default: return sp
        }
    }

    private func setRR(_ i: Int, _ v: UInt16) {
        switch i {
        case 0: bc = v
        case 1: de = v
        case 2: hl = v
        default: sp = v
        }
    }

    /// 8-bit register by opcode index: B, C, D, E, H, L, (HL), A
    private func getReg(_ i: Int) -> UInt8 {
        switch i {
        case 0: return b
        case 1: return c
        case 2: return d
        case 3: return e
        case 4: return h
        case 5: return l
        case 6: return mmu.read(hl)
        default: return a
        }
    }

    private func setReg(_ i: Int, _ v: UInt8) {
        switch i {
        case 0: b = v
        case 1: c = v
        case 2: d = v
        case 3: e = v
        case 4: h = v
        case 5: l = v
        case 6: mmu.write(hl, v)
        default: a = v
        }
    }

    // MARK: - Fetch / stack

    private func fetch() -> UInt8 {
        let v = mmu.read(pc)
        if haltBug { haltBug = false } else { pc &+= 1 }
        return v
    }

    private func fetch16() -> UInt16 {
        let lo = UInt16(fetch())
        let hi = UInt16(fetch())
        return (hi << 8) | lo
    }

    private func push(_ v: UInt16) {
        sp &-= 1
        mmu.write(sp, UInt8(v >> 8))
        sp &-= 1
        mmu.write(sp, UInt8(v & 0xFF))
    }

    private func pop() -> UInt16 {
        let lo = UInt16(mmu.read(sp))
        sp &+= 1
        let hi = UInt16(mmu.read(sp))
        sp &+= 1
        return (hi << 8) | lo
    }

    // MARK: - Flags

    private func setFlags(z: Bool, n: Bool, h: Bool, c: Bool) {
        var flags: UInt8 = 0
        if z { flags |= 0x80 }
        if n { flags |= 0x40 }
        if h { flags |= 0x20 }
        if c { flags |= 0x10 }
        f = flags
    }

    private var carryFlag: Bool { f & 0x10 != 0 }

    private func condition(_ i: UInt8) -> Bool {
        switch i {
        case 0: return f & 0x80 == 0   // NZ
        case 1: return f & 0x80 != 0   // Z
        case 2: return f & 0x10 == 0   // NC
        default: return f & 0x10 != 0  // C
        }
    }

    // MARK: - ALU

    private func alu(_ op: Int, _ v: UInt8) {
        switch op {
        case 0: add(v, carry: false)
        case 1: add(v, carry: carryFlag)
        case 2: sub(v, carry: false, store: true)
        case 3: sub(v, carry: carryFlag, store: true)
        case 4: a &= v; setFlags(z: a == 0, n: false, h: true, c: false)
        case 5: a ^= v; setFlags(z: a == 0, n: false, h: false, c: false)
        case 6: a |= v; setFlags(z: a == 0, n: false, h: false, c: false)
        default: sub(v, carry: false, store: false) // CP
        }
    }

    private func add(_ v: UInt8, carry: Bool) {
        let cin: UInt16 = carry ? 1 : 0
        let result = UInt16(a) + UInt16(v) + cin
        let half = UInt16(a & 0x0F) + UInt16(v & 0x0F) + cin > 0x0F
        a = UInt8(truncatingIfNeeded: result)
        setFlags(z: a == 0, n: false, h: half, c: result > 0xFF)
    }

    private func sub(_ v: UInt8, carry: Bool, store: Bool) {
        let cin = carry ? 1 : 0
        let result = Int(a) - Int(v) - cin
        let half = Int(a & 0x0F) - Int(v & 0x0F) - cin < 0
        let byte = UInt8(truncatingIfNeeded: result)
        setFlags(z: byte == 0, n: true, h: half, c: result < 0)
        if store { a = byte }
    }

    private func inc8(_ v: UInt8) -> UInt8 {
        let r = v &+ 1
        var flags: UInt8 = f & 0x10
        if r == 0 { flags |= 0x80 }
        if v & 0x0F == 0x0F { flags |= 0x20 }
        f = flags
        return r
    }

    private func dec8(_ v: UInt8) -> UInt8 {
        let r = v &- 1
        var flags: UInt8 = (f & 0x10) | 0x40
        if r == 0 { flags |= 0x80 }
        if v & 0x0F == 0 { flags |= 0x20 }
        f = flags
        return r
    }

    private func addHL(_ v: UInt16) {
        let h0 = hl
        let result = UInt32(h0) + UInt32(v)
        let half = (h0 & 0x0FFF) + (v & 0x0FFF) > 0x0FFF
        hl = UInt16(truncatingIfNeeded: result)
        var flags: UInt8 = f & 0x80
        if half { flags |= 0x20 }
        if result > 0xFFFF { flags |= 0x10 }
        f = flags
    }

    private func spPlusOffset(_ raw: UInt8) -> UInt16 {
        let offset = Int(Int8(bitPattern: raw))
        let result = UInt16(truncatingIfNeeded: Int(sp) + offset)
        setFlags(z: false, n: false,
                 h: (sp & 0x0F) + UInt16(raw & 0x0F) > 0x0F,
                 c: (sp & 0xFF) + UInt16(raw) > 0xFF)
        return result
    }

    private func daa() {
        var adjust: UInt8 = 0
        var carry = carryFlag
        let subtract = f & 0x40 != 0
        if f & 0x20 != 0 || (!subtract && a & 0x0F > 9) { adjust |= 0x06 }
        if carry || (!subtract && a > 0x99) {
            adjust |= 0x60
            carry = true
        }
        a = subtract ? a &- adjust : a &+ adjust
        setFlags(z: a == 0, n: subtract, h: false, c: carry)
    }

    // MARK: - CB-prefixed

    private func rotateShift(_ kind: Int, _ v: UInt8) -> UInt8 {
        var carry = false
        let r: UInt8
        switch kind {
        case 0: carry = v & 0x80 != 0; r = (v << 1) | (carry ? 1 : 0)                 // RLC
        case 1: carry = v & 0x01 != 0; r = (v >> 1) | (carry ? 0x80 : 0)              // RRC
        case 2: carry = v & 0x80 != 0; r = (v << 1) | (carryFlag ? 1 : 0)             // RL
        case 3: carry = v & 0x01 != 0; r = (v >> 1) | (carryFlag ? 0x80 : 0)          // RR
        case 4: carry = v & 0x80 != 0; r = v << 1                                     // SLA
        case 5: carry = v & 0x01 != 0; r = (v >> 1) | (v & 0x80)                      // SRA
        case 6: r = (v << 4) | (v >> 4)                                               // SWAP
        default: carry = v & 0x01 != 0; r = v >> 1                                    // SRL
        }
        setFlags(z: r == 0, n: false, h: false, c: carry)
        return r
    }

    private func executeCB() -> Int {
        let op = fetch()
        let index = Int(op & 0x07)
        let bit = (op >> 3) & 0x07
        let isHL = index == 6
        let value = getReg(index)

        switch op >> 6 {
        case 0:
            setReg(index, rotateShift(Int(bit), value))
            return isHL ? 16 : 8
        case 1: // BIT
            var flags: UInt8 = (f & 0x10) | 0x20
            if value & (UInt8(1) << bit) == 0 { flags |= 0x80 }
            f = flags
            return isHL ? 12 : 8
        case 2: // RES
            setReg(index, value & ~(UInt8(1) << bit))
            return isHL ? 16 : 8
        default: // SET
            setReg(index, value | (UInt8(1) << bit))
            return isHL ? 16 : 8
        }
    }

    // MARK: - Stepping

    /// Executes one instruction (or services an interrupt) and returns T-cycles used.
    func step() -> Int {
        // Locked up by an illegal opcode: nothing can recover the CPU.
        if illegalOpcode != nil { return 4 }

        // STOP: only a button press wakes the CPU.
        if isStopped {
            if mmu.joypad.anyButtonPressed { isStopped = false } else { return 4 }
        }

        let pending = mmu.ie & mmu.ifReg & 0x1F

        if halted {
            if pending != 0 { halted = false } else { return 4 }
        }

        if ime && pending != 0 {
            ime = false
            let bit = pending.trailingZeroBitCount
            mmu.ifReg &= ~(UInt8(1) << UInt8(bit))
            push(pc)
            pc = 0x0040 &+ UInt16(bit) * 8
            return 20
        }

        let enableIME = eiPending
        eiPending = false
        let cycles = execute()
        if enableIME { ime = true }
        return cycles
    }

    private func lockUp(opcode: UInt8, address: UInt16) -> Int {
        illegalOpcode = IllegalOpcode(opcode: opcode, address: address)
        #if DEBUG
        print(String(format: "[CPU] Illegal opcode 0x%02X at PC=0x%04X", Int(opcode), Int(address)))
        #endif
        return 4
    }

    private func execute() -> Int {
        let address = pc
        let op = fetch()

        switch op {
        case 0x00: return 4

        // 16-bit loads / arithmetic
        case 0x01, 0x11, 0x21, 0x31:
            setRR(Int(op >> 4), fetch16()); return 12
        case 0x03, 0x13, 0x23, 0x33:
            let i = Int(op >> 4); setRR(i, getRR(i) &+ 1); return 8
        case 0x0B, 0x1B, 0x2B, 0x3B:
            let i = Int(op >> 4); setRR(i, getRR(i) &- 1); return 8
        case 0x09, 0x19, 0x29, 0x39:
            addHL(getRR(Int(op >> 4))); return 8
        case 0x08:
            let addr = fetch16()
            mmu.write(addr, UInt8(sp & 0xFF))
            mmu.write(addr &+ 1, UInt8(sp >> 8))
            return 20
        case 0xF9: sp = hl; return 8
        case 0xE8: sp = spPlusOffset(fetch()); return 16
        case 0xF8: hl = spPlusOffset(fetch()); return 12

        // Indirect loads
        case 0x02: mmu.write(bc, a); return 8
        case 0x12: mmu.write(de, a); return 8
        case 0x22: mmu.write(hl, a); hl &+= 1; return 8
        case 0x32: mmu.write(hl, a); hl &-= 1; return 8
        case 0x0A: a = mmu.read(bc); return 8
        case 0x1A: a = mmu.read(de); return 8
        case 0x2A: a = mmu.read(hl); hl &+= 1; return 8
        case 0x3A: a = mmu.read(hl); hl &-= 1; return 8
        case 0xE0: mmu.write(0xFF00 | UInt16(fetch()), a); return 12
        case 0xF0: a = mmu.read(0xFF00 | UInt16(fetch())); return 12
        case 0xE2: mmu.write(0xFF00 | UInt16(c), a); return 8
        case 0xF2: a = mmu.read(0xFF00 | UInt16(c)); return 8
        case 0xEA: mmu.write(fetch16(), a); return 16
        case 0xFA: a = mmu.read(fetch16()); return 16

        // 8-bit INC / DEC / LD r,n
        case 0x04, 0x0C, 0x14, 0x1C, 0x24, 0x2C, 0x34, 0x3C:
            let i = Int((op >> 3) & 7); setReg(i, inc8(getReg(i))); return i == 6 ? 12 : 4
        case 0x05, 0x0D, 0x15, 0x1D, 0x25, 0x2D, 0x35, 0x3D:
            let i = Int((op >> 3) & 7); setReg(i, dec8(getReg(i))); return i == 6 ? 12 : 4
        case 0x06, 0x0E, 0x16, 0x1E, 0x26, 0x2E, 0x36, 0x3E:
            let i = Int((op >> 3) & 7); setReg(i, fetch()); return i == 6 ? 12 : 8

        // Accumulator rotates and misc
        case 0x07:
            let carry = a >> 7
            a = (a << 1) | carry
            setFlags(z: false, n: false, h: false, c: carry != 0); return 4
        case 0x0F:
            let carry = a & 1
            a = (a >> 1) | (carry << 7)
            setFlags(z: false, n: false, h: false, c: carry != 0); return 4
        case 0x17:
            let carry = a >> 7
            a = (a << 1) | (carryFlag ? 1 : 0)
            setFlags(z: false, n: false, h: false, c: carry != 0); return 4
        case 0x1F:
            let carry = a & 1
            a = (a >> 1) | (carryFlag ? 0x80 : 0)
            setFlags(z: false, n: false, h: false, c: carry != 0); return 4
        case 0x27: daa(); return 4
        case 0x2F: a = ~a; f = (f & 0x90) | 0x60; return 4
        case 0x37: f = (f & 0x80) | 0x10; return 4
        case 0x3F: f = (f & 0x80) | (carryFlag ? 0 : 0x10); return 4
        case 0x10: // STOP (2 bytes: opcode + padding)
            _ = fetch()
            mmu.timer.resetDivider()
            if !mmu.joypad.anyButtonPressed { isStopped = true }
            return 4

        // Relative jumps
        case 0x18:
            let offset = Int(Int8(bitPattern: fetch()))
            pc = UInt16(truncatingIfNeeded: Int(pc) + offset); return 12
        case 0x20, 0x28, 0x30, 0x38:
            let offset = Int(Int8(bitPattern: fetch()))
            if condition((op >> 3) & 3) {
                pc = UInt16(truncatingIfNeeded: Int(pc) + offset); return 12
            }
            return 8

        // HALT
        case 0x76:
            let pending = mmu.ie & mmu.ifReg & 0x1F
            if !ime && pending != 0 { haltBug = true } else { halted = true }
            return 4

        // LD r,r'
        case 0x40...0x7F:
            let src = Int(op & 7), dst = Int((op >> 3) & 7)
            setReg(dst, getReg(src))
            return (src == 6 || dst == 6) ? 8 : 4

        // ALU A,r
        case 0x80...0xBF:
            let src = Int(op & 7)
            alu(Int((op >> 3) & 7), getReg(src))
            return src == 6 ? 8 : 4

        // Returns
        case 0xC0, 0xC8, 0xD0, 0xD8:
            if condition((op >> 3) & 3) { pc = pop(); return 20 }
            return 8
        case 0xC9: pc = pop(); return 16
        case 0xD9: pc = pop(); ime = true; return 16

        // Stack
        case 0xC1, 0xD1, 0xE1, 0xF1:
            let v = pop()
            switch (op >> 4) & 3 {
            case 0: bc = v
            case 1: de = v
            case 2: hl = v
            default: af = v
            }
            return 12
        case 0xC5, 0xD5, 0xE5, 0xF5:
            switch (op >> 4) & 3 {
            case 0: push(bc)
            case 1: push(de)
            case 2: push(hl)
            default: push(af)
            }
            return 16

        // Jumps / calls
        case 0xC3: pc = fetch16(); return 16
        case 0xE9: pc = hl; return 4
        case 0xC2, 0xCA, 0xD2, 0xDA:
            let target = fetch16()
            if condition((op >> 3) & 3) { pc = target; return 16 }
            return 12
        case 0xCD:
            let target = fetch16(); push(pc); pc = target; return 24
        case 0xC4, 0xCC, 0xD4, 0xDC:
            let target = fetch16()
            if condition((op >> 3) & 3) { push(pc); pc = target; return 24 }
            return 12
        case 0xC7, 0xCF, 0xD7, 0xDF, 0xE7, 0xEF, 0xF7, 0xFF:
            push(pc); pc = UInt16(op & 0x38); return 16

        // ALU A,n
        case 0xC6, 0xCE, 0xD6, 0xDE, 0xE6, 0xEE, 0xF6, 0xFE:
            alu(Int((op >> 3) & 7), fetch()); return 8

        case 0xCB: return executeCB()

        // Interrupt control
        case 0xF3: ime = false; eiPending = false; return 4
        case 0xFB: eiPending = true; return 4

        // The 11 undefined opcodes lock up the CPU on real hardware
        case 0xD3, 0xDB, 0xDD, 0xE3, 0xE4, 0xEB, 0xEC, 0xED, 0xF4, 0xFC, 0xFD:
            return lockUp(opcode: op, address: address)

        // Unreachable: every defined opcode is handled above
        default:
            return lockUp(opcode: op, address: address)
        }
    }
}
