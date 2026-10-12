/// A setup failure with one human-readable line (the CLI prints it as `perch: <message>`). Exit code 1 unless stated.
public struct SetupError: Error, CustomStringConvertible, Equatable {
    public let message: String
    public var code: Int32 = 1
    public init(_ message: String, code: Int32 = 1) {
        self.message = message
        self.code = code
    }
    public var description: String { message }
}
