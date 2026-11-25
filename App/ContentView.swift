import SwiftUI

struct ContentView: View {
    @StateObject private var vm = EmulatorViewModel()
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            if vm.isGameLoaded {
                GameView(vm: vm)
            } else {
                LibraryView(vm: vm)
            }
        }
        .preferredColorScheme(.dark)
        .onChange(of: scenePhase) { phase in
            vm.scenePhaseChanged(isActive: phase == .active)
        }
        .alert(
            "Monoboy",
            isPresented: Binding(
                get: { vm.errorMessage != nil },
                set: { if !$0 { vm.errorMessage = nil } }
            ),
            actions: { Button("OK", role: .cancel) {} },
            message: { Text(vm.errorMessage ?? "") }
        )
    }
}
