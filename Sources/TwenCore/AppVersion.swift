import Foundation

/// A dotted numeric version ("0.1.0"), parsed leniently from release tags:
/// an optional leading "v" is dropped, so "v0.2.0" and "0.2.0" compare equal.
/// Anything with a non-numeric component (pre-release suffixes like "-beta1")
/// fails to parse — the update check should ignore such tags, not guess.
public struct AppVersion: Comparable, Equatable, CustomStringConvertible {
    public let components: [Int]

    public init?(_ string: String) {
        var body = Substring(string)
        if body.first == "v" { body = body.dropFirst() }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard !parts.isEmpty else { return nil }
        var components: [Int] = []
        for part in parts {
            guard let value = Int(part), value >= 0 else { return nil }
            components.append(value)
        }
        self.components = components
    }

    /// Missing trailing components count as zero, so "1.2" == "1.2.0".
    public static func < (lhs: AppVersion, rhs: AppVersion) -> Bool {
        let count = max(lhs.components.count, rhs.components.count)
        for i in 0..<count {
            let l = i < lhs.components.count ? lhs.components[i] : 0
            let r = i < rhs.components.count ? rhs.components[i] : 0
            if l != r { return l < r }
        }
        return false
    }

    public static func == (lhs: AppVersion, rhs: AppVersion) -> Bool {
        !(lhs < rhs) && !(rhs < lhs)
    }

    public var description: String { components.map(String.init).joined(separator: ".") }
}
