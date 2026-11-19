# Monoboy

**A native Game Boy emulator for iOS, built entirely in Swift.**

*Monoboy aims to provide an accurate, lightweight, and intuitive Game Boy emulation experience on Apple devices — without requiring JIT compilation or additional memory entitlements.*

Features

* Native Swift implementation
* Game Boy (DMG) emulation
* No JIT compilation required
* No special memory entitlements required
* ROM importing through the Files app
* On-screen Game Boy controls
* Save states and persistent game saves
* Audio emulation
* Cartridge support

Features will be added as development progresses.

Compatibility

Platform	Support
iPhone	Planned
iPad	Planned
iOS / iPadOS	Planned
Game Boy (DMG)	Target

Architecture

Monoboy is designed around a modular emulator core, separate from its SwiftUI interface.

* CPU: Sharp LR35902 processor emulation
* Memory: Memory bus, cartridge mapping, and RAM
* PPU: Game Boy graphics and rendering
* Cartridge: ROM loading and cartridge banking
* Audio: Game Boy sound hardware emulation
* Input: Game Boy button mapping

Development

Monoboy is written in Swift and uses SwiftUI for its interface.

The project is designed for iPad-first development, with automated builds and testing through GitHub Actions.

Project Status

🚧 Early development

Monoboy is currently under development. Features, compatibility, and accuracy will improve over time.

License

Monoboy is licensed under the MIT License. See LICENSE for details.
