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

    /// Runs until the PPU finishes a frame (or one frame's worth of cycles
    /// if the LCD is switched off).
    func runFrame() {
        mmu.ppu.frameComplete = false
        var elapsed = 0
        while !mmu.ppu.frameComplete && elapsed < GameBoy.cyclesPerFrame * 2 {
            let cycles = cpu.step()
            mmu.tick(cycles)
            elapsed += cycles
        }
    }
}
