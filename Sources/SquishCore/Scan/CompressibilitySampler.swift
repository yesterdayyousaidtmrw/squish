import Compression
import Darwin
import Foundation

public protocol CompressibilityProbe {
    /// Compressed size over original size for a sample of the file: 0.3 means it
    /// shrinks to 30%, 1 means it does not shrink at all.
    func compressedRatio(of url: URL, accessed: Date) throws -> Double
}

/// Compresses the first 64 KB in memory with LZFSE, the same chunk size and
/// algorithm afsctool writes, so the ratio carries over to the whole file.
public struct LZFSESampler: CompressibilityProbe {
    static let sampleBytes = 65_536

    public init() {}

    public func compressedRatio(of url: URL, accessed: Date) throws -> Double {
        let handle = try FileHandle(forReadingFrom: url)
        let sample = try handle.read(upToCount: Self.sampleBytes) ?? Data()
        try handle.close()
        // Reading bumped the access time; put it back so sampling a file does not
        // make it look freshly used to the next scan.
        try restoreAccessTime(of: url, to: accessed)
        guard !sample.isEmpty else { return 1 }

        var output = [UInt8](repeating: 0, count: sample.count)
        let compressedSize = sample.withUnsafeBytes { input in
            compression_encode_buffer(
                &output, output.count,
                input.bindMemory(to: UInt8.self).baseAddress!, sample.count,
                nil, COMPRESSION_LZFSE
            )
        }
        // 0 means the result did not fit in the input's size: it does not shrink.
        guard compressedSize > 0 else { return 1 }
        return Double(compressedSize) / Double(sample.count)
    }

    private func restoreAccessTime(of url: URL, to date: Date) throws {
        let seconds = date.timeIntervalSince1970.rounded(.down)
        var times = [
            timespec(tv_sec: Int(seconds), tv_nsec: Int((date.timeIntervalSince1970 - seconds) * 1_000_000_000)),
            timespec(tv_sec: 0, tv_nsec: Int(UTIME_OMIT)),
        ]
        guard utimensat(AT_FDCWD, url.path, &times, AT_SYMLINK_NOFOLLOW) == 0 else {
            throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)
        }
    }
}
