import Foundation

/// Turns arbitrary byte chunks into whole `LogLine` values.
///
/// Pure, synchronous, and stream-aware: each pipe keeps its own partial-line
/// buffer, so a line split across chunk boundaries is reassembled, while the
/// two pipes never contaminate each other. Line splitting lives here rather
/// than in a readability callback precisely so it can be tested directly
/// (design decision D2).
///
/// Only the line terminator is removed — `\n`, or the `\r\n` pair. Everything
/// else, including a bare `\r` used for progress redraws, ANSI escapes, and
/// leading whitespace, is preserved verbatim (D7).
struct LineSplitter {
    private var stdoutBuffer = Data()
    private var stderrBuffer = Data()
    private var nextSequence = 0

    private static let newline = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")

    /// Emits every complete line contained in `chunk`, buffering any remainder.
    mutating func consume(_ chunk: OutputChunk) -> [LogLine] {
        switch chunk {
        case .stdout(let data):
            return split(data, stream: .stdout)
        case .stderr(let data):
            return split(data, stream: .stderr)
        }
    }

    /// Emits whatever is still buffered, for output that ended without a
    /// trailing newline. Call once, after the source stream finishes.
    mutating func flush() -> [LogLine] {
        var lines: [LogLine] = []
        if !stdoutBuffer.isEmpty {
            lines.append(makeLine(from: stdoutBuffer, stream: .stdout))
            stdoutBuffer.removeAll()
        }
        if !stderrBuffer.isEmpty {
            lines.append(makeLine(from: stderrBuffer, stream: .stderr))
            stderrBuffer.removeAll()
        }
        return lines
    }

    private mutating func split(_ data: Data, stream: LogLine.Stream) -> [LogLine] {
        var buffer = buffer(for: stream)
        buffer.append(data)

        var lines: [LogLine] = []
        while let newlineIndex = buffer.firstIndex(of: Self.newline) {
            var lineBytes = buffer[buffer.startIndex..<newlineIndex]
            if lineBytes.last == Self.carriageReturn {
                lineBytes = lineBytes.dropLast()
            }
            lines.append(makeLine(from: lineBytes, stream: stream))
            buffer.removeSubrange(buffer.startIndex...newlineIndex)
        }

        setBuffer(buffer, for: stream)
        return lines
    }

    private func buffer(for stream: LogLine.Stream) -> Data {
        switch stream {
        case .stdout: stdoutBuffer
        case .stderr: stderrBuffer
        }
    }

    private mutating func setBuffer(_ buffer: Data, for stream: LogLine.Stream) {
        switch stream {
        case .stdout: stdoutBuffer = buffer
        case .stderr: stderrBuffer = buffer
        }
    }

    private mutating func makeLine(
        from bytes: some Collection<UInt8>,
        stream: LogLine.Stream
    ) -> LogLine {
        defer { nextSequence += 1 }
        return LogLine(
            stream: stream,
            text: String(decoding: bytes, as: UTF8.self),
            sequence: nextSequence
        )
    }
}
