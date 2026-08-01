# Design: M1 — CellarCore foundation, BrewRunner actor, brew detection

**Artifact store**: hybrid — Engram `sdd/m1-brewrunner-core/design`.

## Technical Approach

Four ordered slices: (P0) settings-only Xcode migration → (P1) `Packages/CellarCore` with a single
`BrewProcess` target → (P2) `actor BrewRunner` over an injectable process seam → (P3) brew detection
+ observable state → (P4) thin app wiring. Everything in P2–P3 is `swift test`-able with no Xcode,
GUI, or real `brew`. Two isolation domains: the **app target** keeps `SWIFT_DEFAULT_ACTOR_ISOLATION
= MainActor`; **CellarCore** uses SwiftPM's default `nonisolated` so core types must earn their
isolation explicitly.

## Architecture Decisions

| # | Decision | Chosen | Rejected | Rationale |
|---|---|---|---|---|
| D1 | Process bridge | `SystemProcess`: `final class` whose only stored state is `Mutex<State>` (`import Synchronization`); two `readabilityHandler`s yield to **one** `AsyncStream<OutputChunk>` continuation | `@unchecked Sendable` on the runner or on scattered boxes; `DispatchQueue` + callback API | `Mutex` is the sanctioned confinement for a non-`Sendable` `Process`; the class is `Sendable` with **zero** `@unchecked`. One continuation, one `finish()` when both pipes EOF **and** the process reaped |
| D2 | Two-layer streaming | Raw `AsyncStream<OutputChunk>` (bytes, arrival-ordered) → actor-owned pump `Task` → `AsyncStream<LogLine>` (split, tagged, sequenced) | Split lines inside the readability handler | Line splitting is pure logic and belongs in tested actor code, not in a callback that cannot be faked |
| D3 | Exit is not an error | Non-zero status returns `BrewExit`; only launch/signal faults `throw` | `throw` on non-zero exit | brew uses exit codes semantically; a cancelled op must report *cancelled*, not failure (success criterion) |
| D4 | Escalation stops at SIGTERM | SIGINT → grace → SIGTERM → grace → `.cancelledUnresponsive` | escalate to SIGKILL | SIGKILL leaves a stale brew lock and a half-linked keg; surfacing "unresponsive" is an M2 UX decision |
| D5 | Serialization | FIFO gate: `.mutate` awaits the previous mutation's gate task; `.read` bypasses it entirely | `OperationQueue`; one global serial actor | Tail is assigned **synchronously before the first `await`**, so actor reentrancy cannot reorder the queue — a documented invariant, testable with fakes |
| D6 | Detection strictness | Auto-probed standard paths *fall through* on failure; a user-configured path *never* falls through — it reports `.invalid` | Silent fallback to `/opt/homebrew` | A silently ignored custom path is a support nightmare; strictness is only correct where the user made a choice |
| D7 | Verbatim core | No trimming, ANSI stripping, or dedup in `BrewProcess`; env pins `HOMEBREW_COLOR=0`/`NO_EMOJI=1` at the source | Normalize on the way out | Presentation is a later layer's job; verbatim keeps the log copy-pasteable and the tests exact |
| D8 | App sandbox off | `ENABLE_APP_SANDBOX = YES → NO` | Keep sandbox, add temporary-exception entitlements | The template ships sandboxed; a sandboxed app can neither stat `/opt/homebrew/bin/brew` nor spawn it, so P4 would report `.absent` on every machine. PRD §4.2 requires sandbox off |

## Data Flow

    BrewCommand ─▶ BrewRunner (actor) ─▶ ProcessLaunching ─▶ SystemProcess
       .read bypasses gate │                                  ├ stdout handler ┐
       .mutate ─▶ FIFO gate│                                  ├ stderr handler ┤─▶ 1 continuation
                           │◀──── AsyncStream<OutputChunk> ◀──┴ Mutex<State> ──┘
                    pump Task: buffer → split \n → tag stream → seq++
                           ├──▶ AsyncStream<LogLine>   (consumer)
                           └──▶ waitForExit() ─▶ BrewExit(status, reason)

## Interfaces / Contracts

