import Darwin
import Foundation

public protocol OpenFileProbe {
    /// Real paths of files some process has open right now.
    func openPaths() throws -> Set<String>
}

/// One pass over every process's open files, taken once per scan or batch.
/// proc_listpidspath answers for a single path but walks every process to do
/// it: measured at ~190 ms per call, minutes over a few thousand candidates.
///
/// Without root only the user's own processes can be inspected, and those are
/// the ones that hold a user's files open; others are passed over by design.
public struct LibprocOpenFiles: OpenFileProbe {
    public init() {}

    public func openPaths() throws -> Set<String> {
        var paths = Set<String>()
        for pid in try allProcessIDs() {
            for descriptor in fileDescriptors(of: pid) where descriptor.proc_fdtype == UInt32(PROX_FDTYPE_VNODE) {
                var info = vnode_fdinfowithpath()
                let size = Int32(MemoryLayout<vnode_fdinfowithpath>.size)
                // A descriptor closed since it was listed is simply no longer open.
                guard proc_pidfdinfo(pid, descriptor.proc_fd, PROC_PIDFDVNODEPATHINFO, &info, size) == size else { continue }
                // Event-only opens (Spotlight, editors and sync tools watching a
                // folder) never read or write the file.
                if Int32(bitPattern: info.pfi.fi_openflags) & O_EVTONLY != 0 { continue }
                paths.insert(withUnsafeBytes(of: info.pvip.vip_path) { String(cString: $0.bindMemory(to: CChar.self).baseAddress!) })
            }
        }
        return paths
    }

    private func allProcessIDs() throws -> [pid_t] {
        let estimate = proc_listallpids(nil, 0)
        guard estimate > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        var pids = [pid_t](repeating: 0, count: Int(estimate) + 64)
        let count = proc_listallpids(&pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard count > 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        return Array(pids.prefix(Int(count)))
    }

    /// Empty for a process this user may not inspect, or one that has exited.
    private func fileDescriptors(of pid: pid_t) -> [proc_fdinfo] {
        let bytes = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, nil, 0)
        guard bytes > 0 else { return [] }
        let stride = MemoryLayout<proc_fdinfo>.stride
        var descriptors = [proc_fdinfo](repeating: proc_fdinfo(), count: Int(bytes) / stride + 16)
        let filled = proc_pidinfo(pid, PROC_PIDLISTFDS, 0, &descriptors, Int32(descriptors.count * stride))
        guard filled > 0 else { return [] }
        return Array(descriptors.prefix(Int(filled) / stride))
    }
}
