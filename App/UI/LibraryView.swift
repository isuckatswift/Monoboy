import SwiftUI
import UniformTypeIdentifiers

struct LibraryView: View {
    @ObservedObject var vm: EmulatorViewModel
    @State private var showImporter = false

    var body: some View {
        NavigationStack {
            Group {
                if vm.library.isEmpty {
                    VStack(spacing: 16) {
                        Image(systemName: "gamecontroller")
                            .font(.system(size: 56))
                            .foregroundColor(.secondary)
                        Text("No games yet")
                            .font(.title3.bold())
                        Text("Import your own .gb or .gbc ROM files.\nYou can also drop them into the Monoboy folder in the Files app.")
                            .font(.subheadline)
                            .multilineTextAlignment(.center)
                            .foregroundColor(.secondary)
                        Button("Import ROMs") { showImporter = true }
                            .buttonStyle(.borderedProminent)
                    }
                    .padding()
                } else {
                    List {
                        ForEach(vm.library, id: \.self) { url in
                            Button {
                                vm.load(url)
                            } label: {
                                Label(url.deletingPathExtension().lastPathComponent,
                                      systemImage: "gamecontroller")
                            }
                        }
                        .onDelete { vm.deleteROMs(at: $0) }
                    }
                }
            }
            .navigationTitle("Monoboy")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { showImporter = true } label: { Image(systemName: "plus") }
                }
            }
            .fileImporter(
                isPresented: $showImporter,
                allowedContentTypes: [.data],
                allowsMultipleSelection: true
            ) { result in
                if case .success(let urls) = result { vm.importROMs(urls) }
            }
            .onAppear { vm.refreshLibrary() }
        }
    }
}
