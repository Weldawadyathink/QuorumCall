import SwiftUI
import SwiftData

struct MenuContentView: View {
    @Environment(WindowManager.self) private var windowManager
    @Environment(HotkeyManager.self) private var hotkeyManager
    @Environment(\.modelContext) private var modelContext
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Quorum.order) private var quorums: [Quorum]

    var body: some View {
        VStack(spacing: 0) {
            if quorums.isEmpty {
                Text("No Quorums yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, 16)
                    .padding(.vertical, 8)
            } else {
                ForEach(quorums) { quorum in
                    QuorumRowView(
                        quorum: quorum,
                        snapshot: windowManager.lastFrontmostSnapshot,
                        onActivate: { windowManager.activate(quorum: quorum) },
                        onAddWindow: { snapshot in addWindow(snapshot: snapshot, to: quorum) }
                    )
                }
            }

            Divider()
                .padding(.vertical, 4)

            MenuActionButton("New Quorum…") {
                createNewQuorum()
            }
            MenuActionButton("Manage Quorums…") {
                NSApp.activate(ignoringOtherApps: true)
                openWindow(id: "manage-quorums")
            }

            Divider()
                .padding(.vertical, 4)

            MenuActionButton("Quit QuorumCall") {
                NSApplication.shared.terminate(nil)
            }
        }
        .padding(.vertical, 4)
        .frame(width: 260)
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

    private func createNewQuorum() {
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
    }
}

private struct QuorumRowView: View {
    let quorum: Quorum
    let snapshot: FocusedWindowSnapshot?
    let onActivate: () -> Void
    let onAddWindow: (FocusedWindowSnapshot) -> Void

    @State private var rowHovered = false
    @State private var plusHovered = false

    private var textColor: Color { rowHovered ? .white : .primary }
    private var secondaryTextColor: Color { rowHovered ? Color.white.opacity(0.7) : .secondary }

    var body: some View {
        HStack(spacing: 0) {
            Button(action: onActivate) {
                HStack {
                    Text(quorum.name)
                        .foregroundStyle(textColor)
                    Spacer()
                    if let keyCode = quorum.shortcutKeyCode, let mods = quorum.shortcutModifiers {
                        Text(HotkeyManager.displayString(keyCode: keyCode, modifiers: mods))
                            .foregroundStyle(secondaryTextColor)
                            .font(.caption)
                    }
                }
                .contentShape(Rectangle())
                .frame(maxWidth: .infinity)
                .padding(.leading, 12)
                .padding(.trailing, 6)
                .padding(.vertical, 6)
            }
            .buttonStyle(.plain)

            Button {
                if let snapshot { onAddWindow(snapshot) }
            } label: {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(snapshot != nil ? textColor : secondaryTextColor.opacity(0.5))
                    .frame(width: 28, height: 28)
                    .background(plusHovered && snapshot != nil ? Color.white.opacity(0.15) : Color.clear)
                    .clipShape(RoundedRectangle(cornerRadius: 4))
            }
            .buttonStyle(.plain)
            .disabled(snapshot == nil)
            .onHover { plusHovered = $0 }
            .padding(.trailing, 6)
            .help(snapshot != nil
                  ? "Add \"\(snapshot!.appName)\" to \(quorum.name)"
                  : "Switch to a window first")
        }
        .background(rowHovered ? Color.accentColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { rowHovered = $0 }
        .padding(.horizontal, 4)
    }
}

private struct MenuActionButton: View {
    let title: String
    let action: () -> Void
    @State private var isHovered = false

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .foregroundStyle(isHovered ? .white : .primary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
        }
        .buttonStyle(.plain)
        .background(isHovered ? Color.accentColor : Color.clear)
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .onHover { isHovered = $0 }
        .padding(.horizontal, 4)
    }
}
