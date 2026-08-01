/// How long a cancelled `brew` process is given to stop at each escalation
/// step.
///
/// Escalation deliberately stops at `SIGTERM` (design decision D4): `SIGKILL`
/// would leave a stale brew lock and a half-linked keg behind, so an
/// unresponsive process is surfaced rather than killed.
public struct CancellationPolicy: Sendable, Equatable {
    /// Time allowed after `SIGINT` before escalating to `SIGTERM`.
    public var interruptGrace: Duration
    /// Time allowed after `SIGTERM` before the process is declared unresponsive.
    public var terminateGrace: Duration

    public init(interruptGrace: Duration, terminateGrace: Duration) {
        self.interruptGrace = interruptGrace
        self.terminateGrace = terminateGrace
    }

    public static let `default` = CancellationPolicy(
        interruptGrace: .seconds(3),
        terminateGrace: .seconds(2)
    )

    /// Total budget spent before an unresponsive process is reported.
    public var totalGrace: Duration { interruptGrace + terminateGrace }
}
