public enum SavingsEstimate {
    static let blockSize: Int64 = 4096
    static let chunkSize: Int64 = 65_536
    static let headerBytes: Int64 = 256

    /// Measured against afsctool's LZFSE output on APFS: the compressed chunks, a
    /// small header and an 8-byte-per-chunk table round up to whole 4 KB blocks, and
    /// never fewer than one, so a file of 4 KB or less never gets smaller on disk.
    public static func allocatedAfter(logicalBytes: Int64, ratio: Double) -> Int64 {
        let chunks = (logicalBytes + chunkSize - 1) / chunkSize
        let stored = Int64((Double(logicalBytes) * ratio).rounded(.up)) + headerBytes + 8 * chunks
        return max(blockSize, (stored + blockSize - 1) / blockSize * blockSize)
    }

    public static func savedBytes(allocatedBefore: Int64, logicalBytes: Int64, ratio: Double) -> Int64 {
        allocatedBefore - allocatedAfter(logicalBytes: logicalBytes, ratio: ratio)
    }
}
