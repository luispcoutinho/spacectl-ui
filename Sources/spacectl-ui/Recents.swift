import AppKit
import Foundation

enum SidebarMode: String, CaseIterable, Identifiable {
    case search = "Search"
    case recent = "Recent"
    case trigger = "Trigger"   // only offered when actions are enabled
    var id: String { rawValue }
}

/// A stack the user opened before. Only the ID is kept: any state saved here would be stale on the next launch.
struct RecentStack: Codable, Identifiable, Equatable {
    let id: String
    var openedAt: Date

    private static let key = "recentStacks"
    static let limit = 30

    static func load() -> [RecentStack] {
        guard let data = UserDefaults.standard.data(forKey: key),
              let list = try? JSONDecoder().decode([RecentStack].self, from: data) else { return [] }
        return list
    }

    static func save(_ list: [RecentStack]) {
        if let data = try? JSONEncoder().encode(list) { UserDefaults.standard.set(data, forKey: key) }
    }
}

func relativeTime(_ date: Date) -> String {
    if Date().timeIntervalSince(date) < 60 { return "just now" }
    let f = RelativeDateTimeFormatter()
    f.unitsStyle = .full
    return f.localizedString(for: date, relativeTo: Date())
}

extension StacksViewModel {
    /// Newest first, deduplicated, capped.
    func recordRecent(_ id: String) {
        recents.removeAll { $0.id == id }
        recents.insert(RecentStack(id: id, openedAt: Date()), at: 0)
        if recents.count > RecentStack.limit { recents.removeLast(recents.count - RecentStack.limit) }
        RecentStack.save(recents)
    }

    func removeRecent(_ id: String) {
        recents.removeAll { $0.id == id }
        RecentStack.save(recents)
    }

    func clearRecents() {
        recents = []
        RecentStack.save(recents)
    }

    /// Back to the empty state; selecting nothing also cancels loads and stops any log stream.
    /// The Esc shortcut backs off while a text field or the log view has focus, so it never eats Esc meant for them.
    func closeStack(viaEscape: Bool = false) {
        guard selectedID != nil, !paletteOpen else { return }
        if viaEscape, NSApp.keyWindow?.firstResponder is NSText { return }
        selectedID = nil
    }
}
