/// A single line of output produced by a `brew` invocation.
///
/// The text is **verbatim**: `BrewProcess` never trims, re-encodes, normalizes,
/// prefixes, or annotates what the subprocess wrote. Presentation concerns
/// belong to a later layer (design decision D7).
public struct LogLine: Sendable, Equatable {
    /// Which of the process's two output pipes produced the line.
    public enum Stream: Sendable, Equatable {
        case stdout
        case stderr
    }

    /// The pipe the line arrived on.
    public let stream: Stream

    /// The line's content, without its terminating newline, byte-identical to
    /// what the process emitted.
    public let text: String

    /// Global, strictly increasing emission index.
    ///
    /// Invariant I4: `sequence` orders lines *within* a stream strictly. Across
    /// stdout and stderr it reflects chunk-arrival order only — two pipes carry
    /// no OS-level ordering guarantee.
    public let sequence: Int

    public init(stream: Stream, text: String, sequence: Int) {
        self.stream = stream
        self.text = text
        self.sequence = sequence
    }
}
