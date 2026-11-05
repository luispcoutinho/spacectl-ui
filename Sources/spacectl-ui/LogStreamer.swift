import AppKit
import Foundation
import Observation
import SwiftUI

/// Streams `spacectl stack logs` into a text view, line by line, with batched UI updates.
@Observable
@MainActor
final class LogStreamer {
    var isRunning = false
    var error: String?

    // The text view subscribes to these; logs can be megabytes, so they never live in SwiftUI state.
    @ObservationIgnored var onChunk: ((String) -> Void)?
    @ObservationIgnored var onReset: (() -> Void)?

    @ObservationIgnored private var process: Process?
    @ObservationIgnored private var readTask: Task<Void, Never>?
    @ObservationIgnored private var flushTask: Task<Void, Never>?
    @ObservationIgnored private var buffer: [String] = []
    @ObservationIgnored private var generation = 0

    private static let ansi = try! NSRegularExpression(pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]")

    func start(stackID: String, runID: String, phase: String, follow: Bool) {
        stop()
        generation += 1
        let gen = generation
        error = nil
        onReset?()

        guard let path = Spacectl.locate() else { error = SpacectlError.notFound.localizedDescription; return }

        var args = ["stack", "logs", "--id", stackID, "--run", runID]
        if !phase.isEmpty { args += ["--phase", phase] }
        if follow { args.append("--tail") }

        let p = Process()
        p.executableURL = URL(fileURLWithPath: path)
        p.arguments = args
        var env = ProcessInfo.processInfo.environment
        env["NO_COLOR"] = "1"
        p.environment = env
        let pipe = Pipe()
        p.standardOutput = pipe
        p.standardError = pipe   // errors show up inline in the log

        do { try p.run() } catch { self.error = error.localizedDescription; return }
        process = p
        isRunning = true

        flushTask = Task { [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .milliseconds(100))
                self?.flush(gen)
            }
        }
        readTask = Task { [weak self] in
            do {
                for try await line in pipe.fileHandleForReading.bytes.lines {
                    guard let self, self.generation == gen else { return }
                    self.buffer.append(line)
                }
            } catch {}
            guard let self, self.generation == gen else { return }
            self.flush(gen)
            self.flushTask?.cancel()
            self.isRunning = false
        }
    }

    func stop() {
        generation += 1                 // makes any in-flight reader ignore further lines
        process?.terminate()
        process = nil
        readTask?.cancel()
        flushTask?.cancel()
        buffer.removeAll()
        isRunning = false
    }

    private func flush(_ gen: Int) {
        guard gen == generation, !buffer.isEmpty else { return }
        let text = buffer.joined(separator: "\n") + "\n"
        buffer.removeAll(keepingCapacity: true)
        let range = NSRange(text.startIndex..., in: text)
        onChunk?(Self.ansi.stringByReplacingMatches(in: text, range: range, withTemplate: ""))
    }
}

/// NSTextView-backed log viewer: handles large logs smoothly and gives ⌘F find for free.
struct LogTextView: NSViewRepresentable {
    let streamer: LogStreamer
    var autoscroll: Bool

    final class Coordinator {
        var autoscroll = true
        // Spacelift prints each phase as a banner: dashes / "PHASE<TAB>date" / dashes. The banner can be
        // split across chunks, so the small state machine below lives here, not in the chunk handler.
        private var heldDash: String?
        private var phaseLine: String?

        private let body: [NSAttributedString.Key: Any] = [
            .font: NSFont.monospacedSystemFont(ofSize: 11, weight: .regular),
            .foregroundColor: NSColor.labelColor,
        ]

        func reset() { heldDash = nil; phaseLine = nil; emittedAny = false }

        private func isDash(_ l: String) -> Bool { l.count >= 10 && l.allSatisfy { $0 == "-" } }

