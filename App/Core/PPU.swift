import Foundation

/// Scanline-based DMG picture processing unit.
final class PPU {
    static let screenWidth = 160
    static let screenHeight = 144

    var vram = [UInt8](repeating: 0, count: 0x2000)
    var oam = [UInt8](repeating: 0, count: 0xA0)

    /// RGBA pixels, 160x144, packed as R | G<<8 | B<<16 | A<<24.
    private(set) var framebuffer = [UInt32](repeating: 0, count: 160 * 144)
    var palette: [UInt32] = DMGPalette.mono.colors

    // Registers
    private var lcdc: UInt8 = 0x91
    private var stat: UInt8 = 0
    private var scy: UInt8 = 0
    private var scx: UInt8 = 0
    private var ly: UInt8 = 0
    private var lyc: UInt8 = 0
    private var bgp: UInt8 = 0xFC
    private var obp0: UInt8 = 0xFF
    private var obp1: UInt8 = 0xFF
    private var wy: UInt8 = 0
    private var wx: UInt8 = 0

    private var mode: UInt8 = 2
    private var dots = 0
    private var windowLine = 0
    /// Previous level of the combined STAT interrupt line (for rising-edge detection).
    private var statLine = false

    var isLCDEnabled: Bool { lcdc & 0x80 != 0 }

    /// Set when a full frame has been drawn (start of VBlank).
    var frameComplete = false
    /// Pending interrupt request bits (bit 0 = VBlank, bit 1 = STAT).
    var irq: UInt8 = 0

    private var lineBG = [UInt8](repeating: 0, count: 160)
    private var spriteList: [Int] = []

    init() {
        framebuffer = [UInt32](repeating: palette[0], count: 160 * 144)
    }

    // MARK: - Registers

    func read(_ addr: UInt16) -> UInt8 {
        switch addr {
        case 0xFF40: return lcdc
        case 0xFF41:
            let lcdOn = lcdc & 0x80 != 0
            let coincidence: UInt8 = (lcdOn && ly == lyc) ? 0x04 : 0
            return 0x80 | (stat & 0x78) | coincidence | (lcdOn ? mode : 0)
        case 0xFF42: return scy
        case 0xFF43: return scx
        case 0xFF44: return ly
        case 0xFF45: return lyc
        case 0xFF47: return bgp
        case 0xFF48: return obp0
        case 0xFF49: return obp1
        case 0xFF4A: return wy
        case 0xFF4B: return wx
        default: return 0xFF
        }
    }

    func write(_ addr: UInt16, _ value: UInt8) {
        switch addr {
        case 0xFF40:
            let wasOn = lcdc & 0x80 != 0
            lcdc = value
            let isOn = value & 0x80 != 0
            if wasOn && !isOn {
                ly = 0
                dots = 0
                mode = 0
                windowLine = 0
                statLine = false
                for i in 0..<framebuffer.count { framebuffer[i] = palette[0] }
            } else if !wasOn && isOn {
                ly = 0
                dots = 0
                mode = 2
                updateStatLine()
            }
        case 0xFF41:
            stat = value & 0x78
            if isLCDEnabled { updateStatLine() }
        case 0xFF42: scy = value
        case 0xFF43: scx = value
        case 0xFF44: break // LY is read-only
        case 0xFF45:
            lyc = value
            if isLCDEnabled { updateStatLine() }
        case 0xFF47: bgp = value
        case 0xFF48: obp0 = value
        case 0xFF49: obp1 = value
        case 0xFF4A: wy = value
        case 0xFF4B: wx = value
        default: break
        }
    }

    // MARK: - Timing

    /// STAT interrupts come from one combined signal: the OR of every enabled
    /// condition (LYC match, HBlank, VBlank, OAM scan). An interrupt is requested
    /// only when that signal goes from low to high, so overlapping conditions
    /// don't fire twice ("STAT blocking").
    private func updateStatLine() {
        var line = false
        if lcdc & 0x80 != 0 {
            if ly == lyc && stat & 0x40 != 0 { line = true }
            switch mode {
            case 0: if stat & 0x08 != 0 { line = true }
            case 1: if stat & 0x10 != 0 { line = true }
            case 2: if stat & 0x20 != 0 { line = true }
            default: break
            }
        }
        if line && !statLine { irq |= 0x02 }
        statLine = line
    }

