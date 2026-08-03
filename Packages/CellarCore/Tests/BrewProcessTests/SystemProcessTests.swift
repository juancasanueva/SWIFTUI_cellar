import Foundation
import Testing

@testable import BrewProcess

/// Integration coverage for the real `Foundation.Process` bridge. These use
/// system binaries that exist on every macOS install, so they never skip.
@Suite("SystemProcess bridges Foundation.Process")
struct SystemProcessTests {
    private func installation(at path: String) -> BrewInstallation {
        BrewInstallation(
            executableURL: URL(fileURLWithPath: path),
            prefix: .custom(URL(fileURLWithPath: path)),
            version: BrewVersion(major: 4, minor: 0, patch: 0)
        )
    }

    @Test("A real /bin/echo run streams its line and exits 0")
    func echoStreamsOneLineAndExitsZero() async throws {
        let runner = BrewRunner(
            installation: installation(at: "/bin/echo"),
            launcher: SystemProcessLauncher()
        )

        let operation = try await runner.start(.read(["hello from cellar"]))

        var lines: [LogLine] = []
        for await line in operation.lines { lines.append(line) }
        let exit = await operation.exit()

        #expect(lines.map(\.text) == ["hello from cellar"])
        #expect(lines.first?.stream == .stdout)
        #expect(lines.first?.sequence == 0)
        #expect(exit == BrewExit(status: 0, reason: .exited))
    }

    @Test("Multi-line real output keeps its order and sequence")
    func multiLineOutputIsOrdered() async throws {
        let runner = BrewRunner(
            installation: installation(at: "/bin/echo"),
            launcher: SystemProcessLauncher()
        )

        let operation = try await runner.start(.read(["one\ntwo\nthree"]))

        var lines: [LogLine] = []
        for await line in operation.lines { lines.append(line) }
        _ = await operation.exit()

        #expect(lines.map(\.text) == ["one", "two", "three"])
        #expect(lines.map(\.sequence) == [0, 1, 2])
    }

    @Test("A real non-zero exit is reported as a result, not an error")
    func nonZeroExitFromRealBinary() async throws {
        let runner = BrewRunner(
            installation: installation(at: "/usr/bin/false"),
            launcher: SystemProcessLauncher()
        )

        let operation = try await runner.start(.read([]))
        for await _ in operation.lines {}
        let exit = await operation.exit()

        #expect(exit == BrewExit(status: 1, reason: .exited))
    }

    @Test("Cancelling a real /bin/sleep delivers SIGINT and reports cancelled", .timeLimit(.minutes(1)))
    func realCancellationDeliversInterrupt() async throws {
        let runner = BrewRunner(
            installation: installation(at: "/bin/sleep"),
            launcher: SystemProcessLauncher()
        )

        let operation = try await runner.start(.read(["30"]))
        await operation.cancel()
        let exit = await operation.exit()

        #expect(exit.reason == .cancelled(signal: SIGINT))
        #expect(exit.isCancelled)
        #expect(await operation.fault() == nil)
    }

    // MARK: - SM7 sc3, PM4 sc2, PM4 sc5 — standard input is never interactive

    /// The identity of `/dev/null` on this machine, read through the same
    /// `stat(2)` the child reports from.
    ///
    /// Compared by **inode**, not by a device class: every character device
    /// would answer "Character Device", so a type-only assertion would pass with
    /// stdin wired to a terminal — which is the one thing it must catch.
    private static func inode(of path: String) throws -> Int {
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        return try #require(attributes[.systemFileNumber] as? Int)
    }

    /// `stat -f "%i %HT" /dev/fd/0` makes the child report what its own standard
    /// input actually is, so this is a runtime observation of the spawned
    /// process rather than a source scan or a structural claim.
    private func reportedStandardInput(kind: BrewCommand.Kind) async throws -> (text: [String], exit: BrewExit) {
        let runner = BrewRunner(
            installation: installation(at: "/usr/bin/stat"),
            launcher: SystemProcessLauncher()
        )
        let arguments = ["-f", "%i %HT", "/dev/fd/0"]
        let command = kind == .mutate ? BrewCommand.mutate(arguments) : .read(arguments)

        let operation = try await runner.start(command)
        var lines: [LogLine] = []
        for await line in operation.lines { lines.append(line) }
        return (lines.map(\.text), await operation.exit())
    }

    /// Cellar can give brew nothing to type, so brew must never be able to ask.
    /// A password prompt, a `[y/N]` confirmation or a pager would otherwise hang
    /// the operation with no visible cause and no way out.
    @Test(
        "A spawned read reports its own standard input as the null device",
        .timeLimit(.minutes(1))
    )
    func aSpawnedReadReportsTheNullDeviceAsItsStandardInput() async throws {
        let null = try Self.inode(of: "/dev/null")
        let reported = try await reportedStandardInput(kind: .read)

        #expect(reported.exit == BrewExit(status: 0, reason: .exited))
        #expect(reported.text == ["\(null) Character Device"])
    }

    /// PM4 sc5: a **non-package** operation — every `brew services` verb — runs
    /// through this same seam, so it inherits the same guarantee rather than
    /// restating it. `.mutate` is the kind every service verb lowers to.
    @Test(
        "A spawned mutation reports the same null device, so a non-package verb is no different",
        .timeLimit(.minutes(1))
    )
    func aSpawnedMutationReportsTheSameNullDevice() async throws {
        let null = try Self.inode(of: "/dev/null")
        let reported = try await reportedStandardInput(kind: .mutate)

        #expect(reported.exit == BrewExit(status: 0, reason: .exited))
        #expect(reported.text == ["\(null) Character Device"])
    }

    /// The discriminator is the inode, and the inode really does discriminate:
    /// `/dev/zero` is also a character device and is a different file, so the
    /// assertion above cannot be satisfied by "some character device".
    @Test("The null device is identified by inode, which no other character device shares")
    func theNullDeviceIsIdentifiedByInodeNotByBeingACharacterDevice() throws {
        let null = try Self.inode(of: "/dev/null")
        let zero = try Self.inode(of: "/dev/zero")

        #expect(null != zero)
    }

    @Test("Spawning a path that does not exist reports executableUnavailable")
    func missingBinaryReportsUnavailable() async {
        let missing = "/opt/homebrew/bin/definitely-not-a-real-binary"
        let runner = BrewRunner(
            installation: installation(at: missing),
            launcher: SystemProcessLauncher()
        )

        await #expect(throws: BrewProcessError.executableUnavailable(URL(fileURLWithPath: missing))) {
            _ = try await runner.start(.read([]))
        }
    }
}
