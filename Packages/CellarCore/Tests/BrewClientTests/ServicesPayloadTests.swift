import Foundation
import Testing

@testable import BrewClient
@testable import BrewProcess

/// What the two services reads actually spawn, and what they do with what comes
/// back.
///
/// Threat response — **subprocess argument composition**. The list probe is a
/// compile-time constant, so there is nothing to compose; the detail probe is
/// the codebase's *only* parameterised read argv, which is why its shape is
/// asserted element for element rather than by substring.
@Suite("Services payload acquisition")
struct ServicesPayloadTests {
    private func launcher(
        _ stdout: String = ServicesFixture.withNullUserAndExitCode
    ) -> RecordingProcessLauncher {
        RecordingProcessLauncher([ScriptedRun(stdout: stdout)])
    }

    // MARK: - SM1 — one invocation, exact argv

    @Test("One refresh records exactly one invocation with the exact argv")
    func oneRefreshRecordsExactlyOneInvocationWithTheExactArgv() async throws {
        let launcher = launcher()
        let source = ServicesListPayloadSource(launcher: launcher)

        let payload = try await source.payload(using: TestInstallation.appleSilicon)

        #expect(launcher.launchCount == 1, "a refresh spawned \(launcher.launchCount) processes")
        let spec = try #require(launcher.specs.first)
        #expect(spec.arguments == ["services", "list", "--json"])
        #expect(spec.executableURL == TestInstallation.appleSilicon.executableURL)
        // And the bytes really came back, so "one invocation" is not one
        // invocation that returned nothing.
        #expect(try ServicesDecoder.services(from: payload).map(\.name) == ["atuin"])
    }

    // MARK: - SM2 — the detail probe names one service and never uses --all

    @Test("The detail probe names exactly one service and never uses --all")
    func theDetailProbeNamesExactlyOneServiceAndNeverUsesAll() async throws {
        let launcher = launcher(ServicesFixture.infoWithIdenticalLogPaths)
        let source = ServiceInfoPayloadSource(launcher: launcher)
        let target = try #require(ServiceTarget(name: "atuin"))

        _ = try await source.payload(using: TestInstallation.appleSilicon, naming: target)

        #expect(launcher.launchCount == 1)
        let spec = try #require(launcher.specs.first)
        // The name is the last element and an element of its own — never
        // interpolated into one of the flags.
        #expect(spec.arguments == ["services", "info", "--json", "atuin"])
        #expect(spec.arguments.last == "atuin")
        #expect(spec.arguments.contains("--all") == false)
    }

    /// `--all` is what the cost probe used, and it is exactly what must not
    /// ship: the detail fetch is selection-keyed, so asking about every service
    /// would scale a lazy read with the service count.
    @Test("No services read this capability can build carries --all")
    func noServicesReadCarriesAll() async throws {
        let launcher = launcher()
        let listSource = ServicesListPayloadSource(launcher: launcher)
        let infoSource = ServiceInfoPayloadSource(launcher: launcher)

        _ = try await listSource.payload(using: TestInstallation.appleSilicon)
        for name in ["atuin", "postgresql", "redis"] {
            let target = try #require(ServiceTarget(name: name))
            _ = try? await infoSource.payload(
                using: TestInstallation.appleSilicon,
                naming: target
            )
        }

        #expect(launcher.specs.count == 4)
        for spec in launcher.specs {
            #expect(spec.arguments.contains("--all") == false)
        }
        #expect(
            launcher.specs.dropFirst().map(\.arguments.last) == ["atuin", "postgresql", "redis"]
        )
    }

    // MARK: - The payload rules, copied verbatim from InstalledPayload

    private func lines(stdout: [String] = [], stderr: [String] = []) -> [LogLine] {
        var log: [LogLine] = []
        for (index, text) in stdout.enumerated() {
            log.append(LogLine(stream: .stdout, text: text, sequence: index))
        }
        for (index, text) in stderr.enumerated() {
            log.append(
                LogLine(stream: .stderr, text: text, sequence: stdout.count + index)
            )
        }
        return log
    }

    /// brew failing while printing `[]` must never read as "the user has no
    /// services" — that is a list the UI would then happily show as empty.
    @Test("A non-zero exit is an error and never an empty list")
    func aNonZeroExitIsAnErrorAndNeverAnEmptyList() {
        let log = lines(stdout: ["[]"], stderr: ["Error: Cannot read services."])

        #expect(throws: ServicesError.commandFailed(status: 1, message: "Error: Cannot read services.")) {
            _ = try ServicesPayload.payload(
                from: log,
                exit: BrewExit(status: 1, reason: .exited)
            )
        }
    }

    /// Cancelled by *Cellar* is `.cancelled`. A process someone else signalled
    /// is a failure — the distinction is `BrewExit.Reason`'s, and reading it
    /// the other way would report a `brew` killed from Activity Monitor as a
    /// refresh the user asked to stop.
    @Test("A run Cellar cancelled is cancelled; one signalled from outside is a failure")
    func aCancelledRunIsCancelledNotAFailure() {
        #expect(throws: ServicesError.cancelled) {
            _ = try ServicesPayload.payload(
                from: lines(stdout: ["[]"]),
                exit: BrewExit(status: 128 + SIGINT, reason: .cancelled(signal: SIGINT))
            )
        }

        #expect(throws: ServicesError.commandFailed(status: 137, message: "")) {
            _ = try ServicesPayload.payload(
                from: lines(stdout: ["[]"]),
                exit: BrewExit(status: 137, reason: .signalled(SIGKILL))
            )
        }
    }

    /// Interleaved, not appended: a rule that only strips a trailing warning
    /// would pass a test that only ever puts one at the end.
    @Test("stderr never enters the document, at any position")
    func stderrNeverEntersTheDocument() throws {
        var log = lines(stdout: ["[", ServicesFixture.record(name: "atuin", status: "none"), "]"])
        log.insert(LogLine(stream: .stderr, text: "Warning: noise", sequence: 99), at: 1)

        let payload = try ServicesPayload.payload(
            from: log,
            exit: BrewExit(status: 0, reason: .exited)
        )

        let document = try #require(String(data: payload, encoding: .utf8))
        #expect(document.contains("Warning") == false, "stderr reached the document")
        #expect(try ServicesDecoder.services(from: payload).map(\.name) == ["atuin"])
    }

    @Test("A blank document is malformed, not an empty list")
    func aBlankDocumentIsMalformed() {
        for blank in [[], [""], ["   ", "\t"]] {
            #expect(throws: ServicesError.malformedPayload) {
                _ = try ServicesPayload.payload(
                    from: lines(stdout: blank),
                    exit: BrewExit(status: 0, reason: .exited)
                )
            }
        }
    }

    /// The same gate `PackageTarget` uses, so a services name can never reach
    /// argv through a second, weaker door.
    @Test("A name brew could read as an option is refused before any argv exists")
    func anUnsafeServiceNameIsRefusedBeforeAnyArgvExists() {
        for unsafe in ["-rf", "", " ", "two words", "--all", "\t"] {
            #expect(ServiceTarget(name: unsafe) == nil, "\(unsafe.debugDescription) was accepted")
        }
        // And the ordinary names brew genuinely publishes still pass.
        for safe in ["atuin", "postgresql@16", "unbound"] {
            #expect(ServiceTarget(name: safe)?.name == safe)
        }
    }
}