```swift
// —— Values
public struct LogLine: Sendable, Equatable {
    public enum Stream: Sendable, Equatable { case stdout, stderr }
    public let stream: Stream, text: String, sequence: Int   // text verbatim, sequence global+monotonic
}
public struct BrewCommand: Sendable, Equatable {
    public enum Kind: Sendable { case read, mutate }
    public let arguments: [String], kind: Kind               // argv only — never a shell string
}
public struct BrewExit: Sendable, Equatable {
    public enum Reason: Sendable, Equatable { case exited, cancelled(signal: Int32), signalled(Int32) }
    public let status: Int32, reason: Reason
}

// —— Process seam (the fake point)
public struct ProcessSpec: Sendable { public let executableURL: URL, arguments: [String], environment: [String: String] }
public enum OutputChunk: Sendable { case stdout(Data), stderr(Data) }
public enum ProcessSignal: Sendable { case interrupt, terminate }        // SIGINT, SIGTERM
public protocol ProcessLaunching: Sendable { func launch(_ spec: ProcessSpec) throws -> any LaunchedProcess }
public protocol LaunchedProcess: Sendable, AnyObject {
    var output: AsyncStream<OutputChunk> { get }
    func send(_ signal: ProcessSignal) throws
    func waitForTermination() async -> BrewExit
}
public struct SystemProcessLauncher: ProcessLaunching { public init() }  // Foundation.Process

// —— Runner
public actor BrewRunner {
    public init(installation: BrewInstallation,
                launcher: any ProcessLaunching = SystemProcessLauncher(),
                policy: CancellationPolicy = .default,
                clock: any Clock<Duration> = ContinuousClock())
    public func start(_ command: BrewCommand) async throws(BrewProcessError) -> BrewOperation
    public func cancel(_ id: BrewOperation.ID) async
}
public struct BrewOperation: Sendable, Identifiable {
    public let id: UUID
    public let lines: AsyncStream<LogLine>
    public func exit() async -> BrewExit                     // never throws: cancellation is a Reason
    public func cancel() async
}
public struct CancellationPolicy: Sendable {                 // .default = 3s / 2s
    public var interruptGrace: Duration, terminateGrace: Duration
}

// —— Detection
public enum BrewPrefix: Sendable, Equatable { case appleSilicon, intelCarryOver, custom(URL) }
public struct BrewVersion: Sendable, Equatable, Comparable {
    public let major: Int, minor: Int, patch: Int
    public static func parse(_ brewVersionOutput: String) -> BrewVersion?   // pure
}
public struct BrewInstallation: Sendable, Equatable {
    public let executableURL: URL, prefix: BrewPrefix, version: BrewVersion
    public let advisories: Set<Advisory>                     // .rosettaPrefix
}
public enum BrewDetectionState: Sendable, Equatable {
    case detected(BrewInstallation), invalid(URL, BrewValidationError)
    case configuredPathMissing(URL), absent                  // absent = soft signal, gates nothing
}
public protocol BrewLocating: Sendable { func detect(configuredPath: URL?) async -> BrewDetectionState }
public struct DefaultBrewLocator: BrewLocating {             // probes /opt/homebrew → /usr/local
    public init(probe: any ExecutableProbing = DefaultExecutableProbe(), launcher: any ProcessLaunching = SystemProcessLauncher())
}
public protocol ExecutableProbing: Sendable { func isExecutableRegularFile(at url: URL) -> Bool }

@MainActor @Observable public final class BrewDetectionStore {  // single-flight refresh()
    public private(set) var state: BrewDetectionState
    public func refresh() async                                  // launch • app-became-active • configured path vanished
}
```

**Error taxonomy** — `BrewProcessError`: `.executableUnavailable(URL)` (ENOENT/EACCES at launch),
`.launchFailed(URL, code: Int32)`, `.cancelledUnresponsive(after: Duration)`.
`BrewValidationError`: `.notExecutable(URL)`, `.notHomebrew(URL, output: String)`,
`.versionTooOld(BrewVersion, minimum: BrewVersion)` (floor **4.0.0**, PRD §8), `.probeFailed(URL, message: String)`.

**Invariants to document in code**: (I1) exactly one `OutputChunk` continuation per process,
`finish()` called once, after both EOFs and reaping. (I2) the mutation-gate tail is assigned before
any `await` in `start`. (I3) the pump `Task` is unstructured but owned by the operation record and
cancelled on exit/cancel. (I4) `LogLine.sequence` orders *within* a stream strictly; cross-stream
order is chunk-arrival order — two pipes have no OS-level ordering guarantee.

## File Changes

| File | Action | Description |
|---|---|---|
| `cellar.xcodeproj/project.pbxproj` | Modify | `SWIFT_VERSION 5.0→6.0` (6 blocks), `MACOSX_DEPLOYMENT_TARGET 26.5→26.0` (4 blocks), `ENABLE_APP_SANDBOX YES→NO` (app Debug/Release), `XCLocalSwiftPackageReference "Packages/CellarCore"` + `BrewProcess` product dependency on target `cellar` |
| `cellar.xcodeproj/xcshareddata/xcschemes/CellarCore.xcscheme` | Create | Shared scheme so `xcodebuild -scheme CellarCore` verifies the package |
| `Packages/CellarCore/Package.swift` | Create | `// swift-tools-version: 6.0`, `platforms: [.macOS("26.0")]`, target `BrewProcess` + `BrewProcessTests`, `swiftSettings: [.swiftLanguageMode(.v6)]` |
| `.../Sources/BrewProcess/LogLine.swift`, `BrewCommand.swift`, `BrewExit.swift` | Create | Value types |
| `.../Sources/BrewProcess/ProcessLaunching.swift` | Create | Seam protocols + `ProcessSpec`/`OutputChunk`/`ProcessSignal` |
| `.../Sources/BrewProcess/SystemProcess.swift` | Create | `Foundation.Process` + `Mutex<State>` + single continuation (D1, I1) |
| `.../Sources/BrewProcess/BrewRunner.swift` | Create | Actor: FIFO gate, pump, escalation |
| `.../Sources/BrewProcess/BrewEnvironment.swift` | Create | `HOMEBREW_NO_AUTO_UPDATE=1`, `HOMEBREW_COLOR=0`, `HOMEBREW_NO_EMOJI=1` |
| `.../Sources/BrewProcess/BrewLocation.swift`, `DefaultBrewLocator.swift`, `BrewVersion.swift`, `BrewDetectionStore.swift` | Create | Detection + observable state |
| `.../Sources/BrewProcess/BrewErrors.swift` | Create | Error taxonomy |
| `.../Tests/BrewProcessTests/**` | Create | Fakes + suites (below) |
| `cellar/cellarApp.swift`, `cellar/ContentView.swift` | Modify | Own `BrewDetectionStore`; `.task { await store.refresh() }` + refresh on `NSApplication.didBecomeActiveNotification`; render state as text only |
| `openspec/config.yaml` | Modify | Record Swift 6 mode, target 26.0, sandbox off |

