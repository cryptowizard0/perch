import Foundation

/// How a tool permission request reads in the notch.
public enum PermissionPrompt {
    /// The input field that says what the tool will touch.
    public static func mainField(of tool: String) -> String {
        switch tool {
        case "Bash": return "command"
        case "Read", "Edit", "Write", "MultiEdit", "NotebookEdit": return "file_path"
        case "WebFetch": return "url"
        case "WebSearch": return "query"
        case "Glob", "Grep": return "pattern"
        default: return "command"
        }
    }

    /// The full text to show — never truncated: Bash shows the command itself, other tools "Tool value".
    public static func title(tool: String, input: [String: String]) -> String {
        let main = input[mainField(of: tool)] ?? ""
        switch tool {
        case "Bash": return main.isEmpty ? "Bash" : main
        case "Grep":
            let path = input["path"].map { " in \($0)" } ?? ""
            return "Grep \(main)\(path)"
        default:
            if !main.isEmpty { return "\(tool) \(main)" }
            let rest = input.filter { $0.key != "description" }.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
            return rest.isEmpty ? tool : "\(tool) \(rest.joined(separator: " "))"
        }
    }
}
