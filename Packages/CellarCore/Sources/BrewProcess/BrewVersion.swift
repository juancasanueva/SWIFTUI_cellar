/// A Homebrew semantic version triple.
public struct BrewVersion: Sendable, Equatable, Comparable {
    public let major: Int
    public let minor: Int
    public let patch: Int

    public init(major: Int, minor: Int, patch: Int) {
        self.major = major
        self.minor = minor
        self.patch = patch
    }

    public static func < (lhs: BrewVersion, rhs: BrewVersion) -> Bool {
        (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
    }

    /// Parses the output of `brew --version`.
    ///
    /// Pure and total: any output that is not genuine Homebrew — another tool's
    /// version banner, arbitrary noise, nothing at all — yields `nil`, which is
    /// what lets detection reject an impostor without running anything else.
    ///
    /// Recognized shapes, on the first line: `Homebrew 4.0.0`,
    /// `Homebrew 4.2` (patch defaults to 0), and development builds such as
    /// `Homebrew 6.0.14-38-g1f3abf4`, whose git suffix is dropped.
    public static func parse(_ brewVersionOutput: String) -> BrewVersion? {
        guard let firstLine = brewVersionOutput.split(
            separator: "\n",
            omittingEmptySubsequences: false
        ).first else { return nil }

        let fields = firstLine.split(separator: " ", omittingEmptySubsequences: true)
        guard fields.count >= 2, fields[0] == "Homebrew" else { return nil }

        // Everything from the first `-` onwards is a development-build suffix.
        let numeric = fields[1].prefix { $0 != "-" }
        let components = numeric.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(components.count) else { return nil }

        let numbers = components.compactMap { Int($0) }
        guard numbers.count == components.count else { return nil }

        return BrewVersion(
            major: numbers[0],
            minor: numbers[1],
            patch: numbers.count == 3 ? numbers[2] : 0
        )
    }
}
