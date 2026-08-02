# Delta for brew-detection

Existing capability — `openspec/specs/brew-detection/spec.md` (5 requirements / 15 scenarios).

Delta summary: **4 MODIFIED requirements / 16 scenarios**, all reproduced in full so the archive step
loses nothing. Nothing is ADDED, REMOVED or RENAMED.

Two fold-ins, both recorded against this capability's provenance and both approved for this change:

1. **S1 vocabulary alignment** (all four requirements below) — documentation only, no behaviour
   change.
2. **Request-keyed coalescing** (one requirement, "Detection is observable, re-evaluated state") —
   a real behaviour change that closes the known gap the `m2-catalog-hardening` archive routed here:
   a `configuredPath` change during an evaluation in flight could join that evaluation and adopt an
   answer computed for the *previous* path. That evaluation is genuinely in flight, just for a
   different question, so the existing clause did not cover it. The correction extends the requirement
   that already owns coalescing rather than competing with it, so the whole single-flight rule stays
   in one block.

The vocabulary fold-in closes the S1 documentation nit recorded in the provenance: the spec's `native`
and `rosettaCarryOver` vocabulary corresponds to the code's `BrewPrefix.appleSilicon` and
`BrewPrefix.intelCarryOver`. `m1-catalog-browse` declined the fix solely because that change did not
touch `BrewProcess`; this change does, so the spec adopts the code's names. Every occurrence is
aligned in one pass, so the capability does not end up half-renamed. The fifth requirement, "Absent
brew is a soft signal", names neither prefix and is untouched.

Two names are deliberately kept: the requirement title "Rosetta prefix is fully supported, advisory
only" and the word "Rosetta" in prose, because the advisory itself is `Advisory.rosettaPrefix` in the
code — that is already aligned. Only the two `BrewPrefix` case names change.

## MODIFIED Requirements

### Requirement: Prefix classification and precedence

Detection MUST classify the resolved binary as `appleSilicon` (`/opt/homebrew/bin/brew`) or
`intelCarryOver` (`/usr/local/bin/brew`). When both exist, `appleSilicon` MUST win. A configured
valid custom path MUST take precedence over both.
(Previously: the same rule stated with the spec-only names `native` and `rosettaCarryOver`, which
matched no identifier in the code.)

#### Scenario: Apple Silicon prefix preferred when both exist

- GIVEN both `/opt/homebrew/bin/brew` and `/usr/local/bin/brew` exist
- WHEN detection runs with no configured custom path
- THEN the resolved prefix is `appleSilicon` at `/opt/homebrew/bin/brew`

#### Scenario: Only the Intel carry-over prefix exists

- GIVEN only `/usr/local/bin/brew` exists
- WHEN detection runs
- THEN the resolved prefix is `intelCarryOver` at `/usr/local/bin/brew`

### Requirement: Rosetta prefix is fully supported, advisory only

An `intelCarryOver` result MUST be fully usable — it MUST NOT disable, degrade, or gate any
operation. It MUST expose an advisory migration flag that consumers MAY surface once.
(Previously: the same rule stated for a `rosettaCarryOver` result.)

#### Scenario: Advisory flag does not restrict capability

- GIVEN detection resolved `intelCarryOver`
- WHEN the state is inspected
- THEN its advisory migration flag is true
- AND no capability, mutation, or command is marked disabled or degraded

### Requirement: Strict custom path validation

A configured custom path MUST pass all three checks: the file is executable; its `--version` output
parses as genuine Homebrew; the reported version is at least 4.0.0. Failure MUST produce exactly one
typed reason — `notExecutable`, `notHomebrew`, or `versionTooOld(found:minimum:)` — reported as an
`invalid(reason:)` state. Detection MUST NOT silently fall back to an auto-discovered prefix when a
configured path is invalid, and MUST NOT run any mutating brew command.
(Previously: identical, with the final scenario contrasting the outcome against `native`.)

#### Scenario: Path is not executable

- GIVEN a configured custom path that exists but is not executable
- WHEN detection runs
- THEN the state is `invalid(notExecutable)`

#### Scenario: Path is executable but is not Homebrew

- GIVEN a configured executable whose `--version` prints `git version 2.4.0`
- WHEN detection runs
- THEN the state is `invalid(notHomebrew)`