## Testing Strategy

| Layer | What | Approach |
|---|---|---|
| Unit (fakes) | line splitting incl. chunk-split lines, CRLF, no trailing newline; stdout/stderr tagging; sequence monotonicity; stream finishes once | `FakeProcessLauncher` yields scripted `OutputChunk`s |
| Unit (fakes) | escalation: exits during `interruptGrace` ⇒ signals `[.interrupt]`; ignores SIGINT ⇒ `[.interrupt, .terminate]`; ignores both ⇒ `.cancelledUnresponsive` | `FakeProcess` records `(signal, instant)` against an injected test `Clock` — no wall-clock sleeps |
| Unit (fakes) | FIFO: 3 `.mutate` overlap-free and in submission order; a `.read` completes while a mutation is in flight | Fakes gated on continuations |
| Unit (fakes) | detection: native, `/usr/local` + `.rosettaPrefix`, valid custom, `.notExecutable`, `.notHomebrew`, `.versionTooOld`, `.configuredPathMissing`, `.absent` | `FakeExecutableProbe` + scripted `--version` output |
| Unit (pure) | `BrewVersion.parse` fixtures: `Homebrew 6.0.14-38-g1f3abf4`, `Homebrew 4.0.0`, `3.6.21`, `/bin/echo` noise, empty | Parameterized `@Test` |
| Integration | real SIGINT delivery: launch `/bin/sleep 30` through `SystemProcessLauncher`, cancel, assert `.cancelled(SIGINT)` within a generous deadline | No brew needed ⇒ never skipped, never flaky |
| Integration | real `brew --version` streams ≥1 ordered `LogLine`, exit 0; a bad subcommand yields non-zero exit **and** stderr lines | `.enabled(if: FileManager.default.isExecutableFile(atPath: "/opt/homebrew/bin/brew"))` — skip, never fail |
| Build | app + package compile warning-free in Swift 6 mode | `xcodebuild build -scheme cellar`, `swift test --package-path Packages/CellarCore` |

## Threat Matrix

| Boundary | Applicability | Design response | Planned RED test |
|---|---|---|---|
| Documentation-like paths | **N/A** — no file classification or execution of repo content | — | — |
| Git repository selection | **N/A** — no VCS automation | — | — |
| Commit / push state | **N/A** | — | — |
| PR commands | **N/A** | — | — |
| **Argument composition** (subprocess) | **Applicable** | `BrewCommand.arguments` is argv; `Process.arguments` set directly; **never** `/bin/sh -c`, never string interpolation of a command line | Command with a space/`;`/`$(...)` in an argument reaches the fake as one literal argv element |
| **Executable classification** (custom brew path) | **Applicable** | Must be an executable regular file **and** produce parseable Homebrew `--version` **and** be ≥ 4.0.0; symlinks resolved before probing | One test per `BrewValidationError` case, incl. `/bin/echo` posing as brew |
| **Environment inheritance** | **Applicable** | Explicit environment: inherited `PATH`/`HOME` plus the three pinned `HOMEBREW_*` keys; no `HOMEBREW_*` value from the user environment overrides them | Spec asserts the three keys hold pinned values even when the parent env sets them differently |

## Migration / Rollout

No data migration. Strict ordering: P0 settings (build green, no product code) → P1 package + scheme
→ P2 runner → P3 detection → P4 app seam. Each phase is independently revertible; `Packages/`
deletion plus the pbxproj package reference removes P1–P3 wholesale.

## Open Questions

- [ ] D8 (sandbox off) is required by PRD §4.2 but was not enumerated in the proposal's scope table — it is a build-setting line in the same P0 commit; flagging it as a scope addition, not a blocker.
- [ ] `swift-tools-version: 6.0` chosen for maximum compatibility; 6.2's `.defaultIsolation` is unnecessary because SwiftPM already defaults to `nonisolated`.
