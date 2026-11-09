import SwiftUI

// MARK: - Small shared pieces

/// Colored capsule with a status dot: "● Finished".
struct StateBadge: View {
    let state: String?

    var body: some View {
        let color = stateColor(state)
        HStack(spacing: 5) {
            Circle().fill(color).frame(width: 6, height: 6)
            Text(prettyState(state)).font(.caption.weight(.semibold))
        }
        .padding(.horizontal, 9).padding(.vertical, 3)
        .background(color.opacity(0.15), in: Capsule())
        .overlay(Capsule().stroke(color.opacity(0.3)))
        .foregroundStyle(color)
        .fixedSize()
    }
}

struct InfoGrid: View {
    let rows: [(String, String)]

    var body: some View {
        Grid(alignment: .topLeading, horizontalSpacing: 20, verticalSpacing: 8) {
            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                GridRow {
                    Text(row.0).foregroundStyle(Theme.muted).gridColumnAlignment(.leading)
                    Text(row.1.isEmpty ? "-" : row.1).textSelection(.enabled)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Spinner / error / content for a `Load`, so every tab handles the three states the same way.
struct LoadView<T, Content: View>: View {
    let state: Load<T>
    @ViewBuilder var content: (T) -> Content

    var body: some View {
        switch state {
        case .idle, .loading:
            ProgressView("Loading…").frame(maxWidth: .infinity, minHeight: 80)
        case .failed(let error):
            Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).padding()
        case .loaded(let value):
            content(value)
        }
    }
}

func yesNo(_ b: Bool?) -> String { b.map { $0 ? "yes" : "no" } ?? "-" }

// MARK: - Root

struct ContentView: View {
    // Held by the app (not @State): the @State macro plugin ships with Xcode only, not Command Line Tools.
    var model: StacksViewModel

    var body: some View {
        NavigationSplitView {
            StackListView(model: model)
                .navigationSplitViewColumnWidth(min: 300, ideal: 380)
        } detail: {
            if let id = model.selectedID {
                StackDetailView(model: model, stackID: id)
            } else {
                ContentUnavailableView("Select a stack", systemImage: "square.stack.3d.up",
                                       description: Text("Search on the left, or press ⌘K to jump to a stack."))
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(Theme.bg)
            }
        }
        .frame(minWidth: 1200, minHeight: 650)
        .preferredColorScheme(.dark)
        .tint(Theme.accent)
        .groupBoxStyle(CardStyle())
        .overlay {
            if model.paletteOpen {
                ZStack(alignment: .top) {
                    Color.black.opacity(0.5).ignoresSafeArea().onTapGesture { model.closePalette() }
                    CommandPalette(model: model).padding(.top, 90)
                }
                .transition(.opacity)
            }
        }
        .animation(.easeOut(duration: 0.12), value: model.paletteOpen)
        .sheet(isPresented: Binding(get: { model.triggerSheet }, set: { model.triggerSheet = $0 })) {
            TriggerConfirmSheet(model: model)
        }
        .alert(pendingTitle, isPresented: Binding(get: { model.pendingAction != nil },
                                                  set: { if !$0 { model.pendingAction = nil } })) {
            Button("Cancel", role: .cancel) {}
            Button(pendingButton) { model.confirmPending() }
        } message: {
            Text(pendingMessage)
        }
        .alert("Action failed", isPresented: Binding(get: { model.actionError != nil },
                                                    set: { if !$0 { model.actionError = nil } })) {
            Button("OK") {}
        } message: {
            Text(model.actionError ?? "")
        }
    }

    private var pendingTitle: String {
        switch model.pendingAction {
        case .trigger: return "Trigger this stack?"
        case .retry: return "Retry this failed run?"
        case nil: return ""
        }
    }

    private var pendingButton: String {
        if case .retry = model.pendingAction { return "Retry" }
        return "Trigger"
    }

    private var pendingMessage: String {
        switch model.pendingAction {
        case .trigger(let id, let autodeploy):
            return "\(id)\n\nStarts its first run (spacectl stack deploy) at the branch head."
                + (autodeploy ? "\n\nAutodeploy is on, so the run will apply immediately." : "\nThe run waits for a person to confirm it.")
        case .retry(let id, let runID):
            return "\(id)\n\nRetries run \(runID) (spacectl stack retry)."
        case nil:
            return ""
        }
    }
}

// MARK: - Sidebar

struct StackListView: View {
    @Bindable var model: StacksViewModel

    var body: some View {
        VStack(spacing: 0) {
            VStack(spacing: 10) {
                Picker("", selection: $model.sidebarMode) {
                    ForEach(SidebarMode.allCases.filter { $0 != .trigger || model.actionsEnabled }) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                if (model.sidebarMode == .search || model.sidebarMode == .trigger) && model.triggerBatch.isEmpty { searchField }
            }
            .padding(12)

            switch model.sidebarMode {
            case .search: searchList
            case .favorites: favoritesList
            case .recent: recentList
            case .trigger: TriggerListView(model: model)
            }

            footer
        }
        .background(Theme.sidebar)
        .onChange(of: model.query) { model.queryChanged() }
        .onChange(of: model.selectedID) { model.selectionChanged() }
        .navigationTitle("Spacelift Stacks")
    }

    private var searchField: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(Theme.muted)
            TextField("Search stacks (min 2 characters)", text: $model.query).textFieldStyle(.plain)
            if !model.query.isEmpty {
                Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }
                    .buttonStyle(.plain).foregroundStyle(Theme.muted)
            }
        }
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(Theme.card, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.border))
    }

