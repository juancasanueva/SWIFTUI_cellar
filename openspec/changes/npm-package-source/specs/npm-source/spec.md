# npm-source Specification

New capability. Detecting the one `npm` binary Cellar reads, composing the environment it runs under,
reading the global inventory and the outdated report, the two npm mutation commands and their outcome
classification, and the opt-in toggle that gates every npm surface. Owned by `Packages/CellarCore`
targets `BrewProcess` (locator, environment, detection state) and `BrewClient` (payload sources,
decoder, commands, store). Every requirement is behaviour of `CellarCore` values; no SwiftUI view is
named.

Binding decisions (Engram `sdd/npm-package-source/decisions`): one npm selected by priority; toggle
default **off**; hybrid approach C; brew and npm mutations **serialized** across sources; upgrade verb
`npm install -g <name>@latest` through a validated spec token; Health copy-only; Settings shows the
selected npm's path, version and prefix and nothing more.

Session preflight (forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`,
`delivery_strategy=single-pr`, `review_budget_lines=8000`, `strict_tdd=true`. RDD disabled.

## Requirements

### Requirement: The npm source is opt-in, off by default, and nothing npm happens while it is off

The npm source MUST be gated by one persisted preference, default **off**, stored in `UserDefaults`
through a type taking an injectable suite (the `AutomaticUpdateChecks(defaults:)` precedent), never in
SwiftData. While the preference is off the system MUST spawn **no** npm process of any kind, MUST
publish no npm detection state other than `disabled`, MUST contribute no npm entry to any inventory,
count, filter, history presentation or copy, and MUST behave observably identically to a build without
this capability. Turning it on MUST start detection without a relaunch; turning it off MUST clear npm
inventory state and stop the npm refresh cadence without a relaunch. The choice MUST survive relaunch.

#### Scenario: With no stored value nothing npm is spawned or shown

- GIVEN a defaults suite with no stored npm preference and a recording process launcher
- WHEN the app's stores are composed and one full refresh cycle runs
- THEN the preference reads false, no npm process was spawned, and detection reports `disabled`
- AND the installed inventory, the outdated set and every count equal those of the same run without npm
- Verification: `unit`

#### Scenario: Enabling starts detection and disabling clears it, without relaunch

- GIVEN the preference off, a locator that would resolve a valid npm, and a running inventory
- WHEN the preference is turned on, then off again
- THEN after "on" detection publishes a detected state and the npm inventory populates
- AND after "off" detection publishes `disabled`, the npm entries leave the inventory, and no further
  npm process is spawned
- Verification: `unit`

### Requirement: One npm is selected by priority, and a configured path never falls through

Detection MUST resolve at most one npm binary, trying candidates in exactly this order and stopping at
the first that validates: the configured path; `/opt/homebrew/bin/npm`; `/usr/local/bin/npm`; Volta
`~/.volta/bin/npm`; fnm `~/Library/Application Support/fnm/aliases/default/bin/npm`; nvm's default
alias under `~/.nvm/versions/node/<default>/bin/npm`; mise `~/.local/share/mise/installs/node/*/bin/npm`.
A candidate validates only when it is executable and its `--version` output parses as a semantic
version. A configured path that fails MUST yield exactly one typed reason — `notExecutable`, `notNpm`
— as `invalid(reason:)`, or `configuredPathMissing` when it no longer exists, and detection MUST NOT
fall back to an auto-discovered candidate. No candidate anywhere MUST yield `absent` with guidance.
Validation MUST run only read-only npm invocations (`--version`, `prefix -g`). Candidate probing MUST
go through the existing `ExecutableProbing` seam so every rule is testable without a real npm.

#### Scenario: Priority order stops at the first valid candidate

- GIVEN valid npm binaries at `/usr/local/bin/npm` and under Volta, none at `/opt/homebrew/bin/npm`, and
  no configured path
- WHEN detection runs
- THEN the selected location is `/usr/local/bin/npm`
- AND the Volta candidate was not probed for its version
- Verification: `unit`

#### Scenario: An invalid configured path does not fall through

- GIVEN `/opt/homebrew/bin/npm` valid and a configured path whose `--version` prints `git version 2.4.0`
- WHEN detection runs
- THEN the state is `invalid(notNpm)`
- AND the resolved location is not `/opt/homebrew/bin/npm`, and no npm inventory probe runs
- Verification: `unit`

#### Scenario: A missing configured path is distinct from a non-executable one

- GIVEN a configured path that does not exist, and separately one that exists but is not executable
- WHEN detection runs for each
- THEN the first reports `configuredPathMissing` and the second `invalid(notExecutable)`
- Verification: `unit`

#### Scenario: No npm anywhere is a soft absent signal

- GIVEN no candidate validates and no configured path
- WHEN detection runs
- THEN the state is `absent`, resolved without throwing or blocking
- Verification: `unit`

### Requirement: A detected npm exposes its path, version and global prefix

A detected state MUST carry the executable path, the parsed version and the global prefix read from
`npm prefix -g` with the composed environment. That triple is the whole disclosure owed for
per-Node-version managers (nvm, fnm, Volta, mise); no further warning is required. Detection state MUST
be observable, evaluated when the source is enabled, re-evaluated on window focus and when the
configured path changes, coalesced per request on the same terms `brew-detection` states.

#### Scenario: The detected triple is exposed

- GIVEN a valid npm whose `--version` prints `10.9.2` and whose `prefix -g` prints `/opt/homebrew`
- WHEN detection completes
- THEN the state carries that path, version `10.9.2` and prefix `/opt/homebrew`
- Verification: `unit`

### Requirement: The npm environment prepends the selected bin directory and inherits only PATH and HOME

Every npm invocation MUST run with `PATH` equal to the selected npm's bin directory, a colon, then the
inherited `PATH`, so `#!/usr/bin/env node` resolves from a GUI process. `HOME` MUST be inherited so
`~/.npmrc` applies. The environment MUST pin exactly `NO_COLOR=1`, `npm_config_color=false`,
`npm_config_progress=false`, `npm_config_update_notifier=false`, `npm_config_fund=false`,
`npm_config_audit=false` and `npm_config_loglevel=warn`. No other inherited variable MUST be passed
through, and no `HOMEBREW_*` key MUST be set. Suppression happens at the source: no ESC byte (`0x1B`)
MUST be stripped from captured output to satisfy this rule.

#### Scenario: The composed environment is exactly PATH, HOME and the seven pins

- GIVEN an inherited environment containing `PATH`, `HOME`, `SHELL` and `HOMEBREW_NO_AUTO_UPDATE`, and a
  selected npm at `/Users/u/.volta/bin/npm`
- WHEN the environment is composed and any npm command runs through a recording launcher
- THEN the recorded `PATH` begins with `/Users/u/.volta/bin:` followed by the inherited `PATH`
- AND the recorded keys are exactly `PATH`, `HOME` and the seven pins with those exact values
- Verification: `unit`

#### Scenario: No ANSI escape byte survives capture

- GIVEN a real npm invocation under the composed environment
- WHEN every captured line's bytes are inspected
- THEN no line contains `0x1B`, and no line was altered to achieve that
- Verification: `integration` (self-skipping when no npm is present)

### Requirement: The global inventory decodes `npm ls -g --json --depth=0`, including an exit-1 payload

The npm inventory MUST come from exactly one `ls -g --json --depth=0` invocation per refresh. Decoding
MUST run off the main actor. The decoder MUST accept exit `0`, and MUST also accept exit `1` when
stdout parses as the expected document (npm's `ELSPROBLEMS` case), reading the document from **stdout
only**. Each key of the top-level `dependencies` object MUST become an installed entry with identity
`(kind: npm, name)` and its `version`; the top-level `name`/`version` (the prefix's own record) MUST NOT
become an entry. Every npm entry MUST report installed on request, unpinned, no tap, no auto-updates
declaration and no keg. A non-zero exit with unparseable stdout, or a document on stderr only, MUST be
reported as a failed acquisition, never as an empty inventory. This rule MUST NOT reach the three brew
JSON payload sources, which keep refusing non-zero exits.

#### Scenario: A clean listing decodes every dependency

- GIVEN exit `0` with a document naming `corepack@0.29.4` and `@angular/cli@18.2.0` under `dependencies`
- WHEN the payload is decoded
- THEN two entries exist, `(npm, corepack)` at `0.29.4` and `(npm, @angular/cli)` at `18.2.0`
- AND both report installed on request, unpinned and no tap
- Verification: `unit`

#### Scenario: An exit-1 listing with a complete document still decodes

- GIVEN exit `1`, an `ELSPROBLEMS` line on stderr and a complete document on stdout
- WHEN the payload is decoded
- THEN the entries from the document are returned and no failure is reported
- Verification: `unit`

#### Scenario: Unparseable stdout on a non-zero exit is a failure, not empty

- GIVEN exit `1` with empty stdout, and separately exit `0` with the document on stderr only
- WHEN each is decoded
- THEN each reports a failed acquisition
- AND neither yields an empty inventory presented as healthy
- Verification: `unit`

### Requirement: Outdated state comes from `npm outdated -g --json` with exit 0 or 1, and is tri-state fresh

Outdated state MUST come from one `outdated -g --json` invocation, accepted at exit `0` (nothing
outdated; empty stdout or `{}`) and at exit `1` with a parseable stdout document. A package MUST be
outdated exactly when its `current` differs from its `latest`, because the upgrade verb reaches
`latest`; `wanted` MUST be preserved but MUST NOT decide outdated-ness. The offered version exposed for
snooze equality MUST be `latest`. The result MUST be one of three typed states — `fresh(checkedAt:)`,
`notChecked`, `failed(reason:)` — and only `fresh` MUST contribute npm entries to the outdated set. Any
other exit, unparseable stdout, spawn failure or network error MUST yield `failed`, and neither `failed`
nor `notChecked` MUST ever be presented, counted or summarised as "up to date".

#### Scenario: An exit-1 report marks packages outdated by `latest`

- GIVEN exit `1` with `corepack {current: 0.29.4, wanted: 0.29.4, latest: 0.31.0}` and
  `typescript {current: 5.6.2, wanted: 5.6.2, latest: 5.6.2}`
- WHEN the report is decoded and the outdated set read
- THEN the state is `fresh`, `corepack` is outdated toward `0.31.0`, and `typescript` is not
- Verification: `unit`

#### Scenario: A clean exit-0 report is fresh and empty

- GIVEN exit `0` with empty stdout, and separately with `{}`
- WHEN each is decoded
- THEN each yields `fresh` with no outdated npm entry
- Verification: `unit`

#### Scenario: Offline is failed, never up to date

- GIVEN a report that exits non-zero with `ENOTFOUND` on stderr and no stdout document
- WHEN it is decoded and the summary read
- THEN the state is `failed` naming a network reason
- AND no npm entry is in the outdated set, and the summary does not report npm as up to date
- Verification: `unit`

#### Scenario: Before any check the state is not checked

- GIVEN a freshly enabled source whose outdated check has not yet run
- WHEN the state is read
- THEN it is `notChecked`, distinct from `fresh` with zero outdated and from `failed`
- Verification: `unit`

### Requirement: The npm outdated cadence is independent of brew's activation-driven refresh

The outdated check MUST run on its own cadence driven by an injected clock: once when the source becomes
detected, once at every npm-inventory invalidation, and periodically thereafter. It MUST NOT be coupled
to window focus, app activation or the brew inventory refresh, because it needs the network and can be
slow. A check in flight MUST coalesce overlapping requests; a request after settlement MUST run fresh.
A failed check MUST NOT be retried in a tight loop; the next periodic tick retries it.

#### Scenario: Activation does not trigger the npm check

- GIVEN a detected, enabled source and a recording launcher
- WHEN five focus events occur within one period of the injected clock
- THEN no additional `outdated -g --json` invocation is recorded
- AND exactly one is recorded when the clock advances one period
- Verification: `unit`

#### Scenario: An npm mutation's terminal outcome forces exactly one npm refresh

- GIVEN a submitted npm upgrade reaching each of success, failure and cancellation
- WHEN each reaches its terminal outcome
- THEN exactly one `ls -g` and exactly one `outdated -g` invocation follow in each case
- AND no `brew info --installed --json=v2` invocation is recorded
- Verification: `unit`

### Requirement: npm commands are a separate family with fixed argv vectors and validated names

The capability MUST expose exactly two npm mutations: upgrade and uninstall, entering the shared
mutation spine through the shared abstraction with `source` = npm, never as a case of the six brew
package commands. Upgrade argv MUST be exactly `install -g <name>@latest`, where `<name>@latest` is one
argv element produced by a validated spec token, never by string interpolation in the argv body.
Uninstall argv MUST be exactly `uninstall -g <name>`. Both MUST be classified as mutations, MUST declare
the `npmInventory` invalidation domain only, and MUST NOT declare the installed set. Uninstall MUST
require confirmation with the ordinary package-removal disclosure presenting the exact `npm uninstall -g
<name>` text; upgrade MUST NOT. Construction MUST go through the same `MutationName.isSafe` gate (empty,
whitespace-only and leading `-` rejected) plus one npm rule: `@` MAY appear only as the first character
of a scoped name. The command file MUST sit at the top level of the command sources so the shipped
structural argv scan covers it.

#### Scenario: Upgrade and uninstall argv are fixed vectors

- GIVEN the installed npm package `typescript`
- WHEN upgrade and uninstall commands are built
- THEN their argvs are exactly `install -g typescript@latest` and `uninstall -g typescript`
- AND each argv element is a separate value, with `typescript@latest` a single element
- Verification: `unit`

#### Scenario: A scoped name survives intact

- GIVEN the installed npm package `@angular/cli`
- WHEN upgrade is built
- THEN the argv is exactly `install -g @angular/cli@latest`
- Verification: `unit`

#### Scenario: Hostile names are rejected at construction

- GIVEN names ``, ` `, `--force`, `typescript@5`, `a b`
- WHEN a command is constructed for each
- THEN construction fails for every one and no argv is produced
- Verification: `unit`

#### Scenario: The structural argv scan covers the npm command file

- GIVEN the shipped scan over every top-level `*Command.swift`
- WHEN it runs
- THEN the npm command file is among the scanned files, contains `MutationName.isSafe`, and contains no
  `\(`, `joined(` or `+ " "` in its `arguments` body
- Verification: `unit`

#### Scenario: Uninstall confirms and upgrade does not

- GIVEN the npm package `typescript`
- WHEN uninstall, then upgrade, are requested
- THEN uninstall raises one confirmation whose text contains exactly `npm uninstall -g typescript`
- AND upgrade is submitted directly with no confirmation
- Verification: `unit`

### Requirement: npm outcomes are classified by npm's own signatures, never brew's

An npm operation that exits `0` MUST be successful regardless of output. A non-zero exit whose stderr
tail contains `EACCES` or `EPERM` MUST be the typed needs-privileges failure, echoing the exact `npm …`
command for Terminal and never escalating or prompting. A non-zero exit whose stderr tail contains
`ENOTFOUND`, `ETIMEDOUT`, `ECONNREFUSED` or `EAI_AGAIN` MUST be a generic failure whose message names a
network reason. Any other non-zero exit MUST be a generic failure with the verbatim log. Brew's lock,
sudo-prompt and untrusted-tap signatures MUST NOT classify an npm operation, and the failure message
MUST say npm exited, never Homebrew.

#### Scenario: EACCES is needs-privileges with the exact command

- GIVEN an npm upgrade exiting `243` with `npm error code EACCES` on stderr
- WHEN it reaches its terminal outcome
- THEN it is the typed needs-privileges failure and its guidance contains `npm install -g typescript@latest`
- AND no sudo, password or retry occurred
- Verification: `unit`

#### Scenario: Network errors and unknown errors are failures; exit 0 is success

- GIVEN three runs: exit `1` with `ENOTFOUND`; exit `1` with an unrecognised message; exit `0` with a
  `WARN` line
- WHEN each reaches its terminal outcome
- THEN the first is a failure naming the network, the second a generic failure with its log, and the
  third a success
- AND the message of neither failure mentions Homebrew
- Verification: `unit`

### Requirement: No npm mutation is built or spawned while npm is disabled, absent or invalid

When the source is off, or detection reports `absent`, `invalid` or `configuredPathMissing`, npm
mutation affordances MUST be unavailable with read-only guidance naming npm, nothing MUST be spawned or
thrown, and brew mutations MUST be unaffected. When npm later becomes detected, npm mutations MUST
become available without relaunch.

#### Scenario: Absent npm leaves brew available and npm unavailable

- GIVEN brew detected and npm `absent`
- WHEN a brew upgrade and an npm upgrade are requested
- THEN the brew upgrade is submitted normally
- AND the npm affordance reports unavailable with npm guidance, and no npm process is spawned
- Verification: `unit`
