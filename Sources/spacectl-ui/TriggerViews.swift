import SwiftUI
import AppKit

// MARK: - Sidebar tab

/// Search results that have run before, with checkboxes. Nothing is ticked until the user ticks it.
struct TriggerListView: View {
    @Bindable var model: StacksViewModel

    var body: some View {
        if !model.triggerBatch.isEmpty {
            TriggerProgressView(model: model)
        } else {
            selection
        }
    }

    private var selection: some View {
        let candidates = model.triggerCandidates
        let hidden = model.stacks.count - candidates.count
        return VStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Picker("Action", selection: $model.triggerAction) {
                    ForEach(TriggerAction.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented).labelsHidden()
                Text(model.triggerAction == .preview
                     ? "Starts a proposed run (plan only) on each selected stack. Nothing is applied."
                     : "Starts a tracked run on each selected stack. Stacks with autodeploy apply immediately.")
                    .font(.caption).foregroundStyle(Theme.muted)
            }
            .padding(.horizontal, 12).padding(.bottom, 8)

            HStack(spacing: 10) {
                Text("\(model.triggerSelected.count) of \(candidates.count) selected")
                    .font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                Button("Select all \(candidates.count)") { model.setTriggerSelection(all: true) }.disabled(candidates.isEmpty)
                Button("None") { model.setTriggerSelection(all: false) }.disabled(model.triggerSelection.isEmpty)
            }
            .buttonStyle(.plain).font(.caption).foregroundStyle(Theme.accent)
            .padding(.horizontal, 12).padding(.bottom, 6)

            List(candidates) { stack in row(stack) }
                .listStyle(.sidebar)
                .scrollContentBackground(.hidden)
                .background(Theme.sidebar)
                .overlay { overlayContent(candidates: candidates) }

            VStack(alignment: .leading, spacing: 6) {
                if hidden > 0 && model.triggerAction == .deploy {
                    Text("\(hidden) never-run \(hidden == 1 ? "stack" : "stacks") hidden. Start a first run from the stack's own page.")
                        .font(.caption).foregroundStyle(Theme.muted)
                }
                if model.stacks.count >= 200 {
                    Text("Results are limited to 200. Narrow the search before selecting all.")
                        .font(.caption).foregroundStyle(.orange)
                }
                Button {
                    model.triggerPhrase = ""
                    model.triggerSheet = true
                } label: {
                    Text("\(model.triggerAction.rawValue) \(model.triggerSelected.count) \(model.triggerSelected.count == 1 ? "stack" : "stacks")…")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.triggerSelected.isEmpty)
            }
            .padding(12)
        }
    }

    private func row(_ stack: Stack) -> some View {
        Toggle(isOn: Binding(
            get: { model.triggerSelection.contains(stack.id) },
            set: { on in
                if on { model.triggerSelection.insert(stack.id) } else { model.triggerSelection.remove(stack.id) }
            }
        )) {
            HStack(spacing: 8) {
                Circle().fill(stateColor(stack.state)).frame(width: 8, height: 8)
                VStack(alignment: .leading, spacing: 2) {
                    Text(stack.id).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    Text(prettyState(stack.state)).font(.caption).foregroundStyle(Theme.muted)
                }
                Spacer(minLength: 4)
                if stack.autodeploy == true {
                    Image(systemName: "bolt.fill").foregroundStyle(.yellow).help("Autodeploy: a new run applies immediately")
                }
                if stack.hasBlocker {
                    Image(systemName: "hourglass").foregroundStyle(.orange).help("Another run is blocking this stack; a new run will queue")
                }
                if stack.canWrite == false {
                    Image(systemName: "lock.fill").foregroundStyle(Theme.muted).help("No permission to run this stack")
                }
            }
        }
        .toggleStyle(.checkbox)
        .disabled(stack.canWrite == false)
        .padding(.vertical, 3)
    }

    @ViewBuilder private func overlayContent(candidates: [Stack]) -> some View {
        if model.spacectlMissing {
            ContentUnavailableView("spacectl not found", systemImage: "exclamationmark.triangle",
                                   description: Text(SpacectlError.notFound.localizedDescription))
        } else if let error = model.searchError {
            ContentUnavailableView("Search failed", systemImage: "xmark.octagon", description: Text(error))
        } else if candidates.isEmpty && !model.isSearching {
            if model.query.trimmingCharacters(in: .whitespaces).count < 2 {
                ContentUnavailableView("Search for stacks", systemImage: "magnifyingglass",
                                       description: Text("Type at least 2 characters. Deploy lists only stacks that have run before."))
            } else {
                ContentUnavailableView("No stacks to deploy", systemImage: "tray",
                                       description: Text("None of the matches has run before. Preview works on any stack."))
            }
        }
    }
}

// MARK: - Batch progress

struct TriggerProgressView: View {
    var model: StacksViewModel

    private var settled: Int {
        model.triggerBatch.filter {
            switch $0.status { case .queued, .starting, .running: return false; default: return true }
        }.count
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("\(model.triggerBatchAction == .preview ? "Previewing" : "Deploying"): \(settled) of \(model.triggerBatch.count) settled").font(.caption).foregroundStyle(Theme.muted)
                Spacer()
                if model.triggerRunning { ProgressView().controlSize(.small) }
            }
            .padding(.horizontal, 12).padding(.bottom, 6)

            List(model.triggerBatch) { item in
                VStack(alignment: .leading, spacing: 4) {
                    Text(item.stack.id).font(.callout.weight(.medium)).lineLimit(1).truncationMode(.middle)
                    status(item.status)
                }
                .padding(.vertical, 3)
                .contentShape(Rectangle())
                .onTapGesture { model.selectedID = item.stack.id }
            }
            .listStyle(.sidebar)
            .scrollContentBackground(.hidden)
            .background(Theme.sidebar)