    private var favoritesList: some View {
        List(model.favorites, id: \.self, selection: $model.selectedID) { id in
            HStack(spacing: 10) {
                Image(systemName: "star.fill").font(.caption).foregroundStyle(.yellow).frame(width: 8)
                Text(id).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
            }
            .tag(id)
            .padding(.vertical, 3)
            .contextMenu { Button("Remove from favorites") { model.toggleFavorite(id) } }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
        .overlay {
            if model.favorites.isEmpty {
                ContentUnavailableView("No favorite stacks", systemImage: "star",
                                       description: Text("Star a stack in its header or right-click a stack in the sidebar."))
            }
        }
    }

    private var recentList: some View {
        List(model.recents, selection: $model.selectedID) { recent in
            HStack(spacing: 10) {
                Image(systemName: "clock").font(.caption).foregroundStyle(Theme.muted).frame(width: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(recent.id).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Text("Opened \(relativeTime(recent.openedAt))")
                        .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
                if model.isFavorite(recent.id) {
                    Spacer(minLength: 4)
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                }
            }
            .tag(recent.id)
            .padding(.vertical, 3)
            .contextMenu {
                Button(model.isFavorite(recent.id) ? "Remove from favorites" : "Add to favorites") {
                    model.toggleFavorite(recent.id)
                }
                Button("Remove from history") { model.removeRecent(recent.id) }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
        .overlay {
            if model.recents.isEmpty {
                ContentUnavailableView("No recent stacks", systemImage: "clock",
                                       description: Text("Stacks you open show up here."))
            }
        }
    }

    private var footer: some View {
        HStack {
            switch model.sidebarMode {
            case .search, .trigger:
                if model.isSearching { ProgressView().controlSize(.small) }
                Text(model.stacks.isEmpty ? "" : "\(model.stacks.count) stacks")
                    .font(.caption).foregroundStyle(Theme.muted)
            case .favorites:
                Text(model.favorites.isEmpty ? "" : "\(model.favorites.count) \(model.favorites.count == 1 ? "favorite" : "favorites")")
                    .font(.caption).foregroundStyle(Theme.muted)
            case .recent:
                Text(model.recents.isEmpty ? "" : "\(model.recents.count) recent")
                    .font(.caption).foregroundStyle(Theme.muted)
                if !model.recents.isEmpty {
                    Button("Clear history") { model.clearRecents() }
                        .buttonStyle(.plain).font(.caption).foregroundStyle(Theme.accent)
                }
            }
            Spacer()
            Button { model.togglePalette() } label: {
                HStack(spacing: 4) { Image(systemName: "command"); Text("K") }
                    .font(.caption.weight(.medium))
                    .padding(.horizontal, 7).padding(.vertical, 3)
                    .background(Theme.card, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6).stroke(Theme.border))
            }
            .buttonStyle(.plain).foregroundStyle(Theme.muted)
            .help("Command palette (⌘K)")
        }
        .padding(.horizontal, 12).padding(.vertical, 8)
        .background(Theme.sidebar)
    }

    private var searchList: some View {
        List(model.stacks, selection: $model.selectedID) { stack in
            HStack(spacing: 10) {
                Circle().fill(stateColor(stack.state)).frame(width: 8, height: 8)
                    .shadow(color: stateColor(stack.state).opacity(0.7), radius: 3)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stack.id).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Text("\(prettyState(stack.state)) · \(stack.trackedCommit?.authorName ?? "-")")
                        .font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
                if model.isFavorite(stack.id) {
                    Spacer(minLength: 4)
                    Image(systemName: "star.fill").font(.caption2).foregroundStyle(.yellow)
                }
            }
            .tag(stack.id)
            .padding(.vertical, 3)
            .contextMenu {
                Button(model.isFavorite(stack.id) ? "Remove from favorites" : "Add to favorites") {
                    model.toggleFavorite(stack.id)
                }
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(Theme.sidebar)
        .overlay { overlayContent }
    }

    @ViewBuilder private var overlayContent: some View {
        if model.spacectlMissing {
            ContentUnavailableView("spacectl not found", systemImage: "exclamationmark.triangle",
                                   description: Text(SpacectlError.notFound.localizedDescription))
        } else if let error = model.searchError {
            ContentUnavailableView("Search failed", systemImage: "xmark.octagon", description: Text(error))
        } else if model.stacks.isEmpty && !model.isSearching {
            if model.query.trimmingCharacters(in: .whitespaces).count < 2 {
                ContentUnavailableView("Search for stacks", systemImage: "magnifyingglass",
                                       description: Text("Type at least 2 characters. Listing every stack is too slow, so searching happens on the server."))
            } else {
                ContentUnavailableView.search(text: model.query)
            }
        }
    }
}

// MARK: - Detail container

struct StackDetailView: View {
    @Bindable var model: StacksViewModel
    let stackID: String

    private var currentState: String? {
        model.stack.value?.state ?? model.stacks.first { $0.id == stackID }?.state
    }

    private var subtitle: String {
        if let s = model.stack.value {
            return [s.repository, s.branch].compactMap { $0 }.joined(separator: " · ")
        }
        return model.stacks.first { $0.id == stackID }?.trackedCommit?.authorName ?? ""
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(stackID).font(.title3.weight(.semibold)).lineLimit(1).truncationMode(.middle)
                    .textSelection(.enabled)
                if !subtitle.isEmpty {
                    Text(subtitle).font(.caption).foregroundStyle(Theme.muted).lineLimit(1)
                }
            }
            StateBadge(state: currentState)
            Spacer()
            Button { model.toggleFavorite(stackID) } label: {
                Image(systemName: model.isFavorite(stackID) ? "star.fill" : "star")
                    .foregroundStyle(model.isFavorite(stackID) ? .yellow : .primary)
            }
            .buttonStyle(.bordered)
            .help(model.isFavorite(stackID) ? "Remove from favorites" : "Add to favorites")
            Button { model.closeStack() } label: { Image(systemName: "xmark") }
                .buttonStyle(.bordered)
                .help("Close stack (Esc)")
            if model.actionsEnabled {
                Button { model.requestTrigger() } label: { Label("Trigger", systemImage: "play.fill") }
                    .buttonStyle(.bordered)
                    .disabled(!model.canTriggerFirstRun)
                    .help(model.triggerButtonHelp)
            }
            Button { model.refresh() } label: { Label("Refresh", systemImage: "arrow.clockwise") }
                .keyboardShortcut("r", modifiers: .command)
                .buttonStyle(.bordered)
        }
        .padding(.horizontal, 20).padding(.top, 16).padding(.bottom, 12)
    }

    private var tabBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(DetailTab.allCases) { t in
                    let selected = model.tab == t
                    Button { model.tab = t } label: {
                        Label(t.rawValue, systemImage: t.icon)
                            .font(.callout.weight(selected ? .semibold : .regular))
                            .padding(.horizontal, 11).padding(.vertical, 6)
                            .background(selected ? Theme.accent.opacity(0.2) : .clear, in: RoundedRectangle(cornerRadius: 8))
                            .foregroundStyle(selected ? Theme.accent : Theme.muted)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, 16)
        }
        .padding(.bottom, 8)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            tabBar
            Divider().overlay(Theme.border)

            Group {
                switch model.tab {
                case .overview:    ScrollView { OverviewSections(model: model).padding(16) }
                case .history:     RunHistoryView(model: model)
                case .logs:        LogsPane(model: model, streamer: model.logs, follow: false)
                case .live:        LogsPane(model: model, streamer: model.live, follow: true)
                case .outputs:     OutputsSection(model: model, embedded: false)
                case .environment: EnvironmentSection(model: model, embedded: false)
                case .everything:  EverythingView(model: model)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .background(Theme.bg)
        .background {
            // Invisible: carries the Esc shortcut without adding a second visible button.
            Button("") { model.closeStack(viaEscape: true) }
                .keyboardShortcut(.escape, modifiers: [])
                .opacity(0).frame(width: 0, height: 0)
        }
        .navigationTitle("")
        .onAppear { model.ensure(model.tab) }
        .onChange(of: model.tab) { model.ensure(model.tab) }
    }
}

// MARK: - Overview (mirrors `spacectl stack show`)

struct OverviewSections: View {
    var model: StacksViewModel

    var body: some View {
        LoadView(state: model.stack) { s in
            VStack(alignment: .leading, spacing: 16) {
                LatestRunSection(model: model)
                GroupBox("Stack") {
                    InfoGrid(rows: [
                        ("Name", s.name),
                        ("State", s.state ?? "-"),
                        ("State set", formatTimestamp(s.stateSetAt)),
                        ("Description", s.description ?? ""),
                        ("Labels", (s.labels ?? []).map { "[\($0)]" }.joined(separator: " ")),
                    ])
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 420), spacing: 16, alignment: .top)], spacing: 16) {
                GroupBox("VCS settings") {
                    InfoGrid(rows: [
                        ("Provider", (s.provider ?? "-").replacingOccurrences(of: "_", with: " ").capitalized),
                        ("Repository", s.repository ?? "-"),
                        ("Branch", s.branch ?? "-"),
                        ("Commit", [s.trackedCommit?.hash.map { String($0.prefix(8)) }, s.trackedCommit?.authorName]
                            .compactMap { $0 }.joined(separator: " by ")),
                        ("Message", s.trackedCommit?.message ?? ""),
                    ])
                }
                GroupBox("Backend") {
                    InfoGrid(rows: [("Vendor", s.VendorConfig?.vendor ?? "-")]
                        + (s.VendorConfig?.settings ?? []).map { ($0.key, $0.value) }
                        + [("Managed state", yesNo(s.managesStateFile))])
                }
                GroupBox("Settings") {
                    InfoGrid(rows: [
                        ("Administrative", yesNo(s.administrative)),
                        ("Worker pool", s.workerPool.map { "\($0.name ?? "-") (\($0.id ?? "-"))" } ?? "public"),
                        ("Autodeploy", yesNo(s.autodeploy)),
                        ("Autoretry", yesNo(s.autoretry)),
                        ("Local preview enabled", yesNo(s.localPreviewEnabled)),
                        ("Project root", s.projectRoot ?? ""),
                        ("Additional project globs", (s.additionalProjectGlobs ?? []).joined(separator: ", ")),
                        ("Runner image", s.runnerImage ?? "default"),
                        ("Terraform version", s.terraformVersion ?? ""),
                    ])
                }
                GroupBox("Attached contexts") {
                    if let contexts = s.AttachedContexts, !contexts.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(contexts) { c in
                                DisclosureGroup("\(c.name ?? c.id)  (\((c.config ?? []).count) items)") {
                                    // Names only; Spacelift does not expose write-only values.
                                    VStack(alignment: .leading, spacing: 2) {
                                        ForEach(c.config ?? [], id: \.id) { item in
                                            Text("\(item.id)  ·  \((item.type ?? "").replacingOccurrences(of: "_", with: " ").lowercased())")
                                                .font(.caption.monospaced()).foregroundStyle(.secondary)
                                                .textSelection(.enabled)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.leading, 8)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("None").foregroundStyle(Theme.muted)
                    }
                }
                GroupBox("Attached policies") {
                    if let policies = s.AttachedPolicies, !policies.isEmpty {
                        Grid(alignment: .leading, horizontalSpacing: 24, verticalSpacing: 6) {
                            GridRow { Text("Name").bold(); Text("Type").bold() }
                            Divider()
                            ForEach(policies) { p in
                                GridRow {
                                    Text(p.name ?? p.id).textSelection(.enabled)
                                    Text((p.type ?? "-").replacingOccurrences(of: "_", with: " ").capitalized)
                                }
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    } else {
                        Text("None").foregroundStyle(Theme.muted)
                    }
                }
                }
            }
        }
    }
}

// MARK: - Latest run

struct RunInfoGrid: View {
    let run: Run

    var body: some View {
        InfoGrid(rows: [
            ("Run", run.id),
            ("Type", run.kind.rawValue),
            ("State", run.state + (run.isMostRecent == true ? " (most recent)" : "")),
            ("Triggered", "\(run.triggeredBy ?? "-") at \(formatTimestamp(run.createdAt))"),
            ("Title", run.title ?? "-"),
            ("Commit", [run.commit?.hash.map { String($0.prefix(8)) }, run.commit?.authorName]
                .compactMap { $0 }.joined(separator: " by ")),
            ("Approval", run.needsApproval == true ? "needed" : "not needed"),
        ])
    }
}

struct LatestRunSection: View {
    var model: StacksViewModel

    var body: some View {
        LoadView(state: model.runs) { runs in
            if let r = model.latestRun {
                GroupBox(r.kind == .tracked ? "Latest tracked run" : "Latest run") { RunInfoGrid(run: r) }
            } else {
                NoRunsView(model: model)
            }
        }
    }
}

// MARK: - Tables (shared by their own tab and by Everything)

private func tableHeight(_ rows: Int, embedded: Bool) -> CGFloat? {
    embedded ? CGFloat(min(max(rows, 1), 12)) * 26 + 34 : nil
}

struct ChangesSection: View {
    var model: StacksViewModel
    let embedded: Bool

    var body: some View {
        LoadView(state: model.changesState(for: model.effectiveRunID)) { rows in
            if rows.isEmpty {
                ContentUnavailableView("No resource changes for this run", systemImage: "checkmark.circle")
            } else {
                Table(rows) {
                    TableColumn("Change", value: \.type).width(min: 60, ideal: 80)
                    TableColumn("Resource") { Text($0.address).textSelection(.enabled) }
                    TableColumn("Previous address", value: \.previous).width(min: 80, ideal: 160)
                }
                .frame(height: tableHeight(rows.count, embedded: embedded))
                .tableSurface(embedded: embedded)
            }
        }
        .task(id: model.effectiveRunID) { model.ensureChanges() }
    }
}

/// Run list on top, the selected run's changes below: changes always say which run they belong to.
struct RunHistoryView: View {
    @Bindable var model: StacksViewModel

    var body: some View {
        VSplitView {
            HistorySection(model: model, embedded: false)
                .frame(minHeight: 160)
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 8) {
                    Text("Changes").font(.headline)
                    if let id = model.effectiveRunID {
                        Text("· run \(id)").font(.callout.monospaced()).foregroundStyle(Theme.muted)
                    }
                    Spacer()
                }
                .padding(.horizontal, 16).padding(.vertical, 8)
                ChangesSection(model: model, embedded: false)
            }
            .frame(minHeight: 140)
        }
        .background {
            Button("") { model.detailsRunID = model.detailsRunID == nil ? model.effectiveRunID : nil }
                .keyboardShortcut("i", modifiers: .command)
                .opacity(0).frame(width: 0, height: 0)
        }
    }
}

struct RunKindPill: View {
    let kind: RunKind

    private var color: Color {
        switch kind {
        case .tracked: return Theme.teal
        case .proposed: return .orange
        case .drift: return .yellow
        }
    }

    var body: some View {
        Text(kind.rawValue)
            .font(.caption.weight(.medium))
            .padding(.horizontal, 8).padding(.vertical, 2)
            .background(color.opacity(0.18), in: Capsule())
            .foregroundStyle(color)
    }
}

struct HistorySection: View {
    @Bindable var model: StacksViewModel
    let embedded: Bool

    var body: some View {
        LoadView(state: model.runs) { all in
            let runs = all.filter { model.runFilter.includes($0) }
            VStack(alignment: .leading, spacing: 8) {
                // Only worth showing when the stack has proposed or drift runs next to the tracked ones.
                if all.contains(where: { $0.kind != .tracked }) {
                    Picker("Show", selection: $model.runFilter) {
                        ForEach(RunFilter.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented).labelsHidden()
                    .frame(maxWidth: 380)
                    .padding(.horizontal, embedded ? 0 : 16).padding(.top, embedded ? 0 : 8)
                }
                if all.isEmpty {
                    NoRunsView(model: model)
                } else if runs.isEmpty {
                    ContentUnavailableView("No \(model.runFilter.rawValue.lowercased()) runs", systemImage: "tray")
                } else {
                    table(runs)
                }
            }
        }
    }

    private func table(_ runs: [Run]) -> some View {
        // Selecting a run chooses the run whose changes, Logs and Live logs are shown (default: latest tracked).
        Table(runs, selection: Binding(get: { model.effectiveRunID }, set: { model.logRunID = $0 })) {
            TableColumn("") { run in
                Button { model.detailsRunID = model.detailsRunID == run.id ? nil : run.id } label: {
                    Image(systemName: "info.circle").foregroundStyle(Theme.muted)
                }
                .buttonStyle(.borderless)
                .help("Run details (⌘I)")
                .popover(isPresented: Binding(
                    get: { model.detailsRunID == run.id },
                    set: { if !$0 && model.detailsRunID == run.id { model.detailsRunID = nil } }
                ), arrowEdge: .trailing) {
                    RunInfoGrid(run: run).padding(16).frame(width: 460)
                }
            }.width(28)
            TableColumn("Run") { Text($0.id).textSelection(.enabled) }.width(min: 200, ideal: 240)
            TableColumn("Type") { RunKindPill(kind: $0.kind) }.width(min: 80, ideal: 90)
            TableColumn("State") { StateBadge(state: $0.state) }.width(min: 90, ideal: 110)
            TableColumn("When") { Text(formatTimestamp($0.createdAt)) }.width(min: 150, ideal: 180)
            TableColumn("Trigger") { Text($0.triggeredBy ?? "-") }.width(min: 80, ideal: 100)
            TableColumn("Author") { Text($0.commit?.authorName ?? "-") }.width(min: 80, ideal: 120)
            TableColumn("Title") { Text($0.title ?? "-") }
        }
        .frame(height: tableHeight(runs.count, embedded: embedded))
        .tableSurface(embedded: embedded)
        .contextMenu(forSelectionType: String.self) { ids in
            if let id = ids.first {
                Button("Details") { model.showDetails(id) }
                Button("Open logs") { model.openLogs(id) }
                Button("Follow live") { model.openLogs(id, live: true) }
                    .disabled(!(runs.first { $0.id == id }?.isInProgress ?? false))
                if model.actionsEnabled, let run = runs.first(where: { $0.id == id }), run.state == "FAILED" {
                    Divider()
                    Button("Retry failed run") { model.requestRetry(run) }
                }
            }
        } primaryAction: { ids in
            if let id = ids.first { model.openLogs(id) }
        }
    }
}

struct OutputsSection: View {
    @Bindable var model: StacksViewModel
    let embedded: Bool

    private func filtered(_ rows: [OutputRow]) -> [OutputRow] {
        let f = model.outputFilter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !f.isEmpty else { return rows }
        return rows.filter {
            $0.output.lowercased().contains(f) || $0.path.lowercased().contains(f) || $0.value.lowercased().contains(f)
        }
    }

    var body: some View {
        LoadView(state: model.outputs) { all in
            if all.isEmpty {
                ContentUnavailableView("No outputs", systemImage: "tray")
            } else {
                let rows = filtered(all)
                VStack(spacing: 0) {
                    if !embedded {
                        TextField("Filter outputs", text: $model.outputFilter)
                            .textFieldStyle(.roundedBorder).padding([.horizontal, .top], 16)
                    }
                    Table(rows) {
                        TableColumn("Output", value: \.output).width(min: 80, ideal: 120)
                        TableColumn("Path", value: \.path).width(min: 160, ideal: 280)
                        TableColumn("Value") { Text($0.value).textSelection(.enabled) }
                    }
                    .frame(height: tableHeight(rows.count, embedded: embedded))
                    .tableSurface(embedded: embedded)
                }
            }
        }
    }
}

struct EnvironmentSection: View {
    @Bindable var model: StacksViewModel
    let embedded: Bool

    private func filtered(_ rows: [EnvRow]) -> [EnvRow] {
        let f = model.environmentFilter.trimmingCharacters(in: .whitespaces).lowercased()
        guard !f.isEmpty else { return rows }
        return rows.filter {
            $0.name.lowercased().contains(f) || $0.type.lowercased().contains(f)
                || $0.value.lowercased().contains(f) || $0.context.lowercased().contains(f)
        }
    }

    var body: some View {
        LoadView(state: model.environment) { all in
            if all.isEmpty {
                ContentUnavailableView("No environment variables", systemImage: "tray")
            } else {
                let rows = filtered(all)
                VStack(spacing: 0) {
                    if !embedded {
                        TextField("Filter environment", text: $model.environmentFilter)
                            .textFieldStyle(.roundedBorder).padding([.horizontal, .top], 16)
                    }
                    Table(rows) {
                        TableColumn("Name") { Text($0.name).textSelection(.enabled) }.width(min: 180, ideal: 260)
                        TableColumn("Type", value: \.type).width(min: 100, ideal: 150)
                        TableColumn("Value") { Text($0.value).textSelection(.enabled) }
                        TableColumn("Context", value: \.context).width(min: 100, ideal: 180)
                    }
                    .frame(height: tableHeight(rows.count, embedded: embedded))
                    .tableSurface(embedded: embedded)
                }
            }
        }
    }
}

// MARK: - Everything (all but logs, like the script)

struct EverythingView: View {
    @Bindable var model: StacksViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                OverviewSections(model: model)
                GroupBox("Changes") { ChangesSection(model: model, embedded: true) }
                GroupBox("Run history") { HistorySection(model: model, embedded: true) }
                GroupBox("Outputs") { OutputsSection(model: model, embedded: true) }
                GroupBox("Environment") { EnvironmentSection(model: model, embedded: true) }
            }
            .padding(16)
        }
    }
}