    /// Advance by `cycles` T-cycles (always <= 24, so at most one mode change per call).
    func step(_ cycles: Int) {
        guard lcdc & 0x80 != 0 else { return }
        dots += cycles

        switch mode {
        case 2: // OAM scan
            if dots >= 80 {
                dots -= 80
                mode = 3
                updateStatLine()
            }
        case 3: // Drawing
            if dots >= 172 {
                dots -= 172
                mode = 0
                renderScanline()
                updateStatLine()
            }
        case 0: // HBlank
            if dots >= 204 {
                dots -= 204
                ly += 1
                if ly == 144 {
                    mode = 1
                    irq |= 0x01          // VBlank interrupt
                    frameComplete = true
                } else {
                    mode = 2
                }
                updateStatLine()
            }
        default: // VBlank
            if dots >= 456 {
                dots -= 456
                ly += 1
                if ly > 153 {
                    ly = 0
                    mode = 2
                    windowLine = 0
                }
                updateStatLine()
            }
        }
    }

    // MARK: - Rendering

    private func renderScanline() {
        let y = Int(ly)
        let rowBase = y * 160
        let bgEnabled = lcdc & 0x01 != 0
        let unsignedTiles = lcdc & 0x10 != 0
        let bgMap = lcdc & 0x08 != 0 ? 0x1C00 : 0x1800
        let winMap = lcdc & 0x40 != 0 ? 0x1C00 : 0x1800
        let windowOn = bgEnabled && lcdc & 0x20 != 0 && y >= Int(wy) && Int(wx) <= 166
        let winX = Int(wx) - 7
        var drewWindow = false

        for x in 0..<160 {
            var color: UInt8 = 0
            if bgEnabled {
                let px: Int, py: Int, map: Int
                if windowOn && x >= winX {
                    drewWindow = true
                    px = x - winX
                    py = windowLine
                    map = winMap
                } else {
                    px = (x + Int(scx)) & 0xFF
                    py = (y + Int(scy)) & 0xFF
                    map = bgMap
                }
                let tileIndex = vram[map + (py >> 3) * 32 + (px >> 3)]
                let tileAddr: Int
                if unsignedTiles {
                    tileAddr = Int(tileIndex) * 16
                } else {
                    tileAddr = 0x1000 + Int(Int8(bitPattern: tileIndex)) * 16
                }
                let rowAddr = tileAddr + (py & 7) * 2
                let lo = vram[rowAddr]
                let hi = vram[rowAddr + 1]
                let bit = UInt8(7 - (px & 7))
                color = (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1)
            }
            lineBG[x] = color
            framebuffer[rowBase + x] = palette[Int((bgp >> (color * 2)) & 3)]
        }

        if drewWindow { windowLine += 1 }
        if lcdc & 0x02 != 0 { renderSprites(y: y, rowBase: rowBase) }
    }

    private func renderSprites(y: Int, rowBase: Int) {
        let tall = lcdc & 0x04 != 0
        let height = tall ? 16 : 8

        spriteList.removeAll(keepingCapacity: true)
        for i in 0..<40 {
            let top = Int(oam[i * 4]) - 16
            if y >= top && y < top + height {
                spriteList.append(i)
                if spriteList.count == 10 { break }
            }
        }

        // Lowest priority first so higher-priority sprites overwrite them.
        // DMG priority: smaller X wins; ties go to the lower OAM index.
        spriteList.sort { lhs, rhs in
            let xl = oam[lhs * 4 + 1]
            let xr = oam[rhs * 4 + 1]
            return xl != xr ? xl > xr : lhs > rhs
        }

        for i in spriteList {
            let top = Int(oam[i * 4]) - 16
            let left = Int(oam[i * 4 + 1]) - 8
            var tile = Int(oam[i * 4 + 2])
            let attr = oam[i * 4 + 3]

            var row = y - top
            if attr & 0x40 != 0 { row = height - 1 - row }
            if tall { tile = (tile & 0xFE) | (row >> 3) }

            let addr = tile * 16 + (row & 7) * 2
            let lo = vram[addr]
            let hi = vram[addr + 1]
            let xFlip = attr & 0x20 != 0
            let behindBG = attr & 0x80 != 0
            let pal = attr & 0x10 != 0 ? obp1 : obp0

            for sx in 0..<8 {
                let px = left + sx
                guard px >= 0 && px < 160 else { continue }
                let bit = UInt8(xFlip ? sx : 7 - sx)
                let color = (((hi >> bit) & 1) << 1) | ((lo >> bit) & 1)
                if color == 0 { continue }
                if behindBG && lineBG[px] != 0 { continue }
                framebuffer[rowBase + px] = palette[Int((pal >> (color * 2)) & 3)]
            }
        }
    }
}
