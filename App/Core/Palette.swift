import Foundation

/// Four-shade palettes used to colorize the DMG's 2-bit output.
/// Colors are packed as R | G<<8 | B<<16 | A<<24 so they can be written
/// straight into an RGBA framebuffer.
enum DMGPalette: Int, CaseIterable, Identifiable {
    case mono = 0
    case classic
    case pocket
    case ice

    var id: Int { rawValue }

    var name: String {
        switch self {
        case .mono: return "Mono"
        case .classic: return "Classic Green"
        case .pocket: return "Pocket"
        case .ice: return "Ice"
        }
    }

    var colors: [UInt32] {
        let hex: [UInt32]
        switch self {
        case .mono:    hex = [0xF2F2F2, 0xA9A9A9, 0x585858, 0x101010]
        case .classic: hex = [0x9BBC0F, 0x8BAC0F, 0x306230, 0x0F380F]
        case .pocket:  hex = [0xC4CFA1, 0x8B956D, 0x4D533C, 0x1F1F1F]
        case .ice:     hex = [0xE8F4FA, 0x8EC5DC, 0x3F7A9B, 0x10263A]
        }
        return hex.map(DMGPalette.pack)
    }

    private static func pack(_ rgb: UInt32) -> UInt32 {
        let r = (rgb >> 16) & 0xFF
        let g = (rgb >> 8) & 0xFF
        let b = rgb & 0xFF
        return r | (g << 8) | (b << 16) | 0xFF00_0000
    }
}