            HStack {
                if model.triggerRunning {
                    Text("Up to \(StacksViewModel.maxInFlight) runs at once").font(.caption).foregroundStyle(Theme.muted)
                    Spacer()
                    Button("Stop") { model.stopBatch() }
                        .help("Stop starting new stacks. Runs already created keep going in Spacelift.")
                } else {
                    Spacer()
                    Button("Done") { model.finishBatch() }.buttonStyle(.borderedProminent)
                }
            }
            .padding(12)
        }
    }

    @ViewBuilder private func status(_ s: TriggerItem.Status) -> some View {
        switch s {
        case .queued:
            Label("Queued", systemImage: "clock").font(.caption).foregroundStyle(Theme.muted)
        case .starting:
            HStack(spacing: 6) { ProgressView().controlSize(.mini); Text("Starting…").font(.caption).foregroundStyle(Theme.muted) }
        case .running(_, let state):
            HStack(spacing: 6) { ProgressView().controlSize(.mini); StateBadge(state: state) }
        case .finished(_, let state):
            StateBadge(state: state)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.red)
                .lineLimit(3)
        case .stopped:
            Label("Stopped waiting; the run continues in Spacelift", systemImage: "stop.circle")
                .font(.caption).foregroundStyle(.orange)
        case .notStarted:
            Label("Not started", systemImage: "minus.circle").font(.caption).foregroundStyle(Theme.muted)
        }
    }
}

// MARK: - Confirmation sheet

struct TriggerConfirmSheet: View {
    @Bindable var model: StacksViewModel

    var body: some View {
        let selected = model.triggerSelected
        let preview = model.triggerAction == .preview
        let auto = selected.filter { $0.autodeploy == true }
        let blocked = selected.filter(\.hasBlocker)
        VStack(alignment: .leading, spacing: 14) {
            Text("\(model.triggerAction.rawValue) \(selected.count) \(selected.count == 1 ? "stack" : "stacks")")
                .font(.title3.weight(.semibold))
            Text(preview
                 ? "Starts a proposed run (plan only, spacectl stack preview) at the branch head of each stack. Nothing is applied. At most \(StacksViewModel.maxInFlight) are in progress at once."
                 : "Starts a new tracked run at the branch head of each stack (spacectl stack deploy). Runs are not confirmed from here, and at most \(StacksViewModel.maxInFlight) are in progress at once.")
                .font(.callout).foregroundStyle(Theme.muted)

            if !preview && !auto.isEmpty {
                warning("bolt.fill", .yellow,
                        "\(auto.count) of \(selected.count) have autodeploy on and will apply immediately:",
                        names: auto.map(\.id))
            }
            if !preview && !blocked.isEmpty {
                warning("hourglass", .orange,
                        "\(blocked.count) already have a blocking run; theirs will queue behind it:",
                        names: blocked.map(\.id))
            }

            GroupBox("Stacks") {
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(selected) { Text($0.id).font(.caption.monospaced()).textSelection(.enabled) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(height: 120)
            }

            if !preview {
                VStack(alignment: .leading, spacing: 6) {
                    Text("To confirm, type one of:").font(.callout)
                    ForEach(model.triggerPhrases, id: \.self) { Text($0).font(.callout.monospaced()).foregroundStyle(Theme.accent) }
                    TextField("", text: $model.triggerPhrase)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { model.startBatch() }
                }
            }

            HStack {
                Spacer()
                Button("Cancel") { model.triggerSheet = false }.keyboardShortcut(.cancelAction)
                Button(model.triggerAction.rawValue) { model.startBatch() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.triggerPhraseMatches)
            }
        }
        .padding(20)
        .frame(width: 520)
        .background(Theme.bg)
        .preferredColorScheme(.dark)
    }

    private func warning(_ icon: String, _ color: Color, _ text: String, names: [String]) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Label(text, systemImage: icon).foregroundStyle(color).font(.callout)
            Text(names.prefix(6).joined(separator: ", ") + (names.count > 6 ? " and \(names.count - 6) more" : ""))
                .font(.caption.monospaced()).foregroundStyle(Theme.muted).lineLimit(3)
        }
    }
}

// MARK: - Settings and empty state

struct SettingsView: View {
    @Bindable var model: StacksViewModel

    var body: some View {
        Form {
            Toggle("Enable actions", isOn: $model.actionsEnabled)
            Text("Off by default, so the app stays read-only. When on, you can Trigger a stack's first run, Retry a failed run, and Trigger several stacks from the Trigger tab. Every action asks for confirmation, and runs started here use your Spacelift permissions.")
                .font(.caption).foregroundStyle(.secondary)
        }
        .padding(20)
        .frame(width: 440)
        .preferredColorScheme(.dark)
    }
}

/// A stack with no runs: offers the first run when actions are on, explains how to get it when they are off.
struct NoRunsView: View {
    var model: StacksViewModel

    var body: some View {
        ContentUnavailableView {
            Label("No runs", systemImage: "tray")
        } description: {
            if model.actionsEnabled {
                Text(model.stack.value?.canWrite == false
                     ? "This stack has never run, and you do not have permission to run it."
                     : "This stack has never run.")
            } else {
                Text("This stack has never run. Enable actions in Settings (⌘,) to start its first run.")
            }
        } actions: {
            if model.actionsEnabled {
                Button("Trigger") { model.requestTrigger() }
                    .buttonStyle(.borderedProminent)
                    .disabled(!model.canTriggerFirstRun)
            }
        }
    }
}
