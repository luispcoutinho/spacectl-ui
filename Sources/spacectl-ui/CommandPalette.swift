import SwiftUI
import AppKit

/// One row in the ⌘K palette: a tab to jump to, an action, or a stack to open.
struct PaletteItem: Identifiable {
    enum Kind { case tab(DetailTab), refresh, stack(Stack), stackID(String) }
    let id: String
    let title: String
    let subtitle: String
    let icon: String
    let badge: String
    let kind: Kind
}

extension StacksViewModel {
    func openPalette() {
        paletteQuery = ""; paletteIndex = 0; paletteStacks = []
        paletteOpen = true
    }

    func closePalette() {
        paletteTask?.cancel()
        paletteSearching = false
        paletteOpen = false
    }

    func togglePalette() { paletteOpen ? closePalette() : openPalette() }

    func movePalette(_ delta: Int) {
        let count = paletteItems.count
        guard count > 0 else { return }
        paletteIndex = (paletteIndex + delta + count) % count
    }

    func runSelectedPaletteItem() {
        let items = paletteItems
        guard items.indices.contains(paletteIndex) else { return }
        run(items[paletteIndex])
    }

    func run(_ item: PaletteItem) {
        closePalette()
        switch item.kind {
        case .tab(let t):
            tab = t
        case .refresh:
            refresh()
        case .stack(let s):
            // The stack may come from the palette's own search, so make sure the sidebar lists it.
            if !stacks.contains(where: { $0.id == s.id }) { stacks.insert(s, at: 0) }
            selectedID = s.id
        case .stackID(let id):
            selectedID = id
        }
    }

    /// Commands filter locally; stacks come from a debounced server search, like the sidebar.
    func paletteQueryChanged() {
        paletteIndex = 0
        paletteTask?.cancel()
        let q = paletteQuery.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else { paletteStacks = []; paletteSearching = false; return }
        paletteTask = Task {
            try? await Task.sleep(for: .milliseconds(300))
            if Task.isCancelled { return }
            paletteSearching = true
            defer { if !Task.isCancelled { paletteSearching = false } }
            if let result = try? await Spacectl.searchStacks(q, limit: 30), !Task.isCancelled {
                paletteStacks = result
            }
        }
    }

    var paletteItems: [PaletteItem] {
        let tokens = paletteQuery.lowercased().split(separator: " ").map(String.init)
        func matches(_ s: String) -> Bool { tokens.allSatisfy { s.lowercased().contains($0) } }

        var items: [PaletteItem] = []
        if selectedID != nil {
            for t in DetailTab.allCases where matches(t.rawValue) {
                items.append(PaletteItem(id: "tab-\(t.rawValue)", title: t.rawValue, subtitle: "Go to tab",
                                         icon: t.icon, badge: "Tab", kind: .tab(t)))
            }
            if matches("refresh reload") {
                items.append(PaletteItem(id: "refresh", title: "Refresh", subtitle: "Reload the selected stack",
                                         icon: "arrow.clockwise", badge: "Action", kind: .refresh))
            }
        }

        let q = paletteQuery.trimmingCharacters(in: .whitespaces)
        // Recently opened stacks come first, so an empty palette is a quick way back.
        var seen = Set<String>()
        for r in recents.filter({ matches($0.id) }).prefix(q.isEmpty ? 8 : 30) {
            seen.insert(r.id)
            items.append(PaletteItem(id: "recent-\(r.id)", title: r.id,
                                     subtitle: "Opened \(relativeTime(r.openedAt))",
                                     icon: "clock", badge: "Recent", kind: .stackID(r.id)))
        }
        let source = q.count >= 2 ? paletteStacks : stacks
        for s in source.filter({ matches($0.id) && !seen.contains($0.id) }).prefix(30) {
            items.append(PaletteItem(id: "stack-\(s.id)", title: s.id,
                                     subtitle: "\(prettyState(s.state)) · \(s.trackedCommit?.authorName ?? "-")",
                                     icon: "square.stack.3d.up", badge: "Stack", kind: .stack(s)))
        }
        return items
    }
}

struct CommandPalette: View {
    @Bindable var model: StacksViewModel

