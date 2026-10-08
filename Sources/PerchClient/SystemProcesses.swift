import Darwin
import Foundation
import PerchCore

/// Live processes, read with sysctl (no subprocess). `perch hook` walks its ancestors to find its agent
/// (`AgentProcess`); perchd asks whether a session's agent is still alive.
/// Zombies (exited, not yet reaped) count as gone. Start times are whole seconds, like every date perchd stores.
public enum SystemProcesses {
    /// `pid` and its ancestors up to launchd, keyed by pid: the table `AgentProcess.find` walks.
    public static func ancestors(of pid: Int32) -> [Int32: ProcessEntry] {
        var table: [Int32: ProcessEntry] = [:]
        var next = pid
        while next > 0, table[next] == nil, table.count < 64, let entry = entry(pid: next) {
            table[next] = entry
            next = entry.ppid
        }
        return table
    }

    /// The process with this pid, named after its argv[0] (see `ProcessEntry.name`), or nil if there is none.
    public static func entry(pid: Int32) -> ProcessEntry? {
        guard var entry = kernelEntry(pid: pid) else { return nil }
        if let argv0 = argv0(pid: pid) { entry.name = argv0 }
        return entry
    }

    /// When `pid` started, or nil if there is no such (live) process. perchd's liveness probe.
    /// The file the process runs (symlinks resolved), or nil if it is gone.
    public static func executablePath(of pid: Int32) -> String? {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        let length = proc_pidpath(pid, &buffer, UInt32(buffer.count))
        return length > 0 ? String(cString: buffer) : nil
    }

    public static func startTime(of pid: Int32) -> Date? {
        kernelEntry(pid: pid)?.startedAt
    }

    /// Named by the kernel's short name, which is the executable's real file name (`bash` for a symlink to it).
    private static func kernelEntry(pid: Int32) -> ProcessEntry? {
        guard pid > 0 else { return nil }
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_PID, pid]
        var info = kinfo_proc()
        var size = MemoryLayout<kinfo_proc>.stride
        guard sysctl(&mib, u_int(mib.count), &info, &size, nil, 0) == 0, size > 0 else { return nil }
        let proc = info.kp_proc
        guard proc.p_pid == pid, proc.p_stat != SZOMB else { return nil }
        let name = withUnsafeBytes(of: proc.p_comm) { String(decoding: $0.prefix { $0 != 0 }, as: UTF8.self) }
        return ProcessEntry(pid: pid, ppid: info.kp_eproc.e_ppid, name: name,
                            startedAt: Date(timeIntervalSince1970: TimeInterval(proc.p_un.__p_starttime.tv_sec)))
    }

    /// The last path component of argv[0]. Only readable for this user's processes.
    /// KERN_PROCARGS2 is `argc`, the exec path, NUL padding, then argv.
    private static func argv0(pid: Int32) -> String? {
        var mib: [Int32] = [CTL_KERN, KERN_PROCARGS2, pid]
        var size = 0
        guard sysctl(&mib, u_int(mib.count), nil, &size, nil, 0) == 0, size > MemoryLayout<Int32>.size else { return nil }
        var buffer = [UInt8](repeating: 0, count: size)
        guard sysctl(&mib, u_int(mib.count), &buffer, &size, nil, 0) == 0 else { return nil }
        var rest = buffer.prefix(size).dropFirst(MemoryLayout<Int32>.size)
        rest = rest.drop { $0 != 0 }.drop { $0 == 0 }
        let arg = rest.prefix { $0 != 0 }
        guard !arg.isEmpty else { return nil }
        let name = String(decoding: arg, as: UTF8.self).split(separator: "/").last.map(String.init)
        return name?.isEmpty == false ? name : nil
    }
}
