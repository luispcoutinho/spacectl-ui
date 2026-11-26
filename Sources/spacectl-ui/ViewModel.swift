import AppKit
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
    var environmentFilter = ""
    var logPhase = ""
    var logRunID: String?          // chosen in Run history or the logs header; defaults to the latest run
    var autoscroll = true
    var runFilter: RunFilter = .all
    var detailsRunID: String?      // run whose details popover is open in Run history
    var endpoint: String?          // base URL of the active Spacelift profile
    var workerPool: Load<WorkerPoolStatus> = .idle
    var workerPoolRefreshing = false
    var copiedStackLink = false
    var copiedRunLink = false
    @ObservationIgnored private var copyStackTask: Task<Void, Never>?
    @ObservationIgnored private var copyRunTask: Task<Void, Never>?
    @ObservationIgnored private var workerPoolTask: Task<Void, Never>?
    @ObservationIgnored private var workerPoolLoopTask: Task<Void, Never>?

    // Selection and per-stack data, each loaded on demand
    var selectedID: String?
    var stack: Load<Stack> = .idle
    var runs: Load<[Run]> = .idle
    var changes: [String: Load<[ChangeRow]>] = [:]   // by run ID: changes belong to a run
    var outputs: Load<[OutputRow]> = .idle
    var environment: Load<[EnvRow]> = .idle

    // Sidebar: search results, favorites or previously opened stacks (behaviour lives in Recents.swift)
    static let minSidebarWidth: CGFloat = 280
    static let maxSidebarWidth: CGFloat = 500
    static let defaultSidebarWidth: CGFloat = 340
    static let sidebarRailWidth: CGFloat = 52

    var sidebarMode: SidebarMode = .search
    var sidebarCollapsed = UserDefaults.standard.bool(forKey: "sidebarCollapsed") {
        didSet { UserDefaults.standard.set(sidebarCollapsed, forKey: "sidebarCollapsed") }
    }
    var sidebarWidth: CGFloat = {
        let saved = UserDefaults.standard.double(forKey: "sidebarWidth")
        return saved > 0 ? min(max(CGFloat(saved), minSidebarWidth), maxSidebarWidth) : defaultSidebarWidth
    }() {
        didSet { UserDefaults.standard.set(Double(sidebarWidth), forKey: "sidebarWidth") }
    }
    @ObservationIgnored var sidebarDragStartWidth: CGFloat?
    var favorites: [String] = FavoriteStacks.load()
    var recents: [RecentStack] = RecentStack.load()

    // Actions that change Spacelift state (behaviour lives in Trigger.swift). Off until the user opts in.
    var actionsEnabled = UserDefaults.standard.bool(forKey: "actionsEnabled") {
        didSet {
            UserDefaults.standard.set(actionsEnabled, forKey: "actionsEnabled")
            if !actionsEnabled { stopBatch(); if sidebarMode == .trigger { sidebarMode = .search } }
        }
    }
    var pendingAction: PendingAction?
    var actionBusy = false
    var actionError: String?
    var triggerSelection = Set<String>()
    var triggerBatch: [TriggerItem] = []
    var triggerRunning = false
    var triggerSheet = false
    var triggerAction: TriggerAction = .preview       // Preview plans only, so it is the default
    var triggerBatchAction: TriggerAction = .preview  // what the batch in progress is doing
    var triggerPhrase = ""
    @ObservationIgnored var triggerTask: Task<Void, Never>?

    // ⌘K command palette (behaviour lives in CommandPalette.swift)
    var paletteOpen = false
    var paletteQuery = ""
    var paletteIndex = 0
    var paletteStacks: [Stack] = []
    var paletteSearching = false
    var paletteTask: Task<Void, Never>?

    // Release update check (behaviour lives in Updates.swift)
    var availableUpdate: ReleaseUpdate?
    var checkingForUpdates = false
    var updateCheckFailed = false
    @ObservationIgnored var updateTask: Task<Void, Never>?
    @ObservationIgnored var updateLoopTask: Task<Void, Never>?

    let logs = LogStreamer()
    let live = LogStreamer()

    private var searchTask: Task<Void, Never>?
    private var tasks: [Task<Void, Never>] = []

    var spacectlMissing: Bool { Spacectl.locate() == nil }
    /// The newest tracked run (what was actually deployed); proposed and drift runs never take its place.
    var latestRun: Run? { runs.value?.first { $0.kind == .tracked } ?? runs.value?.first }
    var effectiveRunID: String? { logRunID ?? latestRun?.id }

    init() {
        Task { endpoint = await Spacectl.currentEndpoint() }
        refreshWorkerPool()
        startWorkerPoolLoop()
        checkForUpdates()
        startUpdateLoop()
    }

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
        refreshWorkerPool()
    }

    private func resetData() {
        tasks.forEach { $0.cancel() }
        tasks.removeAll()
        logs.clear(); live.clear()
        copyStackTask?.cancel(); copyRunTask?.cancel()
        copiedStackLink = false; copiedRunLink = false
        detailsRunID = nil
        stack = .idle; runs = .idle; changes = [:]; outputs = .idle; environment = .idle
        logRunID = nil
    }

    /// Fetch whatever the tab needs, once. Safe to call repeatedly (tab switches, appear events).
    func ensure(_ tab: DetailTab) {
        guard let id = selectedID else { return }
        // Every tab's header shows the live state, which also covers stacks opened from Recent.
        load(\.stack, id) { try await Spacectl.stackDetail(id: id) }
        if actionsEnabled { loadRuns(id) }   // the header's Trigger button needs to know whether the stack ever ran
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

    // MARK: Worker pool, links & logs

    private func startWorkerPoolLoop() {
        workerPoolLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(60))
                if Task.isCancelled { break }
                self?.refreshWorkerPool(silent: true)
            }
        }
    }

    func refreshWorkerPool(silent: Bool = false) {
        guard !spacectlMissing else {
            workerPool = .failed("spacectl not found")
            return
        }
        workerPoolTask?.cancel()
        if workerPool.value == nil {
            workerPool = .loading
        } else if !silent {
            workerPoolRefreshing = true
        }
        workerPoolTask = Task {
            defer { if !Task.isCancelled { workerPoolRefreshing = false } }
            do {
                let status = try await Spacectl.defaultWorkerPoolStatus()
                if Task.isCancelled { return }
                workerPool = .loaded(status)
            } catch {
                if Task.isCancelled { return }
                workerPool = .failed(error.localizedDescription)
            }
        }
    }

    func openWorkerPoolsPage() {
        Task {
            if endpoint == nil { endpoint = await Spacectl.currentEndpoint() }
            guard let endpoint, let url = URL(string: "\(endpoint)/worker-pools") else {
                actionError = "Could not determine the active Spacelift endpoint. Check `spacectl profile list`."
                return
            }
            NSWorkspace.shared.open(url)
        }
    }

    func copyStackLink(_ stackID: String) {
        Task {
            if endpoint == nil { endpoint = await Spacectl.currentEndpoint() }
            guard let endpoint else { return }
            copyToPasteboard("\(endpoint)/stack/\(stackID)")
            copiedStackLink = true
            copyStackTask?.cancel()
            copyStackTask = Task {
                try? await Task.sleep(for: .milliseconds(1200))
                if !Task.isCancelled { copiedStackLink = false }
            }
        }
    }

    func copyRunLink(_ runID: String?) {
        guard let stackID = selectedID, let runID else { return }
        Task {
            if endpoint == nil { endpoint = await Spacectl.currentEndpoint() }
            guard let endpoint else { return }
            copyToPasteboard("\(endpoint)/stack/\(stackID)/run/\(runID)")
            copiedRunLink = true
            copyRunTask?.cancel()
            copyRunTask = Task {
                try? await Task.sleep(for: .milliseconds(1200))
                if !Task.isCancelled { copiedRunLink = false }
            }
        }
    }

    private func copyToPasteboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func startLogs(_ streamer: LogStreamer, follow: Bool) {
        guard let id = selectedID, let runID = effectiveRunID else { return }
        streamer.start(stackID: id, runID: runID, phase: follow ? "" : logPhase, follow: follow)
    }

    func downloadLogs(_ streamer: LogStreamer, follow: Bool) {
        guard let stackID = selectedID, let runID = effectiveRunID, streamer.hasLogs else { return }
        let phaseSuffix = (!follow && !logPhase.isEmpty) ? "-\(logPhase.lowercased())" : ""
        let panel = NSSavePanel()
        panel.nameFieldStringValue = "\(stackID)-\(runID)\(phaseSuffix).log"
        panel.canCreateDirectories = true
        guard panel.runModal() == .OK, let url = panel.url else { return }
        do {
            try streamer.rawText.write(to: url, atomically: true, encoding: .utf8)
        } catch {
            actionError = error.localizedDescription
        }
    }
}