        private func phase(_ l: String) -> (name: String, date: String)? {
            let parts = l.split(separator: "\t", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, !parts[0].isEmpty,
                  parts[0].allSatisfy({ $0.isUppercase || $0 == "_" }) else { return nil }
            return (String(parts[0]), String(parts[1]))
        }

        private static func color(_ name: String) -> NSColor {
            switch name {
            case "QUEUED", "READY", "DISCARDED", "CANCELED", "STOPPED", "SKIPPED": return .systemGray
            case "PREPARING", "PREPARING_APPLY": return .systemTeal
            case "INITIALIZING": return .systemBlue
            case "PLANNING": return NSColor(Theme.accent)
            case "UNCONFIRMED", "PENDING_REVIEW", "CONFIRMED": return .systemYellow
            case "APPLYING", "PERFORMING", "DESTROYING": return .systemOrange
            case "FINISHED": return .systemGreen
            case "FAILED": return .systemRed
            default: return .systemPurple
            }
        }

        private func header(_ name: String, _ date: String, first: Bool) -> NSAttributedString {
            let color = Self.color(name)
            let para = NSMutableParagraphStyle()
            para.paragraphSpacingBefore = first ? 4 : 22
            para.paragraphSpacing = 6
            let out = NSMutableAttributedString(string: "\u{258C} ", attributes: [
                .font: NSFont.systemFont(ofSize: 15, weight: .bold), .foregroundColor: color, .paragraphStyle: para])
            out.append(NSAttributedString(string: name.replacingOccurrences(of: "_", with: " "), attributes: [
                .font: NSFont.systemFont(ofSize: 13, weight: .bold), .foregroundColor: color, .paragraphStyle: para]))
            out.append(NSAttributedString(string: "   \(date)\n", attributes: [
                .font: NSFont.monospacedSystemFont(ofSize: 10.5, weight: .regular),
                .foregroundColor: NSColor.secondaryLabelColor, .paragraphStyle: para]))
            return out
        }

        private var emittedAny = false

        /// Turns phase banners into colored, spaced headings; everything else stays plain monospaced text.
        func render(_ chunk: String) -> NSAttributedString {
            let out = NSMutableAttributedString()
            func raw(_ l: String) { out.append(NSAttributedString(string: l + "\n", attributes: body)) }

            var lines = chunk.components(separatedBy: "\n")
            if lines.last == "" { lines.removeLast() }
            for line in lines {
                if let p = phaseLine {
                    phaseLine = nil
                    if isDash(line), let ph = phase(p) {
                        out.append(header(ph.name, ph.date, first: !emittedAny)); emittedAny = true
                        heldDash = nil
                        continue
                    }
                    raw(heldDash ?? ""); raw(p); heldDash = nil   // not a banner after all
                }
                if let d = heldDash {
                    if phase(line) != nil { phaseLine = line; continue }
                    raw(d); heldDash = nil
                }
                if isDash(line) { heldDash = line; continue }
                raw(line); emittedAny = true
            }
            return out
        }
    }
    func makeCoordinator() -> Coordinator { Coordinator() }

    func makeNSView(context: Context) -> NSScrollView {
        let scroll = NSTextView.scrollableTextView()
        let tv = scroll.documentView as! NSTextView
        tv.isEditable = false
        tv.isSelectable = true
        tv.usesFindBar = true
        tv.isIncrementalSearchingEnabled = true
        tv.textContainerInset = NSSize(width: 8, height: 8)
        tv.drawsBackground = false
        scroll.drawsBackground = false

        let coordinator = context.coordinator
        coordinator.autoscroll = autoscroll

        streamer.onReset = { [weak tv] in coordinator.reset(); tv?.string = "" }
        streamer.onChunk = { [weak tv] chunk in
            guard let tv else { return }
            tv.textStorage?.append(coordinator.render(chunk))
            if coordinator.autoscroll { tv.scrollToEndOfDocument(nil) }
        }
        return scroll
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        context.coordinator.autoscroll = autoscroll
    }
}
