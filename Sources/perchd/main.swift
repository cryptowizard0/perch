import Foundation
import PerchCore

// perchd — the Perch daemon. Single source of truth.
// Owns the SQLite store, listens on the Unix socket (+ localhost HTTP),
// pushes events to every `watch` client, renders ~/.perch/todo.md, ingests ~/.perch/inbox.md.
// Runs under launchd. Milestone 1 implements this target — see CLAUDE.md.

let args = Array(CommandLine.arguments.dropFirst())
if args.contains("--version") {
    print("perchd \(PerchVersion.string)")
    exit(0)
}

let message = """
perchd \(PerchVersion.string): not implemented yet (milestone 1).
  socket:   \(PerchPaths.socket.path)
  database: \(PerchPaths.database.path)
  http:     127.0.0.1:\(PerchPaths.defaultHTTPPort)

"""
FileHandle.standardError.write(Data(message.utf8))
exit(64)
