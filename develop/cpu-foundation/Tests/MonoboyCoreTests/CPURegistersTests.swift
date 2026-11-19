
import XCTest
@testable import MonoboyCore

final class CPURegistersTests: XCTestCase {

    func testRegistersInitializeToZero() {
        let registers = CPURegisters()

        XCTAssertEqual(registers.af, 0)
        XCTAssertEqual(registers.bc, 0)
        XCTAssertEqual(registers.de, 0)
        XCTAssertEqual(registers.hl, 0)
        XCTAssertEqual(registers.sp, 0)
        XCTAssertEqual(registers.pc, 0)
    }

    func testRegisterPairAssignment() {
        var registers = CPURegisters()

        registers.af = 0x1230
        registers.bc = 0x4567
        registers.de = 0x89AB
        registers.hl = 0xCDEF

        XCTAssertEqual(registers.a, 0x12)
        XCTAssertEqual(registers.f, 0x30)
        XCTAssertEqual(registers.b, 0x45)
        XCTAssertEqual(registers.c, 0x67)
        XCTAssertEqual(registers.d, 0x89)
        XCTAssertEqual(registers.e, 0xAB)
        XCTAssertEqual(registers.h, 0xCD)
        XCTAssertEqual(registers.l, 0xEF)
    }

    func testFlagRegisterMasksLowerNibble() {
        var registers = CPURegisters(f: 0xFF)

        XCTAssertEqual(registers.f, 0xF0)

        registers.f = 0x0F

        XCTAssertEqual(registers.f, 0x00)
    }

    func testIndividualFlags() {
        var registers = CPURegisters()

        registers.setFlag(.zero, to: true)
        XCTAssertTrue(registers.flagIsSet(.zero))

        registers.setFlag(.subtract, to: true)
        XCTAssertTrue(registers.flagIsSet(.subtract))

        registers.setFlag(.halfCarry, to: true)
        XCTAssertTrue(registers.flagIsSet(.halfCarry))

        registers.setFlag(.carry, to: true)
        XCTAssertTrue(registers.flagIsSet(.carry))

        XCTAssertEqual(registers.f, 0xF0)
    }

    func testClearingFlags() {
        var registers = CPURegisters(f: 0xF0)

        registers.clearFlags()

        XCTAssertEqual(registers.f, 0x00)
    }

    func testDMGPostBootState() {
        var registers = CPURegisters()

        registers.resetToDMGPostBootState()

        XCTAssertEqual(registers.af, 0x01B0)
        XCTAssertEqual(registers.bc, 0x0013)
        XCTAssertEqual(registers.de, 0x00D8)
        XCTAssertEqual(registers.hl, 0x014D)
        XCTAssertEqual(registers.sp, 0xFFFE)
        XCTAssertEqual(registers.pc, 0x0100)
    }

    func testReset() {
        var registers = CPURegisters(
            a: 0xFF,
            f: 0xF0,
            b: 0xAA,
            c: 0xBB,
            sp: 0xFFFF,
            pc: 0x1234
        )

        registers.reset()

        XCTAssertEqual(registers, CPURegisters())
    }
}
