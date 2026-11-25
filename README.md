# Monoboy

A Game Boy (DMG) emulator for iPhone and iPad, written from scratch in Swift and SwiftUI. No third-party dependencies.

⚠️ Early version (v0.1). It runs many games, but there is no sound yet and accuracy is "good enough for most games", not cycle-perfect.

## Features

	•	Full LR35902 CPU instruction set (including the CB prefix, HALT bug and delayed EI)
	•	Scanline PPU: background, window, 8×8 and 8×16 sprites, DMG sprite priority
	•	Timer, joypad, OAM DMA and interrupts
	•	Cartridge mappers: ROM-only, MBC1, MBC2, MBC3 (no RTC), MBC5
	•	Battery-backed saves (.sav files, autosaved)
	•	Built-in ROM library with import from the Files app
	•	Multi-touch on-screen controls (slide the D-pad for diagonals) with haptics
	•	MFi / Xbox / PlayStation controller support
	•	Selectable palettes (Mono, Classic Green, Pocket, Ice)
	•	Portrait and landscape layouts on iPhone and iPad

## Requirements

	•	Xcode 14.1+ (Swift 5.7+)
	•	iOS / iPadOS 16.0+

$# Build

Option A: XcodeGen (recommended)

brew install xcodegen
xcodegen generate
open Monoboy.xcodeproj

Set your signing team and bundle identifier (com.example.monoboy in project.yml), then run on a device or simulator.

Option B: Manual Xcode project

	1.	Xcode → File → New → Project → iOS App (Interface: SwiftUI, Language: Swift), named Monoboy.
	2.	Delete the generated ContentView.swift and *App.swift.
	3.	Drag the Monoboy/ source folder (Core, UI, MonoboyApp.swift) into the project.
	4.	Set the deployment target to 16.0 and devices to iPhone + iPad.
	5.	In the target's Info tab add Application supports iTunes file sharing = YES and Supports opening documents in place = YES.
	6.	Set the Debug optimization level to -O (the emulator is far too slow at -Onone).

## Adding games

Monoboy ships no games and no BIOS. Use only ROMs you legally own (e.g. dumped from your own cartridges, or homebrew).

	•	Tap + in the library and pick .gb / .gbc files, or
	•	Connect the device to a Mac/PC or open the Files app and drop them in On My iPhone → Monoboy → ROMs.

Saves are stored next to it in Saves/.

## Controls

Input	Action
On-screen D-pad / controller D-pad / left stick	D-pad
A / B buttons	A / B
Controller Menu / Options	Start / Select
⋯ menu	Pause, reset, change palette

## Project layout

Monoboy/
├── MonoboyApp.swift          App entry point
├── Core/                     UI-independent emulator
│   ├── CPU.swift             LR35902 interpreter
│   ├── MMU.swift             Memory bus, I/O registers, OAM DMA
│   ├── PPU.swift             Scanline renderer + LCD timing
│   ├── Cartridge.swift       ROM/RAM + MBC1/2/3/5
│   ├── GBTimer.swift         DIV / TIMA / TMA / TAC
│   ├── Joypad.swift          Input register
│   ├── GameBoy.swift         Runs a frame
│   └── Palette.swift         DMG color palettes
└── UI/
    ├── EmulatorViewModel.swift  Display link, library, saves
    ├── ContentView.swift        Root view
    ├── LibraryView.swift        ROM list + importer
    ├── GameView.swift           Screen + layouts
    ├── ControlsView.swift       Touch controls
    └── ControllerManager.swift  GameController support


The Core folder has no UIKit/SwiftUI dependencies, so it can be reused in a Swift package, macOS app or test target.

## Testing accuracy

In Debug builds, bytes written to the serial port are printed to the Xcode console. That makes Blargg's cpu_instrs ROMs useful: they print "Passed" or the failing test via serial.

## Roadmap

	☐︎	Audio (APU) via AVAudioEngine
	☐︎	MBC3 real-time clock
	☐︎	Save states
	☐︎	Run emulation off the main thread
	☐︎	Game Boy Color support
	☐︎	Rebindable controls, screen filters
	☐︎	Unit tests against test ROMs (Blargg, Mooneye)

## Known limitations

	•	No audio
	•	PPU is scanline-based (no mid-scanline effects) and ignores VRAM/OAM access restrictions
	•	CPU is instruction-accurate, not cycle-accurate within an instruction
	•	Game Boy Color-only games are rejected

## Legal

Monoboy is an independent project and is not affiliated with or endorsed by Nintendo. "Game Boy" is a trademark of Nintendo. Do not use this software with ROMs you don't have the right to use.

## License

MIT, see LICENSE.
