import Foundation

enum SpacectlError: LocalizedError {
    case notFound
    case failed(status: Int32, stderr: String)

    var errorDescription: String? {
        switch self {
        case .notFound:
            return "spacectl was not found. Install it (brew install spacelift-io/spacelift/spacectl) and run `spacectl profile login`."
        case .failed(let status, let stderr):
            let msg = stderr.trimmingCharacters(in: .whitespacesAndNewlines)
            return msg.isEmpty ? "spacectl exited with status \(status)" : msg
        }
    }
}

/// Thin wrapper that shells out to spacectl. All data access goes through here so it can be
/// swapped for direct GraphQL calls later.
enum Spacectl {
    // GUI apps do not inherit the shell PATH, so probe the usual install locations.
    private static let candidates = [
        "/opt/homebrew/bin/spacectl",
        "/usr/local/bin/spacectl",
        NSHomeDirectory() + "/.local/bin/spacectl",
        NSHomeDirectory() + "/go/bin/spacectl",
    ]

    static func locate() -> String? {
        candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    static func run(_ arguments: [String]) async throws -> Data { try await execute(arguments).out }

    /// Runs spacectl and returns both streams; some commands print the new run's ID on stderr.
    static func execute(_ arguments: [String]) async throws -> (out: Data, err: Data) {
        guard let path = locate() else { throw SpacectlError.notFound }
        return try await Task.detached(priority: .userInitiated) {
            let process = Process()
            process.executableURL = URL(fileURLWithPath: path)
            process.arguments = arguments
            var env = ProcessInfo.processInfo.environment
            env["NO_COLOR"] = "1"
            process.environment = env

            let out = Pipe(), err = Pipe()
            process.standardOutput = out
            process.standardError = err
            try process.run()

            // Drain stderr concurrently so a chatty failure cannot fill the pipe and deadlock us.
            let errTask = Task.detached { err.fileHandleForReading.readDataToEndOfFile() }
            let outData = out.fileHandleForReading.readDataToEndOfFile()
            process.waitUntilExit()
            let errData = await errTask.value

            guard process.terminationStatus == 0 else {
                throw SpacectlError.failed(status: process.terminationStatus,
                                           stderr: String(decoding: errData, as: UTF8.self))
            }
            return (outData, errData)
        }.value
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    /// spacectl prints JSON `null`, not `[]`, when a list is empty (for example a stack that never ran).
    private static func decodeList<T: Decodable>(_ type: T.Type, from data: Data) throws -> [T] {
        try JSONDecoder().decode([T]?.self, from: data) ?? []
    }

    // MARK: Queries

    /// Server-side search: listing every stack without a filter is far too slow for an interactive UI.
    static func searchStacks(_ query: String, limit: Int = 200) async throws -> [Stack] {
        let data = try await run(["stack", "list", "-o", "json", "--search", query, "--limit", String(limit)])
        return try decodeList(Stack.self, from: data).sorted { $0.id < $1.id }
    }

    static func stackDetail(id: String) async throws -> Stack {
        let data = try await run(["stack", "show", "--id", id, "-o", "json"])
        return try decode(Stack.self, from: data)
    }

    /// Tracked runs plus proposed and drift-detection runs, newest first. Without `--preview-runs`
    /// spacectl returns tracked runs only, and the preview list is a separate, non-overlapping set.
    static func runs(stackID: String, max: Int = 10) async throws -> [Run] {
        async let tracked = runList(stackID: stackID, max: max, preview: false)
        async let preview = runList(stackID: stackID, max: max, preview: true)
        let t = try await tracked
        let p = (try? await preview) ?? []   // keep the tracked list usable if the preview call fails
        var seen = Set<String>()
        return (t + p).filter { seen.insert($0.id).inserted }
            .sorted { ($0.createdAt ?? 0) > ($1.createdAt ?? 0) }
    }

    static func runList(stackID: String, max: Int, preview: Bool) async throws -> [Run] {
        var args = ["stack", "run", "list", "--id", stackID, "--max-results", String(max), "-o", "json"]
        if preview { args.append("--preview-runs") }
        var runs = try decodeList(Run.self, from: try await run(args))
        for i in runs.indices { runs[i].isPreview = preview }
        return runs
    }

    static func changes(stackID: String, runID: String) async throws -> [ChangeRow] {
        let data = try await run(["stack", "changes", "--id", stackID, "--run", runID])
        return try decodeList(ChangeSet.self, from: data)
            .flatMap { $0.Resources ?? [] }
            .map { ChangeRow(type: $0.Metadata?.type ?? "-", address: $0.Address, previous: $0.PreviousAddress ?? "") }
    }

    static func environment(stackID: String) async throws -> [EnvRow] {
        let data = try await run(["stack", "environment", "list", "--id", stackID, "-o", "json"])
        return try decodeList(EnvVar.self, from: data).map { v in
            // Spacelift never returns write-only values; show the same placeholders the CLI table does.
            let shown: String
            if v.writeOnly == true { shown = "*****" }
            else if (v.value ?? "").isEmpty && v.runtime == true { shown = "<computed>" }
            else { shown = v.value ?? "" }
            return EnvRow(name: v.name, type: (v.type ?? "-").replacingOccurrences(of: "_", with: " ").capitalized,
                          value: shown, context: v.context ?? "")
        }
    }

    static func outputs(stackID: String) async throws -> [StackOutput] {
        let data = try await run(["stack", "outputs", "--id", stackID, "-o", "json"])
        return try decodeList(StackOutput.self, from: data)
    }

    // MARK: Actions (change Spacelift state; only reachable when the user enabled actions)

    /// States after which a run needs nothing more from the machine, including those waiting for a human.
    static let settledStates: Set<String> = ["FINISHED", "FAILED", "DISCARDED", "CANCELED", "STOPPED", "SKIPPED",
                                             "UNCONFIRMED", "PENDING_REVIEW"]

    /// Starts a tracked run at the branch head, like the web UI's Trigger. It is never confirmed or force-applied
    /// from here: a stack with autodeploy applies on its own, any other waits for a person to confirm.
    @discardableResult
    static func deploy(stackID: String) async throws -> String? {
        let before = try? await runList(stackID: stackID, max: 1, preview: false).first?.id
        let (out, err) = try await execute(["stack", "deploy", "--id", stackID])
        if let id = runID(in: String(decoding: out, as: UTF8.self) + "\n" + String(decoding: err, as: UTF8.self)) { return id }
        // The output carried no ID: fall back to the newest tracked run, if it appeared just now.
        let after = try? await runList(stackID: stackID, max: 1, preview: false).first?.id
        return after != before ? after : nil
    }

    static func retry(stackID: String, runID: String) async throws {
        _ = try await execute(["stack", "retry", "--id", stackID, "--run", runID])
    }

    static func runState(stackID: String, runID: String) async throws -> String? {
        try await runList(stackID: stackID, max: 10, preview: false).first { $0.id == runID }?.state
    }

    /// Run IDs are 26-character ULIDs; stack slugs are lowercase, so they cannot match.
    private static func runID(in text: String) -> String? {
        let regex = try! NSRegularExpression(pattern: "\\b[0-9A-HJKMNP-TV-Z]{26}\\b")
        let range = NSRange(text.startIndex..., in: text)
        return regex.firstMatch(in: text, range: range).flatMap { Range($0.range, in: text).map { String(text[$0]) } }
    }
}
