import AppKit
import Foundation

struct ReleaseUpdate: Equatable {
    let tag: String
    let version: String
}

enum AppReleases {
    static let fallbackVersion = "0.4.7"
    static let releasesPageURL = URL(string: "https://github.com/luispcoutinho/spacectl-ui/releases")!
    private static let latestAPIURL = URL(string: "https://api.github.com/repos/luispcoutinho/spacectl-ui/releases/latest")!

    static var currentVersion: String {
        if let v = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String,
           !v.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return v.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return fallbackVersion
    }

    private struct GitHubRelease: Decodable {
        let tagName: String
        let draft: Bool?
        let prerelease: Bool?
        enum CodingKeys: String, CodingKey {
            case tagName = "tag_name"
            case draft, prerelease
        }
    }

    static func checkLatest() async throws -> ReleaseUpdate? {
        var req = URLRequest(url: latestAPIURL, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 10)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.setValue("spacectl-ui/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
        let release = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard release.draft != true, release.prerelease != true else { return nil }
        let remoteVersion = normalize(release.tagName)
        guard !remoteVersion.isEmpty, isNewer(remoteVersion, than: normalize(currentVersion)) else {
            return nil
        }
        let tag = release.tagName.hasPrefix("v") || release.tagName.hasPrefix("V") ? release.tagName : "v\(remoteVersion)"
        return ReleaseUpdate(tag: tag, version: remoteVersion)
    }

    static func normalize(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s.hasPrefix("v") || s.hasPrefix("V") { s.removeFirst() }
        if let dash = s.firstIndex(of: "-") { s = String(s[..<dash]) }
        if let plus = s.firstIndex(of: "+") { s = String(s[..<plus]) }
        return s
    }

    /// Numeric semver comparison ("0.4.10" > "0.4.7", "0.5.0" > "0.4.7").
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let a = candidate.split(separator: ".").map { Int($0) ?? 0 }
        let b = current.split(separator: ".").map { Int($0) ?? 0 }
        guard !a.isEmpty, !b.isEmpty else { return false }
        let count = max(a.count, b.count)
        for i in 0..<count {
            let lhs = i < a.count ? a[i] : 0
            let rhs = i < b.count ? b[i] : 0
            if lhs != rhs { return lhs > rhs }
        }
        return false
    }
}

extension StacksViewModel {
    func startUpdateLoop() {
        updateLoopTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(6 * 3600))
                if Task.isCancelled { break }
                self?.checkForUpdates()
            }
        }
    }

    func checkForUpdates(manual: Bool = false) {
        updateTask?.cancel()
        checkingForUpdates = true
        if manual { updateCheckFailed = false }
        updateTask = Task {
            defer { if !Task.isCancelled { checkingForUpdates = false } }
            do {
                let update = try await AppReleases.checkLatest()
                if Task.isCancelled { return }
                availableUpdate = update
                updateCheckFailed = false
            } catch {
                if Task.isCancelled { return }
                if manual { updateCheckFailed = true }
            }
        }
    }

    func openReleasesPage() {
        NSWorkspace.shared.open(AppReleases.releasesPageURL)
    }
}
