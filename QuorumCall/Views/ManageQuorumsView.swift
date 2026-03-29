import SwiftUI
import SwiftData

struct ManageQuorumsView: View {
    @Environment(HotkeyManager.self) private var hotkeyManager
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \Quorum.order) private var quorums: [Quorum]
    @State private var selection: Quorum?

    var body: some View {
        NavigationSplitView {
            List(quorums, selection: $selection) { quorum in
                Text(quorum.name)
                    .tag(quorum)
            }
            .navigationTitle("Quorums")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button { addQuorum() } label: {
                        Label("Add Quorum", systemImage: "plus")
                    }
                }
            }
            .onDeleteCommand {
                if let q = selection { deleteQuorum(q) }
            }
        } detail: {
            if let quorum = selection {
                QuorumDetailView(quorum: quorum, hotkeyManager: hotkeyManager)
                    .id(quorum.id)
            } else {
                ContentUnavailableView(
                    "No Quorum Selected",
                    systemImage: "rectangle.3.group",
                    description: Text("Select a Quorum from the list or create a new one.")
                )
            }
        }
        .frame(minWidth: 650, minHeight: 400)
        .onDisappear {
            NSApp.setActivationPolicy(.accessory)
        }
    }

    private func addQuorum() {
        let count = quorums.count
        let quorum = Quorum(name: "New Quorum \(count + 1)", order: count)
        modelContext.insert(quorum)
        selection = quorum
    }

    private func deleteQuorum(_ quorum: Quorum) {
        hotkeyManager.unregister(quorumID: quorum.id)
        if selection?.id == quorum.id { selection = nil }
        modelContext.delete(quorum)
    }
}

struct QuorumDetailView: View {
    @Bindable var quorum: Quorum
    var hotkeyManager: HotkeyManager

    @Environment(\.modelContext) private var modelContext
    @State private var isRecording = false
    @State private var localMonitor: Any?

    var body: some View {
        Form {
            Section("Name") {
                TextField("Quorum name", text: $quorum.name)
            }

            Section("Keyboard Shortcut") {
                HStack {
                    shortcutField
                    Spacer()
                    if isRecording {
                        Button("Cancel") { stopRecording() }
                    } else {
                        Button("Record Shortcut") { startRecording() }
                        if quorum.shortcutKeyCode != nil {
                            Button("Clear") { clearShortcut() }
                                .foregroundStyle(.red)
                        }
                    }
                }
                Text("Shortcuts must include at least one modifier key (⌃ ⌥ ⇧ ⌘).")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }

            Section("Windows") {
                if quorum.windows.isEmpty {
                    Text("No windows added yet. Focus a window and use the menu bar icon to add it.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(quorum.windows) { win in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(win.appName)
                                    .fontWeight(.medium)
                                if !win.windowTitle.isEmpty {
                                    Text(win.windowTitle)
                                        .foregroundStyle(.secondary)
                                        .font(.caption)
                                        .lineLimit(1)
                                }
                            }
                            Spacer()
                            Button("Remove") {
                                removeWindow(win)
                            }
                            .foregroundStyle(.red)
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .formStyle(.grouped)
        .navigationTitle(quorum.name)
        .onDisappear { stopRecording() }
    }

    @ViewBuilder
    private var shortcutField: some View {
        if isRecording {
            Text("Press shortcut keys…")
                .foregroundStyle(.blue)
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.blue.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
        } else if let keyCode = quorum.shortcutKeyCode, let mods = quorum.shortcutModifiers {
            Text(HotkeyManager.displayString(keyCode: keyCode, modifiers: mods))
                .font(.system(.body, design: .monospaced))
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Color.secondary.opacity(0.15), in: RoundedRectangle(cornerRadius: 6))
        } else {
            Text("None")
                .foregroundStyle(.secondary)
        }
    }

    private func startRecording() {
        isRecording = true
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            // Require at least one modifier to avoid capturing plain keys
            guard !event.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
                return event
            }
            let keyCode = Int(event.keyCode)
            let modifiers = HotkeyManager.carbonModifiers(from: event.modifierFlags)
            quorum.shortcutKeyCode = keyCode
            quorum.shortcutModifiers = modifiers
            hotkeyManager.register(quorum: quorum)
            stopRecording()
            return nil
        }
    }

    private func stopRecording() {
        isRecording = false
        if let monitor = localMonitor {
            NSEvent.removeMonitor(monitor)
            localMonitor = nil
        }
    }

    private func clearShortcut() {
        hotkeyManager.unregister(quorumID: quorum.id)
        quorum.shortcutKeyCode = nil
        quorum.shortcutModifiers = nil
    }

    private func removeWindow(_ win: QuorumWindow) {
        quorum.windows.removeAll { $0.id == win.id }
        modelContext.delete(win)
    }
}
