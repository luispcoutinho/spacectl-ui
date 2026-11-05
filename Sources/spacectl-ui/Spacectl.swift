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

    static func run(_ arguments: [String]) async throws -> Data {
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
            return outData
        }.value
    }

    private static func decode<T: Decodable>(_ type: T.Type, from data: Data) throws -> T {
        try JSONDecoder().decode(type, from: data)
    }

    // MARK: Queries

    /// Server-side search: listing every stack without a filter is far too slow for an interactive UI.
    static func searchStacks(_ query: String, limit: Int = 200) async throws -> [Stack] {
        let data = try await run(["stack", "list", "-o", "json", "--search", query, "--limit", String(limit)])
        return try decode([Stack].self, from: data).sorted { $0.id < $1.id }
    }

    static func stackDetail(id: String) async throws -> Stack {
        let data = try await run(["stack", "show", "--id", id, "-o", "json"])
        return try decode(Stack.self, from: data)
    }

    static func runs(stackID: String, max: Int = 10) async throws -> [Run] {
        let data = try await run(["stack", "run", "list", "--id", stackID, "--max-results", String(max), "-o", "json"])
        return try decode([Run].self, from: data)
    }

    static func changes(stackID: String, runID: String) async throws -> [ChangeRow] {
        let data = try await run(["stack", "changes", "--id", stackID, "--run", runID])
        return try decode([ChangeSet].self, from: data)
            .flatMap { $0.Resources ?? [] }
            .map { ChangeRow(type: $0.Metadata?.type ?? "-", address: $0.Address, previous: $0.PreviousAddress ?? "") }
    }

    static func environment(stackID: String) async throws -> [EnvRow] {
        let data = try await run(["stack", "environment", "list", "--id", stackID, "-o", "json"])
        return try decode([EnvVar].self, from: data).map { v in
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
        return try decode([StackOutput].self, from: data)
    }
}
