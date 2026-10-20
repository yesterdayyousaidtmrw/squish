import CoreServices
import Foundation

public protocol ActivityProbe {
    /// Latest of Spotlight's last-opened and date-added, or nil when Spotlight has neither.
    func spotlightActivity(of url: URL) -> Date?
}

public struct SpotlightActivityProbe: ActivityProbe {
    public init() {}

    public func spotlightActivity(of url: URL) -> Date? {
        guard let item = MDItemCreateWithURL(kCFAllocatorDefault, url as CFURL) else { return nil }
        return [kMDItemLastUsedDate, kMDItemDateAdded]
            .compactMap { MDItemCopyAttribute(item, $0) as? Date }
            .max()
    }
}
