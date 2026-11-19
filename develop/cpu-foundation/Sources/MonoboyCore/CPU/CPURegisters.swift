
public struct CPURegisters: Equatable, Sendable {
    public enum Flag: UInt8, Sendable {
        case zero = 0x80
        case subtract = 0x40
        case halfCarry = 0x20
        case carry = 0x10
    }

    public var a: UInt8
    public var f: UInt8 {
        didSet {
            f &= 0xF0
        }
    }

    public var b: UInt8
    public var c: UInt8
    public var d: UInt8
    public var e: UInt8
    public var h: UInt8
    public var l: UInt8

    public var sp: UInt16
    public var pc: UInt16

    public init(
        a: UInt8 = 0,
        f: UInt8 = 0,
        b: UInt8 = 0,
        c: UInt8 = 0,
        d: UInt8 = 0,
        e: UInt8 = 0,
        h: UInt8 = 0,
        l: UInt8 = 0,
        sp: UInt16 = 0,
        pc: UInt16 = 0
    ) {
        self.a = a
        self.f = f & 0xF0
        self.b = b
        self.c = c
        self.d = d
        self.e = e
        self.h = h
        self.l = l
        self.sp = sp
        self.pc = pc
    }

    public var af: UInt16 {
        get {
            (UInt16(a) << 8) | UInt16(f)
        }
        set {
            a = UInt8(newValue >> 8)
            f = UInt8(newValue & 0xF0)
        }
    }

    public var bc: UInt16 {
        get {
            (UInt16(b) << 8) | UInt16(c)
        }
        set {
            b = UInt8(newValue >> 8)
            c = UInt8(newValue & 0xFF)
        }
    }

    public var de: UInt16 {
        get {
            (UInt16(d) << 8) | UInt16(e)
        }
        set {
            d = UInt8(newValue >> 8)
            e = UInt8(newValue & 0xFF)
        }
    }

    public var hl: UInt16 {
        get {
            (UInt16(h) << 8) | UInt16(l)
        }
        set {
            h = UInt8(newValue >> 8)
            l = UInt8(newValue & 0xFF)
        }
    }

    public func flagIsSet(_ flag: Flag) -> Bool {
        (f & flag.rawValue) != 0
    }

    public mutating func setFlag(_ flag: Flag, to enabled: Bool) {
        if enabled {
            f |= flag.rawValue
        } else {
            f &= ~flag.rawValue
        }

        f &= 0xF0
    }

    public mutating func clearFlags() {
        f = 0
    }

    public mutating func reset() {
        self = CPURegisters()
    }

    public mutating func resetToDMGPostBootState() {
        af = 0x01B0
        bc = 0x0013
        de = 0x00D8
        hl = 0x014D
        sp = 0xFFFE
        pc = 0x0100
    }
}
