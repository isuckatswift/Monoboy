import SwiftUI

struct ScreenView: View {
    @ObservedObject var screen: ScreenModel

    var body: some View {
        Group {
            if let image = screen.image {
                Image(decorative: image, scale: 1)
                    .interpolation(.none)
                    .resizable()
            } else {
                Color.black
            }
        }
        .aspectRatio(160.0 / 144.0, contentMode: .fit)
        .overlay(Rectangle().stroke(Color(white: 0.22), lineWidth: 2))
    }
}

struct GameView: View {
    @ObservedObject var vm: EmulatorViewModel

    var body: some View {
        GeometryReader { geo in
            let landscape = geo.size.width > geo.size.height
            VStack(spacing: 0) {
                topBar
                if landscape {
                    landscapeLayout(height: geo.size.height)
                } else {
                    portraitLayout(width: geo.size.width)
                }
            }
        }
    }

    // MARK: - Layouts

    private func portraitLayout(width: CGFloat) -> some View {
        let padSize = min(170, width * 0.42)
        return VStack(spacing: 0) {
            ScreenView(screen: vm.screen)
                .padding(.horizontal, 12)
                .overlay(pauseOverlay)
            Spacer(minLength: 12)
            HStack {
                DPadView(onButton: vm.press, size: padSize)
                Spacer()
                ActionButtonsView(onButton: vm.press, size: padSize)
            }
            .padding(.horizontal, 24)
            Spacer(minLength: 12)
            MenuButtonsView(onButton: vm.press)
                .padding(.bottom, 24)
        }
    }

    private func landscapeLayout(height: CGFloat) -> some View {
        let padSize = min(170, height * 0.45)
        return HStack(spacing: 0) {
            VStack {
                Spacer()
                DPadView(onButton: vm.press, size: padSize)
                Spacer()
                PressButton(label: "SELECT", button: .select, onButton: vm.press, diameter: 64, isPill: true)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)

            ScreenView(screen: vm.screen)
                .overlay(pauseOverlay)
                .layoutPriority(1)

            VStack {
                Spacer()
                ActionButtonsView(onButton: vm.press, size: padSize)
                Spacer()
                PressButton(label: "START", button: .start, onButton: vm.press, diameter: 64, isPill: true)
                    .padding(.bottom, 16)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.bottom, 8)
    }

    // MARK: - Pieces

    private var topBar: some View {
        HStack {
            Button { vm.unload() } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.title2)
                    .foregroundColor(Color(white: 0.6))
            }
            Spacer()
            Text(vm.currentTitle)
                .font(.footnote.weight(.semibold))
                .foregroundColor(Color(white: 0.6))
                .lineLimit(1)
            Spacer()
            Menu {
                Button(vm.isPaused ? "Resume" : "Pause") { vm.togglePause() }
                Button("Reset") { vm.reset() }
                Picker("Palette", selection: $vm.palette) {
                    ForEach(DMGPalette.allCases) { Text($0.name).tag($0) }
                }
            } label: {
                Image(systemName: "ellipsis.circle.fill")
                    .font(.title2)
                    .foregroundColor(Color(white: 0.6))
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var pauseOverlay: some View {
        if vm.isPaused {
            ZStack {
                Color.black.opacity(0.6)
                Image(systemName: "pause.fill")
                    .font(.system(size: 44))
                    .foregroundColor(.white)
            }
            .onTapGesture { vm.togglePause() }
        }
    }
}
