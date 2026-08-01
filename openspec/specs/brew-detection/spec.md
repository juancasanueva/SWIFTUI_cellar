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
see transitions.

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
- THEN observers receive a transition off `custom` to `configuredPathMissing`,
  `invalid(notExecutable)`, or `absent`
- AND a path that has vanished entirely is reported as `configuredPathMissing`, distinct from a
  path that still exists but is not executable

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
