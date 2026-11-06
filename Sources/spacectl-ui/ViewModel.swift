import Foundation
import Observation

/// Load state for one piece of remote data.
enum Load<T> {
    case idle, loading, loaded(T), failed(String)

    var value: T? { if case .loaded(let v) = self { return v } else { return nil } }
    var isLoading: Bool { if case .loading = self { return true } else { return false } }
    var error: String? { if case .failed(let e) = self { return e } else { return nil } }
    var needsLoad: Bool {
        switch self { case .idle, .failed: return true; default: return false }
    }
}

enum DetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case history = "Run history"
    case logs = "Logs"
    case live = "Live logs"
    case outputs = "Outputs"
    case environment = "Environment"
    case everything = "Everything"
    var id: String { rawValue }
}

@Observable
@MainActor
final class StacksViewModel {
    // Search
    var query = ""
    var stacks: [Stack] = []
    var isSearching = false
    var searchError: String?

    // UI state (kept here rather than in @State: that macro plugin ships with Xcode only)
    var tab: DetailTab = .overview
    var outputFilter = ""
    var logPhase = ""
    var logRunID: String?          // chosen in Run history or the logs header; defaults to the latest run
    var autoscroll = true
    var runFilter: RunFilter = .all
    var detailsRunID: String?      // run whose details popover is open in Run history

    // Selection and per-stack data, each loaded on demand
    var selectedID: String?
    var stack: Load<Stack> = .idle
    var runs: Load<[Run]> = .idle
    var changes: [String: Load<[ChangeRow]>] = [:]   // by run ID: changes belong to a run
    var outputs: Load<[OutputRow]> = .idle
    var environment: Load<[EnvRow]> = .idle

    // Sidebar: search results or previously opened stacks (behaviour lives in Recents.swift)
    var sidebarMode: SidebarMode = .search
    var recents: [RecentStack] = RecentStack.load()

    // ⌘K command palette (behaviour lives in CommandPalette.swift)
    var paletteOpen = false
    var paletteQuery = ""
    var paletteIndex = 0
    var paletteStacks: [Stack] = []
    var paletteSearching = false
    var paletteTask: Task<Void, Never>?

    let logs = LogStreamer()
    let live = LogStreamer()

    private var searchTask: Task<Void, Never>?
    private var tasks: [Task<Void, Never>] = []

    var spacectlMissing: Bool { Spacectl.locate() == nil }
    /// The newest tracked run (what was actually deployed); proposed and drift runs never take its place.
    var latestRun: Run? { runs.value?.first { $0.kind == .tracked } ?? runs.value?.first }
    var effectiveRunID: String? { logRunID ?? latestRun?.id }

    // MARK: Search

    /// Debounced server-side search; a newer keystroke cancels the previous request's result.
    func queryChanged() {
        searchTask?.cancel()
        let q = query.trimmingCharacters(in: .whitespaces)
        guard q.count >= 2 else {
            stacks = []; searchError = nil; isSearching = false
            return
        }
        searchTask = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            isSearching = true
            defer { if !Task.isCancelled { isSearching = false } }
            do {
                let result = try await Spacectl.searchStacks(q)
                if Task.isCancelled { return }
                stacks = result; searchError = nil
            } catch {
                if Task.isCancelled { return }
                stacks = []; searchError = error.localizedDescription
            }
        }
    }

    // MARK: Selection

    func selectionChanged() {
        resetData()
        if let id = selectedID { recordRecent(id) }
        ensure(tab)
    }

    func refresh() {
        resetData()
        ensure(tab)
    }

    private func resetData() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        logs.stop(); live.stop()
        detailsRunID = nil
        stack = .idle; runs = .idle; changes = [:]; outputs = .idle; environment = .idle
        logRunID = nil
    }

    /// Fetch whatever the tab needs, once. Safe to call repeatedly (tab switches, appear events).
    func ensure(_ tab: DetailTab) {
        guard let id = selectedID else { return }
        // Every tab's header shows the live state, which also covers stacks opened from Recent.
        load(\.stack, id) { try await Spacectl.stackDetail(id: id) }
        switch tab {
        case .overview, .history, .logs, .live:
                           loadRuns(id)
        case .outputs:     loadOutputs(id)
        case .environment: loadEnvironment(id)
        case .everything:
            loadRuns(id); loadOutputs(id); loadEnvironment(id)
        }
    }

    private func loadRuns(_ id: String) { load(\.runs, id) { try await Spacectl.runs(stackID: id) } }
    private func loadOutputs(_ id: String) {
        load(\.outputs, id) { OutputFlattener.rows(from: try await Spacectl.outputs(stackID: id)) }
    }
    private func loadEnvironment(_ id: String) { load(\.environment, id) { try await Spacectl.environment(stackID: id) } }

    /// Changes of the selected run (the latest unless one is picked in Run history); cached per run.
    func changesState(for runID: String?) -> Load<[ChangeRow]> {
        guard let runID else { return .idle }
        return changes[runID] ?? .idle
    }

    func ensureChanges() {
        guard let id = selectedID, let runID = effectiveRunID, changes[runID]?.needsLoad ?? true else { return }
        changes[runID] = .loading
        let task = Task {
            do {
                let rows = try await Spacectl.changes(stackID: id, runID: runID)
                if Task.isCancelled || selectedID != id { return }
                changes[runID] = .loaded(rows)
            } catch {
                if Task.isCancelled || selectedID != id { return }
                changes[runID] = .failed(error.localizedDescription)
            }
        }
        tasks.append(task)
    }

    func showDetails(_ runID: String) {
        logRunID = runID
        detailsRunID = runID
    }

    /// Run history double-click: jump to that run's logs (or follow it live).
    func openLogs(_ runID: String, live: Bool = false) {
        logRunID = runID
        tab = live ? .live : .logs
    }

    private func load<T>(_ path: ReferenceWritableKeyPath<StacksViewModel, Load<T>>, _ id: String,
                         _ work: @escaping @MainActor () async throws -> T) {
        guard self[keyPath: path].needsLoad else { return }
        self[keyPath: path] = .loading
        let task = Task {
            do {
                let value = try await work()
                if Task.isCancelled || selectedID != id { return }
                self[keyPath: path] = .loaded(value)
            } catch {
                if Task.isCancelled || selectedID != id { return }
                self[keyPath: path] = .failed(error.localizedDescription)
            }
        }
        tasks.append(task)
    }

    // MARK: Logs

    func startLogs(_ streamer: LogStreamer, follow: Bool) {
        guard let id = selectedID, let runID = effectiveRunID else { return }
        streamer.start(stackID: id, runID: runID, phase: follow ? "" : logPhase, follow: follow)
    }
}
