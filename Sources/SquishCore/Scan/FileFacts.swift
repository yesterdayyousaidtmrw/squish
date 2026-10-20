import Darwin
import Foundation

public struct FileFacts: Equatable {
    public let isRegularFile: Bool
    public let isDirectory: Bool
    public let isCompressed: Bool
    public let linkCount: Int
    public let inode: UInt64
    public let logicalBytes: Int64
    public let allocatedBytes: Int64
    public let modified: Date
    public let accessed: Date

    /// lstat, so a symlink is reported as itself and never followed.
    public static func read(_ url: URL) throws -> FileFacts {
        var info = stat()
        guard lstat(url.path, &info) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
        let type = info.st_mode & S_IFMT
        return FileFacts(
            isRegularFile: type == S_IFREG,
            isDirectory: type == S_IFDIR,
            isCompressed: info.st_flags & UInt32(UF_COMPRESSED) != 0,
            linkCount: Int(info.st_nlink),
            inode: info.st_ino,
            logicalBytes: Int64(info.st_size),
            allocatedBytes: Int64(info.st_blocks) * 512,
            modified: date(info.st_mtimespec),
            accessed: date(info.st_atimespec)
        )
    }

    private static func date(_ time: timespec) -> Date {
        Date(timeIntervalSince1970: Double(time.tv_sec) + Double(time.tv_nsec) / 1_000_000_000)
    }
}
