import Foundation

@testable import BrewProcess

extension BrewInstallation {
    /// A stand-in installation for runner tests that never touch the disk.
    static let fixture = BrewInstallation(
        executableURL: URL(fileURLWithPath: "/opt/homebrew/bin/brew"),
        prefix: .appleSilicon,
        version: BrewVersion(major: 4, minor: 2, patch: 0),
        advisories: []
    )
}

extension Sequence where Element == LogLine {
    /// `(stream, text)` pairs, for compact order assertions.
    var tagged: [(LogLine.Stream, String)] { map { ($0.stream, $0.text) } }
}

func == (lhs: [(LogLine.Stream, String)], rhs: [(LogLine.Stream, String)]) -> Bool {
    lhs.count == rhs.count && zip(lhs, rhs).allSatisfy { $0.0 == $1.0 && $0.1 == $1.1 }
}