// MARK: - Logs / Live logs

private let logPhases = ["", "QUEUED", "PREPARING", "INITIALIZING", "PLANNING", "APPLYING", "FINISHED"]

struct LogsPane: View {
    @Bindable var model: StacksViewModel
    let streamer: LogStreamer
    let follow: Bool

    /// Restart the stream whenever the run (or, for static logs, the phase) changes.
    private var streamKey: String { "\(model.effectiveRunID ?? "-")|\(follow ? "" : model.logPhase)" }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 12) {
                Picker("Run", selection: runBinding) {
                    ForEach(model.runs.value ?? []) { run in
                        Text("\(run.id.prefix(8))…  \(run.kind.rawValue)  \(run.state)  \(formatTimestamp(run.createdAt))").tag(Optional(run.id))
                    }
                }
                .frame(maxWidth: 420)
                .disabled((model.runs.value ?? []).isEmpty)

                if !follow {
                    Picker("Phase", selection: $model.logPhase) {
                        ForEach(logPhases, id: \.self) { Text($0.isEmpty ? "All phases" : $0).tag($0) }
                    }
                    .frame(maxWidth: 220)
                }

                Toggle("Auto-scroll", isOn: $model.autoscroll).toggleStyle(.checkbox)

                Spacer()

                if streamer.isRunning { ProgressView().controlSize(.small) }
                if follow {
                    if streamer.isRunning {
                        Button("Stop") { streamer.stop() }
                    } else {
                        Button("Follow again") { model.startLogs(streamer, follow: true) }
                            .disabled(model.effectiveRunID == nil)
                    }
                }
            }
            .padding(10)

            Divider()

            if let error = model.runs.error {
                Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).padding()
                Spacer()
            } else if case .loaded(let runs) = model.runs, runs.isEmpty {
                ContentUnavailableView("No runs", systemImage: "tray")
            } else if model.runs.isLoading || model.runs.needsLoad && model.effectiveRunID == nil {
                ProgressView("Loading runs…").frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                if let error = streamer.error {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red).padding(8)
                }
                LogTextView(streamer: streamer, autoscroll: model.autoscroll)
            }
        }
        .task(id: streamKey) { model.startLogs(streamer, follow: follow) }
        .onDisappear { streamer.stop() }
    }

    private var runBinding: Binding<String?> {
        Binding(get: { model.effectiveRunID }, set: { model.logRunID = $0 })
    }
}
