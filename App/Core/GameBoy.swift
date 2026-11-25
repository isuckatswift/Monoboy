import Foundation

/// Ties the CPU and memory bus together and runs whole frames.
final class GameBoy {
    let mmu: MMU
    let cpu: CPU

    var cartridge: Cartridge { mmu.cartridge }

    private static let cyclesPerFrame = 70224

    init(cartridge: Cartridge) {
        mmu = MMU(cartridge: cartridge)
        cpu = CPU(mmu: mmu)
        #if DEBUG
        mmu.serialOutput = { byte in
            print(String(UnicodeScalar(byte)), terminator: "")
        }
        #endif
    }

    /// Runs one frame's worth of emulation.
    ///
    /// - LCD on: runs until the PPU finishes a frame (start of VBlank).
    /// - LCD off (or CPU stopped): the PPU never signals a frame, so run exactly
    ///   one frame of cycles. This keeps emulation speed at 1x instead of 2x.
    /// - Illegal opcode: returns immediately; check `cpu.illegalOpcode`.
    func runFrame() {
        mmu.ppu.frameComplete = false
        var elapsed = 0

        while !mmu.ppu.frameComplete {
            let limit = (mmu.ppu.isLCDEnabled && !cpu.isStopped)
                ? GameBoy.cyclesPerFrame * 2   // safety net only; VBlank ends the frame first
                : GameBoy.cyclesPerFrame
            if elapsed >= limit { break }

            let cycles = cpu.step()
            if cpu.illegalOpcode != nil { return }

            // STOP freezes the whole system, including timers and the LCD.
            if !cpu.isStopped { mmu.tick(cycles) }
            elapsed += cycles
        }
    }
}
