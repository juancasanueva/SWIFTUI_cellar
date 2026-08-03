# Design: M3-1 — Service Management (`m3-services`)

Inputs: `proposal.md`; `m3-services-cleanup-taps/explore.md` §2, §6-A, §6-B, §6-D, §7;
probe gates U1/U5/U8 (Engram #7178); defect #7179; product rulings #7180 / #7182;
M3-0 archive register #7141. Every code claim below was read at `main` @ `3f2c166`.

## Technical Approach

One protocol generalizes the shipped mutation spine so Services enters it as a
*second family* rather than as new enum cases. Reads copy `BrewInfoPayloadSource`
verbatim. The poll copies `InstalledRefreshCoordinator`'s trust order with a
visibility gate. Two shipped hardcodes — `MutationOutcome.forcesReSnapshot == true`
and `BrewEnvironment.pinned["HOMEBREW_COLOR"]` — are replaced, not worked around.

---

## D1 — `BrewMutating`, with generic parameters and one erased value

```swift
public protocol BrewMutating: Sendable {
    var arguments: [String] { get }          // argv, excluding `brew`
    var verb: String { get }                 // recorded + searched under (IH1/IH5)
    var packageID: PackageID? { get }        // nil for every non-package family
    var requiresConfirmation: Bool { get }
    var invalidates: InvalidationScope { get }
    func classify(exit: BrewExit, fault: BrewProcessError?, log: [LogLine]) -> MutationOutcome
}

extension BrewMutating {                     // defaults — no conformer restates them
    public var displayCommand: String { "brew " + arguments.joined(separator: " ") }
    public var brewCommand: BrewCommand { .mutate(arguments) }
    public func classify(exit:fault:log:) -> MutationOutcome   // today's logic, verbatim
}
```

| Question | Decision | Rationale |
|---|---|---|
| Protocol vs. enum cases vs. parallel centre | **Protocol** (§6-A option 1) | PM1 "exactly six" stays literally true; `MutationCommand` conforms in a 3-line extension supplying only `invalidates`. Option 2 contradicts PM1 and grows a ~18-case switch; option 3 breaks FIFO against brew's global lock |
| `Sendable` only, no `Equatable`/`Hashable` | **Yes** | A `Self`-requirement makes the protocol unusable as a stored property and breaks `ConfirmationRequest: Equatable` and its four existing assertions |
| How `OperationCenter` takes a command | **`submit(_ command: some BrewMutating, versions:)`** — generic, not existential | Every existing app-target call site (`MutationMenu`, `InstalledListView`, `ActivityBar`, `BrowseView`) passing a `MutationCommand` compiles **unchanged**. The forecast "56 mechanical edits" mostly evaporates |
| What `ActivityItem` and `ConfirmationRequest` *store* | **`AnyBrewMutation`** — a `Sendable, Equatable` struct holding the six projections, built by `init(_ some BrewMutating)`, itself conforming to `BrewMutating` | Restores synthesized `Equatable` for free; strengthens the shipped "nothing is parsed back out of a command" property, because the erased value carries projections and no case payload to recover |

**The `-`-prefix rejection survives for every conformer by construction.**
`MutationName.isSafe` (`MutationCommand.swift:104`) stays the single gate. A new
`ServiceTarget` is expressed over it exactly as `PackageTarget` is. The structural
rule: *a conformer's `arguments` may contain only literal verb/flag enum raw values
plus tokens taken from a validated wrapper.* Enforced by the VS1-style positive
structural scan test over `Sources/BrewClient/*Command.swift`.

## D2 — `InvalidationScope`: one mechanism, one problem

```swift
public struct InvalidationScope: OptionSet, Sendable, Hashable {
    public static let installedInventory = InvalidationScope(rawValue: 1 << 0)
    public static let services           = InvalidationScope(rawValue: 1 << 1)
    // 1 << 2 taps (M3-2), 1 << 3 diskUsage (M3-3) — reserved, not declared here
}
```

The problem this solves is **scoped invalidation**, and nothing else: a services
toggle changes nothing in the installed set, so it must not pay for an inventory
re-snapshot.

- `MutationOutcome.forcesReSnapshot` is **deleted**, not kept. Its replacement is
  the *command's* scope, because what a mutation invalidates is a property of what
  ran, not of how it ended. PM6's real invariant is restated and preserved: **every
  terminal outcome — succeeded, failed, busy, cancelled, abandoned, launchFailed —
  still owes exactly one refresh of everything its command invalidates.**
- Fan-out: `OperationCenter.init(gates: MutationGates, …)`, where `MutationGates`
  maps scope → gate and begins/ends only the intersecting gates. The existing
  `init(gate:)` is kept as a convenience building `[(.installedInventory, gate)]`,
  so every current test and the app's composition root compile unchanged.
- The services gate is a **second instance of the shipped `InstalledMutationGate`
  type**, not a new type: it is already a depth counter plus a `terminals` stream
  with nothing installed-specific in its body. Renaming it to match its new
  generality is deliberately **not** done here — it is public API with test call
  sites, and the rename buys no behaviour. The naming debt is recorded, not hidden.
- Net for a services toggle: **zero `brew info --installed --json=v2` probes**,
  saving 1.27 s / 663 KB per toggle.

### Deferred from this slice: M2-2 #6 (post-terminal echo re-snapshot)

An earlier draft folded M2-2 #6 — a mutation's own post-terminal FSEvents echo
buying a redundant re-snapshot ~3 s later — into this decision as an `isSettling`
grace window on `InstalledRefreshCoordinator`. **That is removed.** It is wrong as
designed, and the correction is worth recording:

`openspec/specs/installed-inventory/spec.md:334-337` requires that a change signal
arriving *after* an acquisition started MUST "cause a further re-snapshot once the
quiet window elapses, so the inventory converges on state observed at or after the
newest signal". The grace guard sits exactly where that re-snapshot would fire and
**drops** it. For the mutation's own echo that is harmless; the rule cannot tell
the echo apart from a genuine external change landing in the same window, and that
one would be silently lost. The earlier draft cited II10 sc5 as cover — that
paragraph (`:329-332`) governs *in-flight* suppression, a different moment and a
different guarantee.

Closing M2-2 #6 therefore requires an explicit `installed-inventory` amendment
narrowing the convergence guarantee. **This slice does not take that spec
decision**, and the register already classified the redundant re-snapshot as
*conforming, not a defect*. **M2-2 #6 is re-registered as an open follow-up**, with
the amendment named as its precondition. `InvalidationScope` is unaffected and
stays in full — it is what makes a service toggle cost zero inventory probes.

## D3 — The poll loop

| Decision | Choice |
|---|---|
| Source polled | **`brew services list --json`** (0.37 s), not `info --all --json` (0.43 s) |
| Why | The 0.06 s delta is measured at **n = 1 service**. `info --all` cost scales with service count; `list` is one launchctl dump. The poll runs every 5 s forever, and the detail pane needs `info` for exactly one service. `info --json <name>` is fetched **lazily, keyed on selection** (§6-D) |
| Cadence | `.seconds(5)`, injected `any Clock<Duration>` (ruling #7180 b) |
| Ownership | `ServicesRefreshCoordinator`, mirroring `InstalledRefreshCoordinator`'s four rules: baseline on appear; poll only while visible; forced refresh at every service-mutation terminal; suppressed while a services mutation is in flight |
| Loop placement | `LoopOwner.start("services")` runs `run()` — the **terminals consumer only**, app-lifetime, matching `loops.start("installed")` |
| Poll task placement | **Owned by the coordinator**, created by `setVisible(true)` and `cancel()`-ed + niled by `setVisible(false)` |

**Trap, read from the code:** the poll must **not** be a `LoopOwner` slot.
`LoopOwner.start` guards on `loops[id] == nil` and a slot "stays claimed for the
rest of the launch even if its body returns" (`LoopOwner.swift:20-23, 32`) — a poll
started there would never restart after the first hide.

Visibility is reported, never decided, by the UI: `ServicesListView.onAppear/
onDisappear` (covers section deselect and window close) plus `scenePhase` in
`cellarApp`. Determinism: `TestClock` (already in `CellarTestSupport`, used by
`InstalledRefreshDefectTests`). No wall-clock sleeps anywhere.

## D4 — Outcome classification for the four verbs

U8 facts: cold start → exit 0, stdout `==> Successfully started …`. Start on a
running service → **exit 0**, stdout ``Service `x` already started, use …``, no
`Successfully`, no `Error:`. Stop on a stopped service → **exit 0**, stderr
`Warning: Service \`x\` is not started.` Exit code alone cannot separate them.

1. **`MutationOutcome` gains exactly one case: `.noChange`.** `isSuccess == false`,
   `isFailure == false` (the `.cancelled` shape); `summaryLabel` `"No change"`;
   recorder maps it to `(raw: "noChange", exitStatus: 0)`. Cost is four
   compiler-enforced exhaustive switches. Rejected: an associated value on
   `.succeeded` (breaks `==` across many shipped tests); a display-only "note"
   (would leave the durable history saying "Done" about a no-op, which is a lie).
2. **Where the marker pass runs.** `classify` today decides `if exit.isSuccess {
   return .succeeded }` *before* reading any prose. The protocol's default
   implementation keeps that byte-for-byte; **`ServiceCommand` overrides
   `classify` to consult its own markers on exit 0 first, then falls through to
   the default.** So "package classification is unchanged" is a testable claim, and
   only the family that needs prose on exit 0 pays for it.
3. **Marker matching.** `line.contains(<interior invariant>)`, never anchored and
   never whole-sentence: brew interpolates the service name into every marker, and
   `contains` on an interior phrase is strictly more robust than a prefix match.
   `"already started, use"` → `.noChange`. `"is not started"` → `.noChange`.
   `"Successfully started"` / `"Successfully stopped"` are **corroboration only**,
   never the sole success test.
4. **Scan scope widens to stdout — for this family only.** The shipped stderr-only
   rule exists so a *package's* build script echoing prose cannot change what the
   user is told. `brew services` runs no third-party build script; its stdout is
   brew's own prose plus launchctl's. Because the marker pass is family-owned, the
   widening cannot reach `install`/`upgrade`.
5. **Unmatched failure is never success.** Non-zero exit with no matching marker
   falls through the existing lock/privilege signatures to `.failed(status:)` with
   the log verbatim. U5's root-domain path (non-fatal `opoo` "must be run as root
   to start at system startup!" then a possibly non-zero `launchctl bootstrap`) is
   classified `.needsPrivileges` **only when the exit is non-zero** and the marker
   is present; on exit 0 it is an informational note. Cellar never escalates
   privilege, and the exact bootstrap text is unprobed, so the default degrades to
   a generic failure with the output on screen.

## D5 — `HOMEBREW_NO_COLOR` (defect #7179)

`BrewEnvironment.pinned`: `"HOMEBREW_COLOR": "0"` → `"HOMEBREW_NO_COLOR": "1"`.
The doc comment at `BrewEnvironment.swift:15` asserts the opposite of the shipped
behaviour and is corrected; `explore.md:207-208` repeats the wrong claim and is
corrected. `openspec/specs/brew-execution/spec.md:11` names the key in requirement
text — the delta is `sdd-spec`'s, in parallel.

Two RED tests, both required:

- **Deterministic anchor (always runs).** `#expect(BrewEnvironment.pinned["HOMEBREW_COLOR"] == nil)`
  and `== "1"` for `HOMEBREW_NO_COLOR`; then `RecordingProcessLauncher` proves the
  *spawned* process received exactly that environment, so the key cannot be
  reintroduced anywhere between `pinned` and `SystemProcess`.
- **The ESC proof (integration, self-skipping).** A real `brew info --formula <name>`
  over a formula discovered from `brew list --formula`, `.enabled(if:)`-guarded and
  tagged so the fast loop can exclude it, asserting
  `log.allSatisfy { !$0.text.utf8.contains(0x1B) }`. This is the honest form of the
  success criterion "no ESC (0x1B) byte survives in captured output" — a fake
  process cannot prove anything about brew's own colour decision.

## D6 — Absorbed register items

| Item | Decision |
|---|---|
| **(a) failed-clear reason erased by reload** (top of register) | `HistoryStore` gains a private sticky failure reason. `clearAll()`'s catch sets it; `reload()` ends with `availability = sticky.map(.unavailable) ?? <fetch outcome>` instead of unconditional `.available`; a successful `append`/`clearAll` clears it. RED: fail a clear, then type into `search` (which `didSet`-reloads per keystroke) and assert the reason and `lastError` both survive |
| **VS2** (`pendingConfirmation` widened to `internal(set)`) | A small `@Observable ConfirmationBox` held `@ObservationIgnored private let`; `OperationCenter.pendingConfirmation` becomes a **computed getter with no setter at all** — strictly stronger than the `private(set)` it restores. Observation propagates through the nested observable read, so the sheet still updates |
| **M2-2 #7** (duplicate submit) | `ServiceSubmissionGuard`, keyed on `ServiceTarget.name`, on the **services submit path only**: a second services command for a name with a non-terminal one already in flight returns that existing `ActivityItem` instead of queueing an opposite operation. Explicitly services-scoped; the general dedup rule stays deferred |
| **S1** (`BrewRunner.exit(of:)` fabricating `status: 0`) | **ALREADY CLOSED by M3-0.** `BrewRunner.swift:288/293` returns `.unknownOperation`, and `MutationOutcome.swift:75` maps it to `.launchFailed`. **No work in this slice** |
| **W1** (no-runner submit) | **ALREADY CLOSED by M3-0.** `gate?.begin()` is hoisted above the runner guard and the no-runner path routes through `finish()` (`OperationCenter.swift:168-177`). **No work** |
| **VS4** (clock seam for `HistoryDraft.date`) | **Not adopted.** No assertion in this slice needs a deterministic timestamp — the history claims are "exactly one entry", "null package identity", "typed verb". Stays open |

## D7 — Reads, decoders, store

| Piece | Shape |
|---|---|
| `ServicesListPayloadSource` | **Compile-time constant argv** `BrewCommand.read(["services","list","--json"])`, exactly `BrewInfoPayloadSource`'s pattern |
| `ServiceInfoPayloadSource` | `["services","info","--json", name]` — the *only* parameterised read argv in the codebase; `name` comes from a `ServiceTarget`, is the last element, and is a separate argv element (never interpolated) |
| Payload rule | `ServicesPayload.payload(from:exit:)` — pure, copying `InstalledPayload` verbatim: non-zero exit is an error and never an empty list; stderr never enters the document; blank document is malformed |
| Errors | Closed `ServicesError { brewUnavailable, commandFailed(status:message:), malformedPayload, cancelled }` |
| `ServiceStatus` | `started, none, scheduled, stopped, error, unknown, other` **+ `unrecognised(String)`** — brew's own `other` is a real value, so the catch-all needs a different name. An unrecognised string never fails the payload |
| Nullability | `user` and `exit_code` optional (U1). `info` optional keys arrive as **null**, not omitted |
| `log_path` / `error_log_path` | May be the same file. `ServiceDetail.logPaths: [URL]` is **deduped and order-stable** (log first, error second only when different) |
| `ServicesStore` | Copies `InstalledStore`: single-flight keyed by request URL + invalidation mark, ordinal-guarded adoption, last-good survives failure, `brewAbsent` guidance |

**Deviation from the proposal, flagged:** the proposal says "`ServicesStore` joins
M3-0's single `LocalStores` container." Services state is launchd truth and
**persists nothing**, so it opens no container at all. W3's invariant ("no second
`ModelContainer` is ever opened") is preserved *a fortiori*, and the existing
`LocalStoresTests > oneContainerServesBothStores` remains the assertion.

## D8 — Services UI

- `AppSection` gains `.services` (5th case). Verified: no test asserts a case count
  on `AppSection` — `BulkSelection.Action.allCases == [.upgrade, .uninstall]` is the
  only exhaustive enum assertion in the suite, and it is untouched.
- `ServicesListView` (content column) · `ServiceRow` (name + colour-coded status) ·
  `ServiceDetailView` (status, user, plist `file`, deduped log paths, open-in-Console).
- **All four verbs are visible, explicit controls** (ruling #7182-3): `start`
  registers at login, `run` does not; nothing hidden touches login items. Asserted
  the project's way, as an enumerable surface: `ServiceRowControl.allCases ==
  [.start, .run, .stop, .restart, .copyCommand]` — the `ActivityItem.Control` /
  `HistoryRecord.Control` idiom, so "no hidden default" is a claim about the whole
  surface rather than an unwritten omission.
- **A service that dies on its own is a red row on the next poll tick** — no
  notification, no badge, no delivery path, no new requirement (ruling #7182-2).
- Open-in-Console goes through a `LogFileOpening` protocol seam in `BrewClient`
  (config `rules.design`: a protocol boundary for every external dependency); the
  app target holds the one `NSWorkspace` implementation.
- Brew-absent → read-only guidance, reusing `OperationCenter.unavailableGuidance`
  and `ServicesStore.absence`. No new rule.
- **No services multi-select ships.** If one ever does it MUST be a new
  `ServiceSelection.Action` over `ServiceTarget`; extending `BulkSelection.Action`
  breaks installed-inventory II13 sc4 (proven exhaustive at two cases).

## D9 — The four verbs

```swift
public enum ServiceCommand: Sendable, Equatable, BrewMutating {
    case start(ServiceTarget)    // registers at login
    case run(ServiceTarget)      // does not
    case stop(ServiceTarget)
    case restart(ServiceTarget)
}
```

- `arguments` = `["services", <verb>, target.name]`. **`--all` is unrepresentable**:
  no case omits a target. That is the structural answer to the `upgradeAll` trap —
  one invocation per service, in selection order (M2 fan-out ruling, PM2 sc2).
- `invalidates` = `.services`. `packageID` = `nil` (ruling #7180 a).
- `verb` = `"serviceStart" | "serviceRun" | "serviceStop" | "serviceRestart"`,
  camelCase on the `upgradeAll` precedent, namespaced so an IH5 search for "start"
  cannot collide with a package verb.
- `requiresConfirmation` = **false** for all four, recorded not silent: none
  destroys anything, each is reversible in one click, and `start` vs `run` is
  already an explicit user choice rather than a side effect.
- **`kill` and `stop --keep` are out**, with rationale: PRD §3.3 names four verbs;
  both extras mean "stop but stay registered", which has no PRD surface and would
  make the start/run login-item distinction incoherent to explain.
- Every command is `.mutate` via the protocol default, so BE5 (serialized
  mutations, concurrent reads) is inherited unchanged.

## Data Flow

```
ServiceRow ──► OperationCenter.submit(ServiceCommand)   [ServiceSubmissionGuard]
                   │
                   ├─► MutationGates.begin(.services)      (installed gate untouched)
                   ├─► ActivityItem(AnyBrewMutation)  ──► BrewRunner .mutate FIFO
                   └─► finish(item, with: command.classify(exit:fault:log:))
                           ├─► MutationGates.end(.services)  ──► services terminal
                           └─► history.record(HistoryDraft(packageID: nil, verb:))
                                                              │
ServicesRefreshCoordinator ◄── terminals ◄────────────────────┘
   ├── setVisible(true)  → baseline + poll(5 s, injected clock)
   ├── setVisible(false) → pollTask.cancel(); pollTask = nil
   └── suppressed while serviceGate.isMutating
           │
           └─► ServicesStore ──► ServicesListView / ServiceDetailView
                                        │
                    ServiceInfoPayloadSource (lazy, selection-keyed)
```

## File Changes

| File | Action | What |
|---|---|---|
| `Sources/BrewClient/BrewMutating.swift` | Create | protocol, defaults, `AnyBrewMutation`, `InvalidationScope`, `MutationGates` |
| `Sources/BrewClient/ServiceCommand.swift` | Create | `ServiceTarget`, four verbs, markers, `classify` override |
| `Sources/BrewClient/ServicesPayloadSource.swift` | Create | two sources, pure payload fn, closed error enum |
| `Sources/BrewClient/ServicesWire.swift` | Create | tolerant decoders, `ServiceStatus`, `ServiceDetail` log dedupe |
| `Sources/BrewClient/ServicesStore.swift` | Create | `InstalledStore` clone over services |
| `Sources/BrewClient/ServicesRefreshCoordinator.swift` | Create | visibility gate, poll, terminals, suppression |
| `Sources/BrewClient/LogFileOpening.swift` | Create | open-in-Console seam |
| `Sources/BrewClient/MutationCommand.swift` | Modify | + `extension MutationCommand: BrewMutating { invalidates }` — **nothing else** |
| `Sources/BrewClient/MutationOutcome.swift` | Modify | `.noChange`; delete `forcesReSnapshot`; `message(for: some BrewMutating)` |
| `Sources/BrewClient/OperationCenter.swift` | Modify | generic `submit`, `MutationGates`, `ConfirmationBox` |
| `Sources/BrewClient/OperationCenterBulk.swift` | Modify | generic `request`, `ConfirmationRequest` over `AnyBrewMutation` |
| `Sources/BrewClient/OperationCenterServices.swift` | Create | services submit path + duplicate-submit guard |
| `Sources/BrewClient/ActivityItem.swift` | Modify | `command: AnyBrewMutation` |
| `Sources/BrewProcess/BrewEnvironment.swift` | Modify | `HOMEBREW_NO_COLOR=1` + doc comment |
| `Sources/Persistence/HistoryStore.swift` | Modify | sticky failure reason |
| `Sources/Persistence/SwiftDataHistoryRecorder.swift` | Modify | `.noChange` mapping |
| `cellar/Shell/AppSection.swift` | Modify | `.services` |
| `cellar/Services/{ServicesListView,ServiceRow,ServiceDetailView,ServiceControls}.swift` | Create | the surface |
| `cellar/ContentView.swift`, `cellar/cellarApp.swift` | Modify | column wiring, DI, `loops.start("services")`, `scenePhase` |
| `openspec/changes/m3-services-cleanup-taps/explore.md` | Modify | correct `:207-208` |

## Testing Strategy

| Layer | What | How |
|---|---|---|
| Unit | argv composition per verb; `-`-prefix and empty-name rejection; `--all` unrepresentable; structural scan | `swift test`, no process |
| Unit | seven statuses + unrecognised catch-all; null `user`/`exit_code`; identical log/error paths deduped | fixture JSON (**fixture-first is mandatory** — the dev machine shows one service, status `none`) |
| Unit | start-on-running → `.noChange`; stop-on-stopped → `.noChange`; unmatched non-zero → `.failed`; root-domain marker on exit 0 → note, not `.needsPrivileges`; package classification byte-identical | fixture `LogLine` arrays |
| Unit | `.services` scope drives no installed re-snapshot; every terminal (incl. cancelled/failed) refreshes its own scope exactly once | `MutationGates` + fakes |
| Unit | poll ticks at 5 s while visible; zero calls after `setVisible(false)`; advancing 60 s adds none; forced refresh at terminal; suppressed while mutating | `TestClock`, `.timeLimit(.minutes(1))` on the suite |
| Unit | one history entry per verb, null package identity, typed verb | `OperationCenterHarness` |
| Unit | failed-clear reason survives a search-driven reload; `pendingConfirmation` has no setter | Persistence + BrewClient suites |
| Unit | `BrewEnvironment.pinned` keys; spawned process environment | `RecordingProcessLauncher` |
| Integration | **no ESC (0x1B) byte in captured output** | real `brew`, self-skipping |
| Manual | every UI-only scenario (ruling #7180 c — written into `tasks.md` **before** apply) | recorded checks |

## Threat Matrix

| Boundary | Applicability | Design response | Planned RED tests |
|---|---|---|---|
| Documentation-like paths | **N/A** — no file is classified or executed by this change | — | — |
| Git repository selection | **N/A** — no VCS automation | — | — |
| Commit state | **N/A** | — | — |
| Push state | **N/A** | — | — |
| PR commands | **N/A** | — | — |
| **Subprocess argument composition** (project row) | **Applicable** — four new mutating argv shapes and the codebase's first *parameterised* read argv | argv vector only, never a string; service name only from `ServiceTarget` over `MutationName.isSafe`; name is the last, separate element; `--all` unrepresentable; structural scan | name with leading `-`, empty, whitespace, a name equal to `--all` — each rejected at construction, no argv built. A shell metacharacter (`;`, `$(…)`, `` ` ``, `\|`, `&`, `>`) is **not** rejected and must not be: `MutationName.isSafe` is exactly "non-empty, no leading `-`, no whitespace" and PM9 is untouched. It is neutralised structurally instead — argv is a vector, so the name reaches brew as one literal element and no shell is ever involved. Proven through the real process seam by `shellMetacharactersSurviveAsOneLiteralArgument` |
| **Untrusted subprocess payload as classification input** (project row) | **Applicable** — the marker scan widens to stdout for one family | Family-owned marker pass; classification changes only the message, never argv, never a retry, never a privilege; nothing is extracted from the payload | stdout prose claiming success on a non-zero exit still classifies `.failed`; a payload containing `already started, use` cannot reclassify an `install` |
| **Privilege boundary** (project row) | **Applicable** — U5's root-domain path | Never escalates; `/dev/null` stdin cannot reach a prompt (U5 proved no sudo in the start path); `.needsPrivileges` only on non-zero + marker | root-domain marker on exit 0 → not `.needsPrivileges`; unprobed bootstrap text → `.failed`, never `.succeeded` |
| **Process integration** (project row) | **Applicable** — a 5 s recurring subprocess | Visibility-gated, injected clock, task cancelled and niled on hide, suppressed while mutating, `.read` so it bypasses the mutation gate | no spawn after hide across 60 s of simulated time |

## Size Forecast Delta

Deferring the M2-2 #6 grace removes `isSettling`, the injected `settleGrace`, and
its clock plumbing on `InstalledRefreshCoordinator` (~30–40 production lines), the
two `TestClock` tests that would have pinned it (~70–100 test lines), and one
changed file from the candidate. Against the ledger's accounting that is roughly
**−120 to −180 lines**.

**Revised forecast: ~3,650–5,050 ledger lines** (was 3,800–5,200). This does **not**
change the conclusion: a `size:exception` is still required, and must be recorded
before apply starts.

## Migration / Rollout

No migration. `MutationCommand` conforms in an extension, `init(gate:)` survives as
a convenience, `ServicesStore` adds no schema and opens no container, and
`HOMEBREW_NO_COLOR` is a one-key edit. Reverting the PR restores the M3-0 spine
exactly; any service started through Cellar stays started, as if started from
Terminal (PRD principle 2 — Cellar never touches the Cellar/Caskroom directly).

## Open Questions

- [ ] Exact stderr/exit signature of a failed root-domain `launchctl bootstrap`
      (U5 residual, unprobed). The design degrades to `.failed` with the log
      verbatim, so this is a message-quality gap, not a correctness gap.
- [ ] **M2-2 #6 stays open** (see D2). Closing it needs an `installed-inventory`
      II10 amendment narrowing the `:334-337` convergence guarantee so a
      post-terminal echo can be dropped without also dropping a genuine external
      signal in the same window. That is a spec decision, not a design one, and it
      is not taken here.
- [ ] `brew services info --json <name>` was schema-verified from source and
      cost-probed only via `--all` at n = 1. If a per-service call proves slow, the
      detail fetch is already lazy and selection-keyed, so the mitigation is a
      cache, not a redesign.
