# Artifact Integrity Specification

## Purpose

Read-only visibility into the code-signing identity, notarization verdict, and quarantine and
provenance attributes of brew-managed artifacts. Owned by `Packages/CellarCore` capability
`SecurityKit`; excludes CVE data (`vulnerability-scanning`), disk accounting (`disk-usage`) and
every mutation (`package-mutation`).

## Requirements

### Requirement: Assessment is read-only, unprivileged and subprocess-free

Assessment MUST use the platform security and extended-attribute APIs directly. It MUST NOT spawn
`codesign`, `spctl`, `xattr` or any other subprocess, and MUST NOT parse a command's textual
output. It MUST NOT require root or administrator authorization, MUST NOT request an elevation
prompt, and MUST NOT write to, modify or relocate any inspected artifact. Every external dependency
MUST sit behind a protocol so the capability is testable with fakes.

#### Scenario: Inspection spawns nothing and writes nothing

- GIVEN a recording process launcher and a filesystem observer over a brew-installed cask app
- WHEN its signature, notarization and attributes are assessed
- THEN no process was launched, no elevation was requested, and no byte of the artifact changed

### Requirement: Signing and notarization verdicts are typed, including "could not assess"

Each assessed artifact MUST report a typed signing state (signed with identity details, ad-hoc,
unsigned, invalid) and a typed notarization state (notarized, not notarized, could not assess).
Signed results MUST carry the signing identifier, team identifier and authority chain when the
platform supplies them. A failed, cancelled, unreachable or otherwise inconclusive assessment MUST
report "could not assess" with its reason and MUST NOT be presented as either signed, unsigned,
notarized or not notarized.

#### Scenario: An inconclusive assessment is not a verdict

- GIVEN an artifact whose notarization ticket cannot be looked up
- WHEN its verdict is read
- THEN it reports "could not assess" with a reason
- AND it is neither counted as notarized nor as not notarized

#### Scenario: A signed artifact reports its identity

- GIVEN a validly signed, notarized cask app
- WHEN it is assessed
- THEN the signing identifier, team identifier and authority chain are reported alongside the
  notarized verdict

### Requirement: Quarantine and provenance are enumerated, decoded and cross-referenced

Brew-managed artifacts carrying `com.apple.quarantine` MUST be enumerated, and the attribute MUST be
decoded into its typed components rather than shown as a raw blob only; the raw value MUST remain
available. `com.apple.provenance` presence MUST be reported when present. Each quarantined artifact
MUST be presented together with its signing and notarization verdict so the user can see why launch
is or is not blocked. Any component whose encoding is not recognised MUST be reported as unknown,
never guessed.

#### Scenario: A quarantined artifact explains itself

- GIVEN a quarantined, unsigned brew-installed app
- WHEN it is listed
- THEN its decoded quarantine components, its raw attribute value and its unsigned verdict are
  shown together

#### Scenario: An unrecognised attribute component stays unknown

- GIVEN a quarantine attribute whose flag encoding is not recognised
- WHEN it is decoded
- THEN the unrecognised component reports unknown and the raw value is preserved verbatim

### Requirement: Scope is brew-managed artifacts only

Assessment MUST cover artifacts Homebrew installed: cask artifacts primarily, and formula keg
contents only where a signed, assessable artifact exists. The capability MUST NOT sweep
`/Applications` or any other location for artifacts Homebrew did not install, and MUST NOT report
on them.

#### Scenario: Non-brew applications are out of scope

- GIVEN applications installed outside Homebrew alongside brew-installed casks
- WHEN the artifact list is read
- THEN only brew-managed artifacts appear and no other location was enumerated

### Requirement: Assessment is per-item, off-main, streamed and cancellable

Assessment MUST run off the main actor and MUST NOT block the interface. Results MUST be delivered
incrementally per item rather than as a single terminal batch. Cancellation MUST be offered and MUST
take effect without leaving a partially adopted result presented as complete. A failure for one item
MUST be isolated to that item and MUST NOT fail the run.

#### Scenario: A slow lookup does not freeze or poison the run

- GIVEN one artifact whose assessment is slow or fails and several that succeed
- WHEN the run proceeds and is then cancelled
- THEN completed items remain shown, the failing item reports "could not assess", the interface
  stayed responsive, and the run is not presented as complete

### Requirement: Visibility does not become remediation

The capability MUST NOT offer any action that clears, removes or modifies a quarantine or
provenance attribute, in bulk or per item, and MUST NOT offer any re-signing, notarization or
Gatekeeper-assessment-changing action. No public surface of this capability MUST accept a write.

#### Scenario: No clearing affordance exists

- GIVEN the artifact integrity surface and its public capability surface
- WHEN its controls and operations are enumerated
- THEN none clears an attribute or changes an artifact's assessment state
