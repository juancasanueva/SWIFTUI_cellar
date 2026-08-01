import Foundation
import Testing

@testable import BrewProcess

@Suite("Verbatim line-oriented output streaming")
struct StreamingTests {
    /// Starts an operation against a scripted process and collects every line
    /// the runner produces once the process terminates.
    private func collect(
        _ script: (FakeProcess) -> Void
    ) async throws -> [LogLine] {
        let launcher = FakeProcessLauncher()
        let process = FakeProcess()
        launcher.enqueue(process)
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        let operation = try await runner.start(.read(["list"]))
        script(process)
        process.terminate(with: BrewExit(status: 0, reason: .exited))

        var lines: [LogLine] = []
        for await line in operation.lines { lines.append(line) }
        return lines
    }

    @Test("Leading whitespace, emoji, and ANSI bytes survive untouched")
    func lineContentIsPreservedExactly() async throws {
        let raw = "   ==> \u{1B}[1mDownloading\u{1B}[0m 🍺 ripgrep"

        let lines = try await collect { $0.emitStdout(raw + "\n") }

        #expect(lines.count == 1)
        #expect(lines.first?.text == raw)
        #expect(lines.first?.stream == .stdout)
    }

    @Test("A line split across two chunks is reassembled")
    func lineSplitAcrossChunksIsReassembled() async throws {
        let lines = try await collect { process in
            process.emitStdout("==> Pour")
            process.emitStdout("ing over 3 formulae\n")
        }

        #expect(lines.count == 1)
        #expect(lines.first?.text == "==> Pouring over 3 formulae")
    }

    @Test("A CRLF terminator is consumed, a bare carriage return is content")
    func carriageReturnHandling() async throws {
        let lines = try await collect { process in
            process.emitStdout("windows style\r\n")
            process.emitStdout("progress\rredrawn\n")
        }

        #expect(lines.map(\.text) == ["windows style", "progress\rredrawn"])
    }

    @Test("Output without a trailing newline still yields its final line")
    func missingTrailingNewlineIsFlushed() async throws {
        let lines = try await collect { $0.emitStdout("first\nno trailing newline") }

        #expect(lines.map(\.text) == ["first", "no trailing newline"])
    }

    @Test("An empty line between two lines is preserved, not collapsed")
    func blankLinesArePreserved() async throws {
        let lines = try await collect { $0.emitStdout("a\n\nb\n") }

        #expect(lines.map(\.text) == ["a", "", "b"])
    }

    @Test("stdout and stderr stay distinguishable and keep read order")
    func streamsAreTaggedAndInterleavedInReadOrder() async throws {
        let lines = try await collect { process in
            process.emitStdout("a\n")
            process.emitStderr("b\n")
            process.emitStdout("c\n")
        }

        #expect(lines.tagged == [(.stdout, "a"), (.stderr, "b"), (.stdout, "c")])
    }

    @Test("Sequence numbers are globally monotonic across both streams")
    func sequenceIsMonotonic() async throws {
        let lines = try await collect { process in
            process.emitStdout("a\n")
            process.emitStderr("b\n")
            process.emitStdout("c\n")
        }

        #expect(lines.map(\.sequence) == [0, 1, 2])
    }

    @Test("The stream finishes once after termination and yields nothing more")
    func streamFinishesAfterTermination() async throws {
        let launcher = FakeProcessLauncher()
        let process = FakeProcess()
        launcher.enqueue(process)
        let runner = BrewRunner(installation: .fixture, launcher: launcher)

        let operation = try await runner.start(.read(["list"]))
        process.emitStdout("only line\n")
        process.terminate(with: BrewExit(status: 0, reason: .exited))

        var lines: [LogLine] = []
        for await line in operation.lines { lines.append(line) }
        #expect(lines.map(\.text) == ["only line"])

        // Iterating an already-finished stream must complete immediately and
        // deliver nothing: the finish happened exactly once.
        var afterFinish: [LogLine] = []
        for await line in operation.lines { afterFinish.append(line) }
        #expect(afterFinish.isEmpty)
    }
}
