import Foundation

/// Reading the end of a Claude Code transcript (the session's JSONL log, `transcript_path` in every hook).
///
/// Answering No at Claude Code's permission prompt, or pressing Esc there, ends the turn without any hook (#8):
/// no Stop, no PostToolUseFailure, no Notification. The transcript still records it, as a user message
/// "[Request interrupted by user for tool use]" (Esc mid-turn: "[Request interrupted by user]") followed by a
/// `system` / `turn_duration` entry. Not a documented interface: if the format changes, sessions just stay put
/// until their next event, as before.
public enum ClaudeTranscript {
    public static let interruptMarker = "[Request interrupted by user"

    /// When the turn ended because the human interrupted it: the marker's time, if the transcript's last message
    /// is that marker; nil otherwise. `tail` is the end of the file, so a first line cut in the middle is skipped.
    /// Only `user` / `assistant` entries count as messages; meta entries and bookkeeping (system, attachment,
    /// file-history-snapshot, …) are skipped.
    public static func interruption(tail: String) -> Date? {
        for line in tail.split(whereSeparator: \.isNewline).reversed() {
            guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                  let type = object["type"] as? String, type == "user" || type == "assistant",
                  object["isMeta"] as? Bool != true else { continue }
            guard type == "user", isMarker(object["message"]) else { return nil }
            return (object["timestamp"] as? String).flatMap(date)
        }
        return nil
    }

    private static func isMarker(_ message: Any?) -> Bool {
        let content = (message as? [String: Any])?["content"]
        if let text = content as? String { return text.hasPrefix(interruptMarker) }
        guard let blocks = content as? [[String: Any]] else { return false }
        return blocks.contains { $0["type"] as? String == "text" && ($0["text"] as? String)?.hasPrefix(interruptMarker) == true }
    }

    private static func date(_ text: String) -> Date? {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
}
