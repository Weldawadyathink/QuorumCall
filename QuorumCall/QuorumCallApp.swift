import SwiftUI
import SwiftData

// Owns all services and wires the hotkey callback to SwiftData lookups
final class QuorumCoordinator {
    let modelContainer: ModelContainer
    let windowManager: WindowManager
    let hotkeyManager: HotkeyManager
    private let modelContext: ModelContext

    init() {
        let schema = Schema([Quorum.self, QuorumWindow.self])
        let config = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)
        let container = try! ModelContainer(for: schema, configurations: [config])

        self.modelContainer = container
        self.modelContext = ModelContext(container)
        self.windowManager = WindowManager()
        self.hotkeyManager = HotkeyManager()

        // Wire hotkey → quorum activation
        hotkeyManager.onActivate = { [weak self] quorumID in
            self?.activateQuorum(id: quorumID)
        }

        // Register any previously saved shortcuts
        if let quorums = try? modelContext.fetch(FetchDescriptor<Quorum>()) {
            for quorum in quorums {
                hotkeyManager.register(quorum: quorum)
            }
        }

        WindowManager.requestAccessibilityIfNeeded()
    }

    private func activateQuorum(id: UUID) {
        let predicate = #Predicate<Quorum> { $0.id == id }
        guard let quorum = try? modelContext.fetch(FetchDescriptor(predicate: predicate)).first else { return }
        windowManager.activate(quorum: quorum)
    }
}

@main
struct QuorumCallApp: App {
    @State private var coordinator = QuorumCoordinator()

    var body: some Scene {
        MenuBarExtra("QuorumCall", systemImage: "rectangle.3.group") {
            MenuContentView()
                .environment(coordinator.windowManager)
                .environment(coordinator.hotkeyManager)
                .modelContainer(coordinator.modelContainer)
        }
        .menuBarExtraStyle(.menu)

        Window("Manage Quorums", id: "manage-quorums") {
            ManageQuorumsView()
                .environment(coordinator.hotkeyManager)
                .modelContainer(coordinator.modelContainer)
        }
        .windowResizability(.contentSize)
        .defaultSize(width: 700, height: 500)
    }
}
