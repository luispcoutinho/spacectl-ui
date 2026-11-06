import Foundation

/// A single-stack action waiting for the user's confirmation.
enum PendingAction: Equatable {
    case trigger(stackID: String, autodeploy: Bool)
    case retry(stackID: String, runID: String)
}

/// What the Trigger tab starts on every selected stack.
enum TriggerAction: String, CaseIterable, Identifiable {
    case preview = "Preview"   // a proposed run: plans, never applies
    case deploy = "Deploy"     // a tracked run: applies at once on stacks with autodeploy
    var id: String { rawValue }
}

/// One stack in a Trigger batch.
struct TriggerItem: Identifiable {
    enum Status: Equatable {
        case queued, starting
        case running(runID: String, state: String)
        case finished(runID: String, state: String)   // settled: done, failed or waiting for a person
        case failed(String)
        case stopped(runID: String)                   // Stop was pressed; the run keeps going in Spacelift
        case notStarted
    }

    let stack: Stack
    var status: Status = .queued
    var id: String { stack.id }
}

extension StacksViewModel {
    /// Runs in flight at once. Waiting for each run to settle is what keeps the runners from being flooded.
    static let maxInFlight = 3

    // MARK: Single stack

    /// Never deployed: no tracked run yet. Only then is the header button enabled.
    var canTriggerFirstRun: Bool {
        guard actionsEnabled, !actionBusy, let runs = runs.value, stack.value?.canWrite != false else { return false }
        return !runs.contains { $0.kind == .tracked }
    }

    var triggerButtonHelp: String {
        if runs.value == nil { return "Loading runs…" }
        if stack.value?.canWrite == false { return "You do not have permission to run this stack." }
        if canTriggerFirstRun { return "Start the first run (spacectl stack deploy)" }
        return "This stack already has runs. Use the Trigger tab in the sidebar to start another."
    }

    func requestTrigger() {
        guard canTriggerFirstRun, let s = stack.value else { return }
        pendingAction = .trigger(stackID: s.id, autodeploy: s.autodeploy == true)
    }

    func requestRetry(_ run: Run) {
        guard actionsEnabled, !actionBusy, run.state == "FAILED", let id = selectedID else { return }
        pendingAction = .retry(stackID: id, runID: run.id)
    }

    func confirmPending() {
        guard let action = pendingAction else { return }
        pendingAction = nil
        actionBusy = true
        Task {
            defer { actionBusy = false }
            do {
                let stackID: String
                switch action {
                case .trigger(let id, _):
                    stackID = id
                    try await Spacectl.deploy(stackID: id)
                case .retry(let id, let runID):
                    stackID = id
                    try await Spacectl.retry(stackID: id, runID: runID)
                }
                if selectedID == stackID { refresh(); tab = .history }
            } catch {
                actionError = error.localizedDescription
            }
        }
    }

    // MARK: Trigger tab (many stacks, from the current search)

    /// Deploy only lists stacks that have run before: a never-run stack has the state NONE, and its first
    /// deployment is started from its own page. A preview applies nothing, so it covers every match.
    var triggerCandidates: [Stack] {
        triggerAction == .preview ? stacks : stacks.filter { ($0.state ?? "NONE") != "NONE" }
    }

    /// Ticked stacks that are still in the results; ticks for stacks the search no longer shows never count.
    var triggerSelected: [Stack] {
        triggerCandidates.filter { triggerSelection.contains($0.id) && $0.canWrite != false }
    }

    func setTriggerSelection(all: Bool) {
        triggerSelection = all ? Set(triggerCandidates.filter { $0.canWrite != false }.map(\.id)) : []
    }

    /// Deploy needs the user to type `deploy <count>` or `deploy <search>`, so a click cannot start it by accident.
    /// A preview applies nothing and needs no phrase.
    var triggerPhrases: [String] {
        guard triggerAction == .deploy else { return [] }
        let q = query.trimmingCharacters(in: .whitespaces)
        return ["deploy \(triggerSelected.count)"] + (q.isEmpty ? [] : ["deploy \(q)"])
    }

    var triggerPhraseMatches: Bool {
        if triggerAction == .preview { return true }
        func norm(_ s: String) -> String { s.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ") }
        let typed = norm(triggerPhrase)
        return !typed.isEmpty && triggerPhrases.contains { norm($0) == typed }
    }

    func startBatch() {
        let selected = triggerSelected
        guard actionsEnabled, !selected.isEmpty, !triggerRunning, triggerPhraseMatches else { return }
        triggerBatchAction = triggerAction
        triggerBatch = selected.map { TriggerItem(stack: $0) }
        triggerRunning = true
        triggerSheet = false
        triggerPhrase = ""
        triggerTask = Task { await runBatch() }
    }

    /// Stop starting new stacks and stop waiting on running ones. Runs already created keep going in Spacelift.
    func stopBatch() { triggerTask?.cancel() }

    /// Leave the progress view; refresh the list so the stacks show their new states.
    func finishBatch() {
        guard !triggerRunning else { return }
        triggerBatch = []
        triggerSelection = []
        queryChanged()
    }

    private func runBatch() async {
        let count = triggerBatch.count
        var next = 0
        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<min(Self.maxInFlight, count) {
                let i = next; next += 1
                group.addTask { @MainActor in await self.triggerOne(i) }
            }
            // Each time a stack settles, start the next one, so at most maxInFlight runs are active.
            while await group.next() != nil {
                guard next < count, !Task.isCancelled else { continue }
                let i = next; next += 1
                group.addTask { @MainActor in await self.triggerOne(i) }
            }
        }
        for i in triggerBatch.indices where triggerBatch[i].status == .queued { triggerBatch[i].status = .notStarted }
        triggerRunning = false
    }

    private func triggerOne(_ i: Int) async {
        let id = triggerBatch[i].stack.id
        let preview = triggerBatchAction == .preview
        triggerBatch[i].status = .starting
        var runID: String?
        do {
            runID = preview ? try await Spacectl.preview(stackID: id) : try await Spacectl.deploy(stackID: id)
            guard let run = runID else {
                triggerBatch[i].status = .failed("A run was started but its ID could not be read. Check the stack before triggering again.")
                return
            }
            var state = "QUEUED"
            triggerBatch[i].status = .running(runID: run, state: state)
            while !Spacectl.settledStates.contains(state) {
                try await Task.sleep(for: .seconds(10))
                // A failed poll is retried on the next tick; Stop ends the wait.
                if let s = (try? await Spacectl.runState(stackID: id, runID: run, preview: preview)) ?? nil, s != state {
                    state = s
                    triggerBatch[i].status = .running(runID: run, state: state)
                }
            }
            triggerBatch[i].status = .finished(runID: run, state: state)
        } catch is CancellationError {
            triggerBatch[i].status = runID.map { .stopped(runID: $0) } ?? .notStarted
        } catch {
            triggerBatch[i].status = .failed(error.localizedDescription)
        }
    }
}
