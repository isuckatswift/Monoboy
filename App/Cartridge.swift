import Foundation

enum CartridgeError: LocalizedError {
    case tooSmall
    case colorOnly
    case unsupportedMapper(UInt8)

    var errorDescription: String? {
        switch self {
        case .tooSmall:
            return "This file is too small to be a Game Boy ROM."
        case .colorOnly:
            return "This game only runs on Game Boy Color, which Monoboy doesn't support yet."
        case .unsupportedMapper(let type):
            return String(format: "Unsupported cartridge type 0x%02X.", type)
        }
    }
}

/// ROM + external RAM + memory bank controller (MBC1, MBC2, MBC3, MBC5).
/// MBC3's real-time clock is not implemented.
final class Cartridge {
    enum Mapper { case none, mbc1, mbc2, mbc3, mbc5 }

    let rom: [UInt8]
    private(set) var ram: [UInt8]
    let mapper: Mapper
    let hasBattery: Bool
    let title: String

    /// Set whenever cartridge RAM changes; cleared after a save.
    var ramDirty = false

    private var ramEnabled = false
    private var romBank = 1
    private var ramBank = 0
    private var bank2 = 0          // MBC1 upper bank bits
    private var mode1 = false      // MBC1 banking mode
    private let romBankCount: Int

    init(rom: [UInt8]) throws {
        guard rom.count >= 0x150 else { throw CartridgeError.tooSmall }
        if rom[0x143] == 0xC0 { throw CartridgeError.colorOnly }

        let type = rom[0x147]
        let detected: Mapper
        switch type {
        case 0x00, 0x08, 0x09: detected = .none
        case 0x01...0x03:      detected = .mbc1
        case 0x05, 0x06:       detected = .mbc2
        case 0x0F...0x13:      detected = .mbc3
        case 0x19...0x1E:      detected = .mbc5
        default: throw CartridgeError.unsupportedMapper(type)
        }

        let batteryTypes: Set<UInt8> = [0x03, 0x06, 0x09, 0x0F, 0x10, 0x13, 0x1B, 0x1E]

        let ramSizes = [0, 2048, 8192, 32768, 131072, 65536]
        let ramCode = Int(rom[0x149])
        var ramSize = ramCode < ramSizes.count ? ramSizes[ramCode] : 0
        if detected == .mbc2 { ramSize = 512 }

        let nameBytes = rom[0x134..<0x143].prefix { $0 != 0 }
        let name = String(bytes: nameBytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces) ?? ""

        self.rom = rom
        self.mapper = detected
        self.hasBattery = batteryTypes.contains(type)
        self.ram = [UInt8](repeating: 0, count: ramSize)
        self.title = name.isEmpty ? "Untitled" : name
        self.romBankCount = max(2, rom.count / 0x4000)
        self.ramEnabled = (detected == .none)
    }

    // MARK: - Save data

    func loadRAM(_ data: [UInt8]) {
        let count = min(data.count, ram.count)
        guard count > 0 else { return }
        ram.replaceSubrange(0..<count, with: data[0..<count])
    }

    // MARK: - ROM access

    private var switchableBank: Int {
        switch mapper {
        case .none: return 1
        case .mbc1: return ((bank2 << 5) | romBank) % romBankCount
        default:    return romBank % romBankCount
        }
    }

    func readROM(_ addr: UInt16) -> UInt8 {
        let a = Int(addr)
        let bank: Int
        if a < 0x4000 {
            bank = (mapper == .mbc1 && mode1) ? (bank2 << 5) % romBankCount : 0
        } else {
            bank = switchableBank
        }
        let index = bank * 0x4000 + (a & 0x3FFF)
        return index < rom.count ? rom[index] : 0xFF
    }

    func writeROM(_ addr: UInt16, _ value: UInt8) {
        switch mapper {
        case .none:
            break
        case .mbc1:
            switch addr {
            case 0x0000...0x1FFF: ramEnabled = value & 0x0F == 0x0A
            case 0x2000...0x3FFF:
                romBank = Int(value & 0x1F)
                if romBank == 0 { romBank = 1 }
            case 0x4000...0x5FFF: bank2 = Int(value & 0x03)
            default: mode1 = value & 0x01 != 0
            }
        case .mbc2:
            if addr < 0x4000 {
                if addr & 0x0100 == 0 {
                    ramEnabled = value & 0x0F == 0x0A
                } else {
                    romBank = Int(value & 0x0F)
                    if romBank == 0 { romBank = 1 }
                }
            }
        case .mbc3:
            switch addr {
            case 0x0000...0x1FFF: ramEnabled = value & 0x0F == 0x0A
            case 0x2000...0x3FFF:
                romBank = Int(value & 0x7F)
                if romBank == 0 { romBank = 1 }
            case 0x4000...0x5FFF: ramBank = Int(value)
            default: break // RTC latch (unsupported)
            }
        case .mbc5:
            switch addr {
            case 0x0000...0x1FFF: ramEnabled = value & 0x0F == 0x0A
            case 0x2000...0x2FFF: romBank = (romBank & 0x100) | Int(value)
            case 0x3000...0x3FFF: romBank = (romBank & 0x0FF) | (Int(value & 1) << 8)
            case 0x4000...0x5FFF: ramBank = Int(value & 0x0F)
            default: break
            }
        }
    }

    // MARK: - RAM access

    private func ramIndex(_ addr: UInt16) -> Int? {
        guard ramEnabled, !ram.isEmpty else { return nil }
        let offset = Int(addr) & 0x1FFF
        switch mapper {
        case .none: return offset % ram.count
        case .mbc1: return ((mode1 ? bank2 : 0) * 0x2000 + offset) % ram.count
        case .mbc2: return Int(addr) & 0x1FF
        case .mbc3:
            guard ramBank <= 3 else { return nil } // RTC registers unsupported
            return (ramBank * 0x2000 + offset) % ram.count
        case .mbc5: return (ramBank * 0x2000 + offset) % ram.count
        }
    }

    func readRAM(_ addr: UInt16) -> UInt8 {
        guard let index = ramIndex(addr) else { return 0xFF }
        return mapper == .mbc2 ? (ram[index] | 0xF0) : ram[index]
    }

    func writeRAM(_ addr: UInt16, _ value: UInt8) {
        guard let index = ramIndex(addr) else { return }
        ram[index] = mapper == .mbc2 ? (value & 0x0F) : value
        ramDirty = true
    }
}
