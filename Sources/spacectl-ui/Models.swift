import Foundation

struct Commit: Decodable, Hashable {
    var hash: String?
    var authorName: String?
    var authorLogin: String?
    var message: String?
    var timestamp: Double?
    var url: String?
}

struct WorkerPool: Decodable, Hashable {
    var id: String?
    var name: String?
}

struct Stack: Decodable, Identifiable, Hashable {
    var id: String
    var name: String
    var state: String?
    var stateSetAt: Double?
    var branch: String?
    var repository: String?
    var projectRoot: String?
    var description: String?
    var labels: [String]?
    var terraformVersion: String?
    var autodeploy: Bool?
    var trackedCommit: Commit?
    var workerPool: WorkerPool?
    var provider: String?
    var administrative: Bool?
    var autoretry: Bool?
    var localPreviewEnabled: Bool?
    var managesStateFile: Bool?
    var runnerImage: String?
    var additionalProjectGlobs: [String]?
    var AttachedContexts: [ContextRef]?
    var AttachedPolicies: [PolicyRef]?
    var VendorConfig: VendorConfig?
}

struct ContextItem: Decodable, Hashable {
    var id: String
    var type: String?
}

struct ContextRef: Decodable, Hashable, Identifiable {
    var contextId: String?
    var name: String?
    var config: [ContextItem]?
    var id: String { contextId ?? name ?? UUID().uuidString }
}

struct PolicyRef: Decodable, Hashable, Identifiable {
    var policyId: String?
    var name: String?
    var type: String?
    var id: String { policyId ?? name ?? UUID().uuidString }
}

/// A JSON scalar rendered as text; nested objects/arrays are ignored.
enum Scalar: Decodable, Hashable {
    case text(String), other

    init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if let s = try? c.decode(String.self) { self = .text(s) }
        else if let b = try? c.decode(Bool.self) { self = .text(b ? "true" : "false") }
        else if let i = try? c.decode(Int.self) { self = .text(String(i)) }
        else if let d = try? c.decode(Double.self) { self = .text(String(d)) }
        else { self = .other }
    }
}

struct Setting: Hashable { var key: String; var value: String }

private struct DynamicKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

/// `VendorConfig` carries one block per vendor; only the block matching `Vendor` is meaningful.
struct VendorConfig: Decodable, Hashable {
    var vendor: String?
    var settings: [Setting] = []

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DynamicKey.self)
        let raw = try c.decodeIfPresent(String.self, forKey: DynamicKey(stringValue: "Vendor")!)
        vendor = raw?.replacingOccurrences(of: "StackConfigVendor", with: "")
        if let name = vendor, let key = DynamicKey(stringValue: name),
           let nested = try? c.decode([String: Scalar].self, forKey: key) {
            settings = nested.keys.sorted().compactMap { k in
                if case .text(let v) = nested[k]! { return Setting(key: humanize(k), value: v) }
                return nil
            }
        }
    }
}

/// "UseSmartSanitization" -> "Use smart sanitization"
func humanize(_ key: String) -> String {
    var out = ""
    for (i, ch) in key.enumerated() {
        if ch.isUppercase && i > 0 { out += " " + ch.lowercased() } else { out += i == 0 ? ch.uppercased() : String(ch) }
    }
    return out
}

struct ChangeRow: Identifiable, Hashable {
    let id = UUID()
    let type: String
    let address: String
    let previous: String
}

struct ChangeSet: Decodable {
    var Resources: [ChangeResource]?
}
struct ChangeResource: Decodable {
    var Address: String
    var PreviousAddress: String?
    var Metadata: ChangeMeta?
}
struct ChangeMeta: Decodable {
    var type: String?
    enum CodingKeys: String, CodingKey { case type = "Type" }
}

struct EnvVar: Decodable {
    var name: String
    var type: String?
    var value: String?
    var context: String?
    var runtime: Bool?
    var writeOnly: Bool?
}

struct EnvRow: Identifiable, Hashable {
    let id = UUID()
    let name: String
    let type: String
    let value: String
    let context: String
}

enum RunKind: String {
    case tracked = "Tracked", proposed = "Proposed", drift = "Drift"
}

enum RunFilter: String, CaseIterable, Identifiable {
    case all = "All", tracked = "Tracked", proposed = "Proposed", drift = "Drift"
    var id: String { rawValue }

    func includes(_ run: Run) -> Bool {
        switch self {
        case .all: return true
        case .tracked: return run.kind == .tracked
        case .proposed: return run.kind == .proposed
        case .drift: return run.kind == .drift
        }
    }
}

struct Run: Decodable, Identifiable, Hashable {
    var id: String
    var state: String
    var title: String?
    var triggeredBy: String?
    var createdAt: Double?
    var needsApproval: Bool?
    var isMostRecent: Bool?
    var driftDetection: Bool?
    var commit: Commit?
    /// Set by the client: spacectl only returns proposed (preview) runs from a separate call.
    var isPreview = false

    private enum CodingKeys: String, CodingKey {
        case id, state, title, triggeredBy, createdAt, needsApproval, isMostRecent, driftDetection, commit
    }

    var kind: RunKind { driftDetection == true ? .drift : (isPreview ? .proposed : .tracked) }

    /// Still moving through the pipeline, so there is something to follow.
    var isInProgress: Bool {
        ["PLANNING", "APPLYING", "INITIALIZING", "PREPARING", "PREPARING_APPLY", "PERFORMING",
         "DESTROYING", "QUEUED", "READY", "PENDING", "CONFIRMED"].contains(state)
    }
}

/// `value` is a JSON document encoded as a string for structured outputs.
struct StackOutput: Decodable, Identifiable, Hashable {
    var id: String
    var value: String?
}

struct OutputRow: Identifiable, Hashable {
    let id = UUID()
    let output: String
    let path: String
    let value: String
}

enum OutputFlattener {
    /// One row per leaf value: (output, dotted path, value). Non-JSON values become a single row with path "-".
    static func rows(from outputs: [StackOutput]) -> [OutputRow] {
        var rows: [OutputRow] = []
        for out in outputs.sorted(by: { $0.id < $1.id }) {
            let raw = out.value ?? ""
            if let data = raw.data(using: .utf8),
               let json = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed]),
               json is [String: Any] || json is [Any] {
                walk(json, path: [], output: out.id, into: &rows)
            } else {
                rows.append(OutputRow(output: out.id, path: "-", value: raw))
            }
        }
        return rows
    }

    private static func walk(_ node: Any, path: [String], output: String, into rows: inout [OutputRow]) {
        if let dict = node as? [String: Any] {
            for key in dict.keys.sorted() { walk(dict[key]!, path: path + [key], output: output, into: &rows) }
        } else if let array = node as? [Any] {
            for (i, item) in array.enumerated() { walk(item, path: path + [String(i)], output: output, into: &rows) }
        } else {
            rows.append(OutputRow(output: output, path: path.joined(separator: "."), value: scalar(node)))
        }
    }

    private static func scalar(_ value: Any) -> String {
        if value is NSNull { return "null" }
        if let n = value as? NSNumber {
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue
        }
        return "\(value)"
    }
}

func formatTimestamp(_ seconds: Double?) -> String {
    guard let seconds else { return "-" }
    return Date(timeIntervalSince1970: seconds).formatted(date: .abbreviated, time: .standard)
}
