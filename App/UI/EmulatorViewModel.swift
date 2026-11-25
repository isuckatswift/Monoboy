import SwiftUI
import QuartzCore
import CoreGraphics

/// Separate from the main view model so only the screen redraws at 60 fps.
final class ScreenModel: ObservableObject {
    @Published var image: CGImage?
}

/// CADisplayLink needs an NSObject target.
final class FrameTicker: NSObject {
    var onTick: (() -> Void)?
    @objc func tick() { onTick?() }
}

/// Owns the running GameBoy, the display link, ROM library and save files.
/// Everything here runs on the main thread.
final class EmulatorViewModel: ObservableObject {
    let screen = ScreenModel()

    @Published var library: [URL] = []
    @Published var isGameLoaded = false
    @Published var isPaused = false
    @Published var currentTitle = ""
    @Published var errorMessage: String?
    @Published var palette: DMGPalette {
        didSet {
            UserDefaults.standard.set(palette.rawValue, forKey: "monoboy.palette")
            gameBoy?.mmu.ppu.palette = palette.colors
        }
    }

    private var gameBoy: GameBoy?
    private var romURL: URL?
    private var displayLink: CADisplayLink?
    private let ticker = FrameTicker()
    private let controllers = ControllerManager()
    private var frameCount = 0

    private let fileManager = FileManager.default

    private var documents: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var romsDirectory: URL { documents.appendingPathComponent("ROMs", isDirectory: true) }
    private var savesDirectory: URL { documents.appendingPathComponent("Saves", isDirectory: true) }

    init() {
        let saved = UserDefaults.standard.integer(forKey: "monoboy.palette")
        palette = DMGPalette(rawValue: saved) ?? .mono

        ticker.onTick = { [weak self] in self?.runFrame() }
        controllers.onButton = { [weak self] button, pressed in self?.press(button, pressed: pressed) }

        try? fileManager.createDirectory(at: romsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: savesDirectory, withIntermediateDirectories: true)
        refreshLibrary()
    }

    // MARK: - Library

    func refreshLibrary() {
        let files = (try? fileManager.contentsOfDirectory(
            at: romsDirectory, includingPropertiesForKeys: nil)) ?? []
        library = files
            .filter { ["gb", "gbc"].contains($0.pathExtension.lowercased()) }
            .sorted { $0.lastPathComponent.localizedCaseInsensitiveCompare($1.lastPathComponent) == .orderedAscending }
    }

    func importROMs(_ urls: [URL]) {
        for url in urls {
            let scoped = url.startAccessingSecurityScopedResource()
            defer { if scoped { url.stopAccessingSecurityScopedResource() } }

            guard ["gb", "gbc"].contains(url.pathExtension.lowercased()) else {
                errorMessage = "“\(url.lastPathComponent)” isn’t a .gb or .gbc file."
                continue
            }
            do {
                let destination = romsDirectory.appendingPathComponent(url.lastPathComponent)
                if fileManager.fileExists(atPath: destination.path) {
                    try fileManager.removeItem(at: destination)
                }
                try fileManager.copyItem(at: url, to: destination)
            } catch {
                errorMessage = error.localizedDescription
            }
        }
        refreshLibrary()
    }

    func deleteROMs(at offsets: IndexSet) {
        for index in offsets {
            try? fileManager.removeItem(at: library[index])
        }
        refreshLibrary()
    }

    // MARK: - Game lifecycle

    func load(_ url: URL) {
        unload()
        do {
            let data = try Data(contentsOf: url)
            let cartridge = try Cartridge(rom: [UInt8](data))
            if cartridge.hasBattery, let saved = try? Data(contentsOf: savePath(for: url)) {
                cartridge.loadRAM([UInt8](saved))
            }
            let gb = GameBoy(cartridge: cartridge)
            gb.mmu.ppu.palette = palette.colors

            gameBoy = gb
            romURL = url
            currentTitle = url.deletingPathExtension().lastPathComponent
            isPaused = false
            isGameLoaded = true
            startLoop()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func unload() {
        stopLoop()
        saveRAM()
        gameBoy = nil
        romURL = nil
        isGameLoaded = false
        isPaused = false
        screen.image = nil
    }

    func reset() {
        if let url = romURL { load(url) }
    }

    func togglePause() {
        isPaused.toggle()
        if isPaused {
            stopLoop()
            saveRAM()
        } else {
            startLoop()
        }
    }

    func scenePhaseChanged(isActive: Bool) {
        if !isActive {
            saveRAM()
            stopLoop()
        } else if isGameLoaded && !isPaused {
            startLoop()
        }
    }

    func press(_ button: GBButton, pressed: Bool) {
        gameBoy?.mmu.joypad.set(button, pressed: pressed)
    }

    // MARK: - Loop

    private func startLoop() {
        stopLoop()
        let link = CADisplayLink(target: ticker, selector: #selector(FrameTicker.tick))
        link.preferredFrameRateRange = CAFrameRateRange(minimum: 30, maximum: 60, preferred: 60)
        link.add(to: .main, forMode: .common)
        displayLink = link
        UIApplication.shared.isIdleTimerDisabled = true
    }

    private func stopLoop() {
        displayLink?.invalidate()
        displayLink = nil
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func runFrame() {
        guard let gb = gameBoy else { return }
        gb.runFrame()
        screen.image = makeImage(from: gb.mmu.ppu.framebuffer)
        frameCount += 1
        if frameCount % 300 == 0 { saveRAM() }
    }

    private func makeImage(from pixels: [UInt32]) -> CGImage? {
        let data = pixels.withUnsafeBytes { Data($0) }
        guard let provider = CGDataProvider(data: data as CFData) else { return nil }
        return CGImage(
            width: PPU.screenWidth,
            height: PPU.screenHeight,
            bitsPerComponent: 8,
            bitsPerPixel: 32,
            bytesPerRow: PPU.screenWidth * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGBitmapInfo(rawValue: CGImageAlphaInfo.noneSkipLast.rawValue),
            provider: provider,
            decode: nil,
            shouldInterpolate: false,
            intent: .defaultIntent
        )
    }

    // MARK: - Saves

    private func savePath(for rom: URL) -> URL {
        savesDirectory.appendingPathComponent(rom.deletingPathExtension().lastPathComponent + ".sav")
    }

    private func saveRAM() {
        guard let gb = gameBoy, let url = romURL,
              gb.cartridge.hasBattery, gb.cartridge.ramDirty else { return }
        do {
            try Data(gb.cartridge.ram).write(to: savePath(for: url), options: .atomic)
            gb.cartridge.ramDirty = false
        } catch {
            errorMessage = "Couldn’t save game data: \(error.localizedDescription)"
        }
    }
}
