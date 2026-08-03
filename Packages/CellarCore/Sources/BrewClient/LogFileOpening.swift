import Foundation

/// Opens a file in whatever the system uses to read logs.
///
/// A protocol boundary for an external dependency, per the project's design
/// rules: `NSWorkspace` is AppKit, and `BrewClient` is GUI-free. The **single**
/// real implementation lives in the app target; everything above this seam —
/// including the rule that a service declaring no log location offers nothing
/// to open — stays provable in the `swift test` loop.
///
/// Deliberately non-throwing and non-async. The caller is a button, and a
/// failure to open Console is not something the user can act on differently
/// from a Console that opened and showed an empty file.
public protocol LogFileOpening: Sendable {
    func open(_ url: URL)
}

/// Opens nothing. The default for previews, tests and any composition that has
/// no window to open one in.
public struct NoLogFileOpening: LogFileOpening {
    public init() {}
    public func open(_ url: URL) {}
}
