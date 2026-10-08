import Foundation
import PerchCore

/// Watches the transcripts of sessions that are running or waiting, and calls back with the session id whenever
/// one grows. Claude Code appends to its transcript; the daemon reads the end (`tail(of:)`) and looks for an
/// interruption no hook reported (`ClaudeTranscript`, #8). Lives on the daemon queue.
final class TranscriptWatcher {
    private let queue: DispatchQueue
    private let onChange: (String) -> Void
    private var watched: [String: (path: String, source: DispatchSourceFileSystemObject)] = [:]

    /// How much of the end of a transcript is read: the interruption is the last few small entries.
    static let tailBytes = 64 * 1024

    init(queue: DispatchQueue, onChange: @escaping (String) -> Void) {
        self.queue = queue
        self.onChange = onChange
    }

    /// Session id → transcript path being watched.
    var paths: [String: String] { watched.mapValues(\.path) }

    /// Watches exactly `wanted` (session id → transcript path); returns the sessions newly watched, which the
    /// caller checks once right away (the transcript may already say the turn was interrupted).
    @discardableResult
    func watch(_ wanted: [String: String]) -> [String] {
        for (id, entry) in watched where wanted[id] != entry.path {
            entry.source.cancel()
            watched[id] = nil
        }
        var added: [String] = []
        for (id, path) in wanted where watched[id] == nil {
            let fd = open(path, O_EVTONLY)
            guard fd >= 0 else { continue }
            let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: [.write, .extend], queue: queue)
            source.setEventHandler { [weak self] in self?.onChange(id) }
            source.setCancelHandler { close(fd) }
            source.resume()
            watched[id] = (path, source)
            added.append(id)
        }
        return added
    }

    func stop() {
        watch([:])
    }

    /// The last `bytes` of the file as text (the first line may be cut; `ClaudeTranscript` skips it).
    static func tail(of path: String, bytes: Int = tailBytes) -> String? {
        guard let handle = FileHandle(forReadingAtPath: path) else { return nil }
        defer { try? handle.close() }
        guard let size = try? handle.seekToEnd() else { return nil }
        try? handle.seek(toOffset: size > UInt64(bytes) ? size - UInt64(bytes) : 0)
        guard let data = try? handle.readToEnd() else { return nil }
        return String(decoding: data, as: UTF8.self)
    }
}
