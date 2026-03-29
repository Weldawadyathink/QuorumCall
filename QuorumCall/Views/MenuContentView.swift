import SwiftUI
import SwiftData

struct MenuContentView: View {
    @Environment(WindowManager.self) private var windowManager
    @Environment(HotkeyManager.self) private var hotkeyManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Quorum.order) private var quorums: [Quorum]

    var body: some View {
        // Quorum activation list
        if quorums.isEmpty {
            Text("No Quorums yet")
                .foregroundStyle(.secondary)
        } else {
            ForEach(quorums) { quorum in
                Button {
                    windowManager.activate(quorum: quorum)
                } label: {
                    quorumLabel(quorum)
                }
            }
        }

        Divider()

        // Add window to quorum
        if let snapshot = windowManager.lastFrontmostSnapshot {
            Menu {
                ForEach(quorums) { quorum in
                    Button(quorum.name) {
                        addWindow(snapshot: snapshot, to: quorum)
                    }
                }
                if !quorums.isEmpty { Divider() }
                Button("New Quorum...") {
                    createNewQuorum(snapshot: snapshot)
                }
            } label: {
                let truncated = snapshot.windowTitle.count > 40
                    ? String(snapshot.windowTitle.prefix(40)) + "…"
                    : snapshot.windowTitle
                let label = truncated.isEmpty ? snapshot.appName : "\(snapshot.appName): \(truncated)"
                Text("Add \"\(label)\" to Quorum")
            }
        } else {
            Menu("Add Window to Quorum") {
                Text("Switch to a window first")
            }
            .disabled(true)
        }

        Button("Manage Quorums…") {
            NSApp.activate(ignoringOtherApps: true)
            openWindow(id: "manage-quorums")
        }

        Divider()

        Button("Quit QuorumCall") {
            NSApplication.shared.terminate(nil)
        }
    }

    @ViewBuilder
    private func quorumLabel(_ quorum: Quorum) -> some View {
        if let keyCode = quorum.shortcutKeyCode, let mods = quorum.shortcutModifiers {
            HStack {
                Text(quorum.name)
                Spacer()
                Text(HotkeyManager.displayString(keyCode: keyCode, modifiers: mods))
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(quorum.name)
        }
    }

    private func addWindow(snapshot: FocusedWindowSnapshot, to quorum: Quorum) {
        let isDuplicate = quorum.windows.contains {
            $0.appBundleID == snapshot.bundleID && $0.windowTitle == snapshot.windowTitle
        }
        guard !isDuplicate else { return }

        let win = QuorumWindow(
            appBundleID: snapshot.bundleID,
            appName: snapshot.appName,
            windowTitle: snapshot.windowTitle
        )
        win.quorum = quorum
        modelContext.insert(win)
        quorum.windows.append(win)
    }

    private func createNewQuorum(snapshot: FocusedWindowSnapshot? = nil) {
        let alert = NSAlert()
        alert.messageText = "New Quorum"
        alert.informativeText = "Enter a name for the new Quorum."
        alert.addButton(withTitle: "Create")
        alert.addButton(withTitle: "Cancel")

        let field = NSTextField(frame: NSRect(x: 0, y: 0, width: 240, height: 24))
        field.placeholderString = "e.g., Work: Backend"
        alert.accessoryView = field
        alert.window.initialFirstResponder = field

        guard alert.runModal() == .alertFirstButtonReturn else { return }

        let name = field.stringValue.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let count = (try? modelContext.fetchCount(FetchDescriptor<Quorum>())) ?? 0
        let quorum = Quorum(name: name, order: count)
        modelContext.insert(quorum)

        if let snapshot {
            addWindow(snapshot: snapshot, to: quorum)
        }
    }
}
