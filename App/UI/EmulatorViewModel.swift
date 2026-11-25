import SwiftUI
import CoreGraphics

/// Separate from the main view model so only the screen redraws every frame.
final class ScreenModel: ObservableObject {
    @Published var image: CGImage?
}

/// Threading model
/// ---------------
/// - The view model itself (all @Published state, library, UI actions) lives on the main thread.
/// - The emulator (`gameBoy`, save files, the frame timer) is touched ONLY on `emuQueue`,
///   a dedicated serial queue. Input, palette changes and pause/resume are forwarded to it.
/// - Finished frames are converted to a CGImage on `emuQueue` and handed to the main
///   thread for display. If the UI hasn't drawn the previous frame yet, the new one is dropped.
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
            let colors = palette.colors
            emuQueue.async { [weak self] in self?.gameBoy?.mmu.ppu.palette = colors }
        }
    }

    // MARK: Main-thread state
    private var currentURL: URL?
    private let controllers = ControllerManager()
    private let fileManager = FileManager.default

    // MARK: Emulation-queue state (never touch from other threads)
    private let emuQueue = DispatchQueue(label: "com.monoboy.emulation", qos: .userInteractive)
    private var gameBoy: GameBoy?
    private var romURL: URL?
    private var frameTimer: DispatchSourceTimer?
    private var frameCount = 0

    // MARK: Frame hand-off
    private let publishLock = NSLock()
    private var frameInFlight = false

    /// Game Boy refresh rate: 4194304 Hz / 70224 cycles = 59.7275 fps.
    private static let framePeriodNanoseconds = 16_742_706

    private var documents: URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask)[0]
    }
    private var romsDirectory: URL { documents.appendingPathComponent("ROMs", isDirectory: true) }
    private var savesDirectory: URL { documents.appendingPathComponent("Saves", isDirectory: true) }

    init() {
        let saved = UserDefaults.standard.integer(forKey: "monoboy.palette")
        palette = DMGPalette(rawValue: saved) ?? .mono

        controllers.onButton = { [weak self] button, pressed in self?.press(button, pressed: pressed) }

        try? fileManager.createDirectory(at: romsDirectory, withIntermediateDirectories: true)
        try? fileManager.createDirectory(at: savesDirectory, withIntermediateDirectories: true)
        refreshLibrary()
    }

    // MARK: - Library (main thread)

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
                // Copy to a temporary file first so an existing ROM is never lost if the copy fails.
                let temporary = romsDirectory.appendingPathComponent(".import-\(UUID().uuidString)")
                try fileManager.copyItem(at: url, to: temporary)
                if fileManager.fileExists(atPath: destination.path) {
                    _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
                } else {
                    try fileManager.moveItem(at: temporary, to: destination)
                }
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

    // MARK: - Game lifecycle (called on main, work happens on emuQueue)

    func load(_ url: URL) {
        currentURL = url
        errorMessage = nil
        let title = url.deletingPathExtension().lastPathComponent
        let colors = palette.colors
        let savePath = savePath(for: url)

        emuQueue.async { [weak self] in
            guard let self else { return }
            self.stopTimer()
            self.saveRAM()   // flush the previous game, if any

            do {
                // File reading and ROM parsing happen off the main thread.
                let data = try Data(contentsOf: url)
                let cartridge = try Cartridge(rom: [UInt8](data))
                if cartridge.hasBattery, let saved = try? Data(contentsOf: savePath) {
                    cartridge.loadRAM([UInt8](saved))
                }
                let gb = GameBoy(cartridge: cartridge)
                gb.mmu.ppu.palette = colors

                self.gameBoy = gb
                self.romURL = url
                self.frameCount = 0
                self.startTimer()

                DispatchQueue.main.async {
                    self.currentTitle = title
                    self.isPaused = false
                    self.isGameLoaded = true
                    UIApplication.shared.isIdleTimerDisabled = true
                }
            } catch {
                self.gameBoy = nil
                self.romURL = nil
                DispatchQueue.main.async {
                    self.currentURL = nil
                    self.errorMessage = error.localizedDescription
                }
            }
        }
    }

    func unload() {
        currentURL = nil
        isGameLoaded = false
        isPaused = false
        screen.image = nil
        UIApplication.shared.isIdleTimerDisabled = false

        emuQueue.async { [weak self] in
            guard let self else { return }
            self.stopTimer()
            self.saveRAM()
            self.gameBoy = nil
            self.romURL = nil
        }
    }

    func reset() {
        if let url = currentURL { load(url) }
    }

    func togglePause() {
        guard isGameLoaded else { return }
        isPaused.toggle()
        let paused = isPaused
        UIApplication.shared.isIdleTimerDisabled = !paused

        emuQueue.async { [weak self] in
            guard let self else { return }
            if paused {
                self.stopTimer()
                self.saveRAM()
            } else if self.gameBoy != nil {
                self.startTimer()
            }
        }
    }

    func scenePhaseChanged(isActive: Bool) {
        let shouldRun = isActive && isGameLoaded && !isPaused
        UIApplication.shared.isIdleTimerDisabled = shouldRun

        emuQueue.async { [weak self] in
            guard let self else { return }
            if shouldRun {
                if self.gameBoy != nil { self.startTimer() }
            } else if !isActive {
                self.stopTimer()
                self.saveRAM()
            }
        }
    }

    /// Safe to call from any thread; the joypad is only ever touched on `emuQueue`.
    func press(_ button: GBButton, pressed: Bool) {
        emuQueue.async { [weak self] in
            self?.gameBoy?.mmu.joypad.set(button, pressed: pressed)
        }
    }

    // MARK: - Emulation loop (emuQueue only)

    private func startTimer() {
        stopTimer()
        let timer = DispatchSource.makeTimerSource(flags: .strict, queue: emuQueue)
        timer.schedule(deadline: .now(),
                       repeating: .nanoseconds(EmulatorViewModel.framePeriodNanoseconds),
                       leeway: .microseconds(100))
        timer.setEventHandler { [weak self] in self?.emulateFrame() }
        timer.resume()
        frameTimer = timer
    }

    private func stopTimer() {
        frameTimer?.cancel()
        frameTimer = nil
    }

    private func emulateFrame() {
        guard let gb = gameBoy else { return }
        gb.runFrame()

        if let fault = gb.cpu.illegalOpcode {
            stopTimer()
            saveRAM()
            DispatchQueue.main.async { [weak self] in
                self?.isPaused = true
                self?.errorMessage = fault.localizedDescription
                UIApplication.shared.isIdleTimerDisabled = false
            }
            return
        }

        publish(makeImage(from: gb.mmu.ppu.framebuffer))

        frameCount += 1
        if frameCount % 300 == 0 { saveRAM() }
    }

    /// Hands a finished frame to the main thread. Drops the frame if the UI
    /// hasn't consumed the previous one, so the emulator never queues up UI work.
    private func publish(_ image: CGImage?) {
        publishLock.lock()
        if frameInFlight {
            publishLock.unlock()
            return
        }
        frameInFlight = true
        publishLock.unlock()

        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.publishLock.lock()
            self.frameInFlight = false
            self.publishLock.unlock()
            if self.isGameLoaded { self.screen.image = image }
        }
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

    // MARK: - Saves (emuQueue only)

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
            DispatchQueue.main.async { [weak self] in
                self?.errorMessage = "Couldn’t save game data: \(error.localizedDescription)"
            }
        }
    }
}