#### Scenario: Homebrew below the 4.x floor

- GIVEN a configured executable whose `--version` prints `Homebrew 3.6.21`
- WHEN detection runs
- THEN the state is `invalid(versionTooOld(found: "3.6.21", minimum: "4.0.0"))`

#### Scenario: Valid custom path wins over auto-discovery

- GIVEN `/opt/homebrew/bin/brew` exists AND a configured executable prints `Homebrew 4.2.0`
- WHEN detection runs
- THEN the state is `custom` at the configured path with version `4.2.0`

#### Scenario: Invalid custom path does not fall back

- GIVEN `/opt/homebrew/bin/brew` exists AND the configured path is not executable
- WHEN detection runs
- THEN the state is `invalid(notExecutable)` and the resolved prefix is not `appleSilicon`

### Requirement: Detection is observable, re-evaluated state

Detection state MUST be observable, evaluated at launch, and re-evaluated on window focus and when
the configured path disappears. Every re-evaluation MUST publish the resulting state so observers
see transitions. Overlapping re-evaluations MUST be coalesced onto the one evaluation genuinely in
flight; a re-evaluation requested after the evaluation in flight has settled, or after its
requesting caller was cancelled or abandoned, MUST run a fresh probe and MUST NOT be answered with
the earlier evaluation's result. A settled or abandoned evaluation MUST NOT leave detection unable
to re-evaluate. Coalescing MUST be keyed by the request being evaluated — the configured path the
evaluation was started for. A re-evaluation for a different request MUST NOT be answered with an
evaluation in flight for the previous one; it MUST evaluate the new request, and the published state
MUST correspond to the request most recently asked for.
(Previously: two scenarios named the resolved prefix `native`; and the coalescing clause was not
keyed by request, so a re-evaluation triggered by the user repointing the configured path could join
an evaluation already in flight for the *previous* path and adopt its answer as if it were the new
path's.)

#### Scenario: Evaluated at launch

- GIVEN a fresh detection service
- WHEN the launch evaluation runs
- THEN observers receive exactly one state for that evaluation

#### Scenario: Focus re-evaluation observes a newly installed brew

- GIVEN the current state is `absent`
- WHEN brew appears at `/opt/homebrew/bin/brew` and a focus event occurs
- THEN a re-evaluation runs and observers receive a transition to the `appleSilicon` prefix

#### Scenario: Disappearing configured path transitions away

- GIVEN the current state is `custom` at a configured path
- WHEN that path no longer exists and detection re-evaluates
- THEN observers receive a transition off `custom` to `configuredPathMissing`
- AND a path that still exists but is not executable is instead reported as
  `invalid(notExecutable)`, distinct from `configuredPathMissing`

#### Scenario: A settled evaluation does not answer a later re-evaluation

- GIVEN a locator that answered one evaluation with `absent` and that evaluation has settled
- WHEN a re-evaluation is requested and the locator would now resolve the `appleSilicon` prefix
- THEN the locator is probed a second time
- AND observers receive a transition to the `appleSilicon` prefix

#### Scenario: An abandoned caller does not poison later re-evaluations

- GIVEN a caller whose task is cancelled while it awaits a re-evaluation
- WHEN a later re-evaluation is requested and the locator would now resolve a different state
- THEN a fresh probe runs
- AND observers receive the newest result rather than the abandoned caller's

#### Scenario: Concurrent re-evaluations coalesce onto one probe

- GIVEN a locator that does not answer until it is released
- WHEN two callers request a re-evaluation before the locator is released
- THEN exactly one probe is performed and both callers observe the same resulting state

#### Scenario: A configured path changed mid-evaluation is not answered by the previous path

- GIVEN an evaluation in flight for configured path `A`, which the locator has not yet answered
- WHEN the configured path is changed to `B` and a re-evaluation is requested, and the locator would
  resolve `A` and `B` to different states
- THEN the locator is probed for `B`
- AND the published state is `B`'s, not the state the in-flight evaluation of `A` resolves to

#### Scenario: Identical concurrent requests still coalesce

- GIVEN a locator that does not answer until it is released
- WHEN two callers request a re-evaluation for the same configured path before the locator is
  released
- THEN exactly one probe is performed and both callers observe the same resulting state
