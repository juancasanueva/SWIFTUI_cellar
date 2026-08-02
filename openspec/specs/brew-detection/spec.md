# brew-detection

Locating and validating the local `brew` binary: prefix classification and precedence, strict
custom-path validation, the soft `absent` signal, and observable re-evaluated detection state.
Owned by `Packages/CellarCore` target `BrewProcess`.

## Requirements

### Requirement: Prefix classification and precedence

Detection MUST classify the resolved binary as `native` (`/opt/homebrew/bin/brew`) or
`rosettaCarryOver` (`/usr/local/bin/brew`). When both exist, `native` MUST win. A configured valid
custom path MUST take precedence over both.

#### Scenario: Native prefix preferred when both exist

- GIVEN both `/opt/homebrew/bin/brew` and `/usr/local/bin/brew` exist
- WHEN detection runs with no configured custom path
- THEN the state is `native` at `/opt/homebrew/bin/brew`

#### Scenario: Only the Rosetta prefix exists

- GIVEN only `/usr/local/bin/brew` exists
- WHEN detection runs
- THEN the state is `rosettaCarryOver` at `/usr/local/bin/brew`

### Requirement: Rosetta prefix is fully supported, advisory only

A `rosettaCarryOver` result MUST be fully usable — it MUST NOT disable, degrade, or gate any
operation. It MUST expose an advisory migration flag that consumers MAY surface once.

#### Scenario: Advisory flag does not restrict capability

- GIVEN detection resolved `rosettaCarryOver`
- WHEN the state is inspected
- THEN its advisory migration flag is true
- AND no capability, mutation, or command is marked disabled or degraded

### Requirement: Absent brew is a soft signal

When no brew binary is found, detection MUST report an explicit `absent` state carrying install
guidance (brew.sh link and the install one-liner). Absence MUST NOT block launch or hard-gate the
app; consumers render read-only/empty guidance.

#### Scenario: No brew anywhere

- GIVEN no brew exists at any known prefix and no custom path is configured
- WHEN detection runs
- THEN the state is `absent` with install guidance
- AND the state resolves successfully rather than throwing or blocking

### Requirement: Strict custom path validation

A configured custom path MUST pass all three checks: the file is executable; its `--version` output
parses as genuine Homebrew; the reported version is at least 4.0.0. Failure MUST produce exactly one
typed reason — `notExecutable`, `notHomebrew`, or `versionTooOld(found:minimum:)` — reported as an
`invalid(reason:)` state. Detection MUST NOT silently fall back to an auto-discovered prefix when a
configured path is invalid, and MUST NOT run any mutating brew command.

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
- THEN the state is `invalid(notExecutable)` and is not `native`

### Requirement: Detection is observable, re-evaluated state

Detection state MUST be observable, evaluated at launch, and re-evaluated on window focus and when
the configured path disappears. Every re-evaluation MUST publish the resulting state so observers
see transitions. Overlapping re-evaluations MUST be coalesced onto the one evaluation genuinely in
flight; a re-evaluation requested after the evaluation in flight has settled, or after its
requesting caller was cancelled or abandoned, MUST run a fresh probe and MUST NOT be answered with
the earlier evaluation's result. A settled or abandoned evaluation MUST NOT leave detection unable
to re-evaluate.

#### Scenario: Evaluated at launch

- GIVEN a fresh detection service
- WHEN the launch evaluation runs
- THEN observers receive exactly one state for that evaluation

#### Scenario: Focus re-evaluation observes a newly installed brew

- GIVEN the current state is `absent`
- WHEN brew appears at `/opt/homebrew/bin/brew` and a focus event occurs
- THEN a re-evaluation runs and observers receive a transition to `native`

#### Scenario: Disappearing configured path transitions away

- GIVEN the current state is `custom` at a configured path
- WHEN that path no longer exists and detection re-evaluates
- THEN observers receive a transition off `custom` to `configuredPathMissing`
- AND a path that still exists but is not executable is instead reported as
  `invalid(notExecutable)`, distinct from `configuredPathMissing`

