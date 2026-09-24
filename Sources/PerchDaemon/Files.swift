import Darwin
import Foundation
import PerchCore

/// Writes `todo.md` (mode 0444) when its rendered content changes. Called on the daemon queue.
final class MirrorWriter {
    let path: String
    private var last: String?

    init(path: String) {
        self.path = path
    }

    func write(_ items: [Item]) {
        let text = MirrorRenderer.render(items)
        guard text != last else { return }
        let url = URL(fileURLWithPath: path)
        do {
            try Data(text.utf8).write(to: url, options: .atomic)
            chmod(path, 0o444)
            last = text
        } catch {
            FileHandle.standardError.write(Data("perchd: cannot write \(path): \(error)\n".utf8))
        }
    }
}

/// Watches `inbox.md` (and its directory, to notice the file being created or replaced by an editor's
/// atomic save). Everything runs on the daemon queue.
final class InboxWatcher {
    private let path: String
    private let directory: String
    private let queue: DispatchQueue
    private let onChange: () -> Void
    private var directorySource: DispatchSourceFileSystemObject?
    private var fileSource: DispatchSourceFileSystemObject?
    private var fileInode: ino_t = 0

    init(path: String, queue: DispatchQueue, onChange: @escaping () -> Void) {
        self.path = path
        directory = (path as NSString).deletingLastPathComponent
        self.queue = queue
        self.onChange = onChange
    }

    /// Call on the daemon queue.
    func start() {
        directorySource = source(for: directory, events: .write) { [weak self] _ in
            guard let self else { return }
            if self.currentInode() != self.fileInode { self.watchFile() }
            self.onChange()
        }
        watchFile()
    }

    func stop() {
        directorySource?.cancel()
        fileSource?.cancel()
    }

    private func watchFile() {
        fileSource?.cancel()
        fileSource = nil
        fileInode = currentInode()
        guard fileInode != 0 else { return }
        fileSource = source(for: path, events: [.write, .extend, .delete, .rename]) { [weak self] events in
            guard let self else { return }
            if !events.isDisjoint(with: [.delete, .rename]) { self.watchFile() }
            self.onChange()
        }
    }

    private func currentInode() -> ino_t {
        var st = stat()
        return stat(path, &st) == 0 ? st.st_ino : 0
    }

    private func source(for path: String, events: DispatchSource.FileSystemEvent,
                        handler: @escaping (DispatchSource.FileSystemEvent) -> Void) -> DispatchSourceFileSystemObject? {
        let fd = open(path, O_EVTONLY)
        guard fd >= 0 else { return nil }
        let source = DispatchSource.makeFileSystemObjectSource(fileDescriptor: fd, eventMask: events, queue: queue)
        source.setEventHandler { [weak source] in handler(source?.data ?? []) }
        source.setCancelHandler { close(fd) }
        source.resume()
        return source
    }
}