    var body: some View {
        let items = model.paletteItems
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
                PaletteField(
                    text: $model.paletteQuery,
                    placeholder: "Search stacks, jump to a tab…",
                    onMove: { model.movePalette($0) },
                    onSubmit: { model.runSelectedPaletteItem() },
                    onCancel: { model.closePalette() })
                    .frame(height: 26)
                if model.paletteSearching { ProgressView().controlSize(.small) }
                Text("esc").font(.caption.monospaced()).foregroundStyle(Theme.muted)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 5))
            }
            .padding(14)

            Divider().overlay(Theme.border)

            if items.isEmpty {
                Text(model.paletteSearching ? "Searching…" : "No matches")
                    .foregroundStyle(Theme.muted)
                    .frame(maxWidth: .infinity).padding(28)
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 2) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                                row(item, selected: index == model.paletteIndex)
                                    .id(item.id)
                                    .onTapGesture { model.run(item) }
                            }
                        }
                        .padding(6)
                    }
                    .frame(maxHeight: 360)
                    .onChange(of: model.paletteIndex) {
                        if items.indices.contains(model.paletteIndex) { proxy.scrollTo(items[model.paletteIndex].id) }
                    }
                }
            }

            Divider().overlay(Theme.border)
            HStack(spacing: 16) {
                hint("↑↓", "navigate"); hint("↵", "open"); hint("esc", "close")
                Spacer()
            }
            .padding(.horizontal, 14).padding(.vertical, 8)
        }
        .frame(width: 600)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 14))
        .overlay(RoundedRectangle(cornerRadius: 14).stroke(Color.white.opacity(0.12)))
        .shadow(color: .black.opacity(0.5), radius: 30, y: 12)
        .onChange(of: model.paletteQuery) { model.paletteQueryChanged() }
    }

    private func row(_ item: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Image(systemName: item.icon)
                .frame(width: 28, height: 28)
                .background(Theme.accent.opacity(selected ? 0.35 : 0.16), in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(selected ? .white : Theme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(item.title).lineLimit(1).truncationMode(.middle)
                Text(item.subtitle).font(.caption).foregroundStyle(Theme.muted)
            }
            Spacer()
            Text(item.badge).font(.caption).foregroundStyle(Theme.muted)
        }
        .padding(.horizontal, 8).padding(.vertical, 6)
        .background(selected ? Theme.accent.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 9))
        .contentShape(Rectangle())
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) {
            Text(key).font(.caption.monospaced())
                .padding(.horizontal, 5).padding(.vertical, 1)
                .background(Theme.card, in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.caption)
        }
        .foregroundStyle(Theme.muted)
    }
}

/// Text field that takes focus on appear and reports ↑ ↓ ↵ esc, which SwiftUI's TextField cannot intercept.
struct PaletteField: NSViewRepresentable {
    @Binding var text: String
    var placeholder: String
    var onMove: (Int) -> Void
    var onSubmit: () -> Void
    var onCancel: () -> Void

    func makeNSView(context: Context) -> NSTextField {
        let field = NSTextField()
        field.isBordered = false
        field.drawsBackground = false
        field.focusRingType = .none
        field.font = .systemFont(ofSize: 17)
        field.placeholderString = placeholder
        field.delegate = context.coordinator
        // The view is not in a window yet; grab focus on the next runloop turns.
        for delay in [0.0, 0.08] {
            DispatchQueue.main.asyncAfter(deadline: .now() + delay) { field.window?.makeFirstResponder(field) }
        }
        return field
    }

    func updateNSView(_ field: NSTextField, context: Context) {
        context.coordinator.parent = self
        if field.stringValue != text { field.stringValue = text }
    }

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, NSTextFieldDelegate {
        var parent: PaletteField
        init(_ parent: PaletteField) { self.parent = parent }

        func controlTextDidChange(_ notification: Notification) {
            if let field = notification.object as? NSTextField { parent.text = field.stringValue }
        }

        func control(_ control: NSControl, textView: NSTextView, doCommandBy selector: Selector) -> Bool {
            switch selector {
            case #selector(NSResponder.moveUp(_:)): parent.onMove(-1)
            case #selector(NSResponder.moveDown(_:)): parent.onMove(1)
            case #selector(NSResponder.insertNewline(_:)): parent.onSubmit()
            case #selector(NSResponder.cancelOperation(_:)): parent.onCancel()
            default: return false
            }
            return true
        }
    }
}