#### Scenario: A settled evaluation does not answer a later re-evaluation

- GIVEN a locator that answered one evaluation with `absent` and that evaluation has settled
- WHEN a re-evaluation is requested and the locator would now resolve `native`
- THEN the locator is probed a second time
- AND observers receive a transition to `native`

#### Scenario: An abandoned caller does not poison later re-evaluations

- GIVEN a caller whose task is cancelled while it awaits a re-evaluation
- WHEN a later re-evaluation is requested and the locator would now resolve a different state
- THEN a fresh probe runs
- AND observers receive the newest result rather than the abandoned caller's

#### Scenario: Concurrent re-evaluations coalesce onto one probe

- GIVEN a locator that does not answer until it is released
- WHEN two callers request a re-evaluation before the locator is released
- THEN exactly one probe is performed and both callers observe the same resulting state

## Provenance

- Established by change `m1-brewrunner-core` (archived `2026-08-01`), ADDED-only delta —
  `openspec/changes/archive/2026-08-01-m1-brewrunner-core/specs/brew-detection/spec.md`.
- **Archive amendment (W1, 2026-08-01)**: the scenario "Disappearing configured path transitions
  away" previously enumerated only `invalid(notExecutable)` or `absent`. Amended to include the
  implemented `configuredPathMissing(URL)` state (design + task 3.9), which distinguishes a deleted
  path from a non-executable one.
- Open documentation nit (verify S1, not resolved at archive): the spec vocabulary
  `native` / `rosettaCarryOver` corresponds to the code's `BrewPrefix.appleSilicon` /
  `.intelCarryOver`. Semantically identical; unify in a later change.
- **Editorial reconciliation (change `m1-catalog-browse`, 2026-08-01)**: the "Disappearing configured
  path" scenario asserted a three-way outcome enumeration in its THEN block alongside the AND clause
  that disambiguates it. Amended so the THEN block states the single outcome and the AND clause
  contrasts it with `invalid(notExecutable)`. No behavioural change.
- **Amended by change `m2-catalog-hardening` (archived `2026-08-02`)**, 1 MODIFIED requirement /
  6 scenarios, from
  `openspec/changes/archive/2026-08-02-m2-catalog-hardening/specs/brew-detection/spec.md`.
  "Detection is observable, re-evaluated state" gained a single-flight clause: overlapping
  re-evaluations coalesce onto the one evaluation genuinely in flight, while a request arriving
  after that evaluation settled — or after its caller was cancelled or abandoned — MUST run a fresh
  probe rather than be handed the earlier result. Previously the requirement mandated observability
  and publication on every re-evaluation but said nothing about coalescing, so a caller arriving
  after an evaluation settled could be handed a stale result presented as fresh. Its three existing
  scenarios ("Evaluated at launch", "Focus re-evaluation observes a newly installed brew",
  "Disappearing configured path transitions away") are preserved verbatim and three were added
  ("A settled evaluation does not answer a later re-evaluation", "An abandoned caller does not
  poison later re-evaluations", "Concurrent re-evaluations coalesce onto one probe"). The other four
  requirements are untouched. Capability total after the merge: **5 requirements / 15 scenarios**.
  This is the same invariant `catalog-sync` now states for sync, applied to detection so the M2
  `InstalledStore` has one correct exemplar to copy.
  - **Known gap, deliberately out of scope** (native review lineage `review-93ca396315542808`,
    WARNING, pre-existing — not caused by this change): `BrewDetectionStore.configuredPath`'s
    `didSet` fires a refresh that can still join an evaluation started under the *previous* path and
    adopt its answer. That evaluation is genuinely in flight, just for a different question, so the
    requirement above does not cover it. The fix is to key the coalescing slot by the request and is
    routed to change `m2-installed-inventory`, which copies this recipe.
