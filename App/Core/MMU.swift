import Foundation

/// The Game Boy memory bus. Owns the cartridge, PPU, timer and joypad.
final class MMU {
    let cartridge: Cartridge
    let ppu = PPU()
    let timer = GBTimer()
    let joypad = Joypad()

    private var wram = [UInt8](repeating: 0, count: 0x2000)
    private var hram = [UInt8](repeating: 0, count: 0x7F)
    private var io = [UInt8](repeating: 0, count: 0x80)   // audio regs, wave RAM, misc

    var ie: UInt8 = 0
    var ifReg: UInt8 = 0x01

    private var serialData: UInt8 = 0
    private var serialControl: UInt8 = 0x7E
    private var dmaReg: UInt8 = 0xFF

    /// Called with each byte a game writes to the serial port (handy for test ROMs).
    var serialOutput: ((UInt8) -> Void)?

    init(cartridge: Cartridge) {
        self.cartridge = cartridge
        io[0x26] = 0xF1 // NR52: audio on (audio itself isn't emulated yet)
    }

    // MARK: - Bus

    func read(_ addr: UInt16) -> UInt8 {
        switch addr {
        case 0x0000...0x7FFF: return cartridge.readROM(addr)
        case 0x8000...0x9FFF: return ppu.vram[Int(addr - 0x8000)]
        case 0xA000...0xBFFF: return cartridge.readRAM(addr)
        case 0xC000...0xDFFF: return wram[Int(addr - 0xC000)]
        case 0xE000...0xFDFF: return wram[Int(addr - 0xE000)]
        case 0xFE00...0xFE9F: return ppu.oam[Int(addr - 0xFE00)]
        case 0xFEA0...0xFEFF: return 0xFF
        case 0xFF00...0xFF7F: return readIO(addr)
        case 0xFF80...0xFFFE: return hram[Int(addr - 0xFF80)]
        default:              return ie
        }
    }

    func write(_ addr: UInt16, _ value: UInt8) {
        switch addr {
        case 0x0000...0x7FFF: cartridge.writeROM(addr, value)
        case 0x8000...0x9FFF: ppu.vram[Int(addr - 0x8000)] = value
        case 0xA000...0xBFFF: cartridge.writeRAM(addr, value)
        case 0xC000...0xDFFF: wram[Int(addr - 0xC000)] = value
        case 0xE000...0xFDFF: wram[Int(addr - 0xE000)] = value
        case 0xFE00...0xFE9F: ppu.oam[Int(addr - 0xFE00)] = value
        case 0xFEA0...0xFEFF: break
        case 0xFF00...0xFF7F: writeIO(addr, value)
        case 0xFF80...0xFFFE: hram[Int(addr - 0xFF80)] = value
        default:              ie = value
        }
    }

    private func readIO(_ addr: UInt16) -> UInt8 {
        switch addr {
        case 0xFF00: return joypad.read()
        case 0xFF01: return serialData
        case 0xFF02: return serialControl | 0x7E
        case 0xFF04: return timer.div
        case 0xFF05: return timer.tima
        case 0xFF06: return timer.tma
        case 0xFF07: return timer.tac
        case 0xFF0F: return ifReg | 0xE0
        case 0xFF46: return dmaReg
        case 0xFF40...0xFF4B: return ppu.read(addr)
        default: return io[Int(addr - 0xFF00)]
        }
    }

    private func writeIO(_ addr: UInt16, _ value: UInt8) {
        switch addr {
        case 0xFF00: joypad.write(value)
        case 0xFF01: serialData = value
        case 0xFF02:
            serialControl = value
            if value == 0x81 {
                serialOutput?(serialData)
                serialControl = value & 0x7F
            }
        case 0xFF04: timer.resetDivider()
        case 0xFF05: timer.tima = value
        case 0xFF06: timer.tma = value
        case 0xFF07: timer.writeTAC(value)
        case 0xFF0F: ifReg = value & 0x1F
        case 0xFF46:
            dmaReg = value
            let base = Int(value) << 8
            for i in 0..<0xA0 {
                ppu.oam[i] = read(UInt16(truncatingIfNeeded: base + i))
            }
        case 0xFF40...0xFF4B: ppu.write(addr, value)
        default: io[Int(addr - 0xFF00)] = value
        }
    }

    // MARK: - Clocking

    /// Advance all peripherals by `cycles` T-cycles and collect their interrupts.
    func tick(_ cycles: Int) {
        timer.step(cycles)
        ppu.step(cycles)
        ifReg |= timer.irq | ppu.irq | joypad.irq
        timer.irq = 0
        ppu.irq = 0
        joypad.irq = 0
    }
}
