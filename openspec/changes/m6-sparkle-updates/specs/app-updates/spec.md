# Delta for app-updates

New capability — there is no `openspec/specs/app-updates/spec.md` yet, so this delta is **ADDED-only**:
**7 requirements / 31 scenarios**. Nothing is MODIFIED, REMOVED or RENAMED, so `rules.archive`'s
destructive-delta warning does not fire. On archive this becomes the project's **22nd** capability.

This capability owns **what must be true of Cellar's update surface**: what version the running app
claims to be and how two versions compare, what update feed the running bundle trusts and how that
trust is fixed, what an appcast document must carry before Cellar will treat it as valid, when the app
is allowed to reach the network to look for an update, what the user can always do by hand, what the
update surfaces are allowed to say, and what the update code is allowed to reach.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m6-sparkle-updates/` + Engram canonical project
`swiftui_cellar`), `delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`.
RDD disabled clone-local.

## Admissibility under `rules.specs` — judged, not assumed

`rules.specs` carries two clauses. The first ("Given/When/Then + RFC 2119") is satisfied throughout.
The second — "specify observable behavior of `CellarCore` types without referencing SwiftUI views" —
**has a subject here**, unlike the previous slice: this change adds `CellarCore` types *and* two user
surfaces (a Settings group and an app-menu command).

**Judgment: admissible, with a discipline.** Every requirement below is written against the observable
behaviour of `CellarCore` types (`AppVersion`, `AppcastDocument`, `UpdateCheckPresentation`, the
`AppUpdating` protocol) or against the running bundle. Where a user surface is unavoidable it is named
by **what the user sees** — "the Settings Updates group", "the app menu" — never by a SwiftUI type, a
view file, or a property wrapper. No requirement below names `SPUUpdater`, `SPUStandardUpdaterController`,
a Sparkle API, a build setting, a workflow step, or a project-file edit: those are *how* the contract is
met and belong to `design.md`.

Every scenario declares exactly one verification class, and no requirement is written that no test or
recorded observation could ever check:

| Class | Meaning | Count |
|---|---|---|
| `unit-core` | RED-first assertion in `Packages/CellarCore` `UpdatesTests`, run by `swift test --package-path Packages/CellarCore`; the external updater is driven by a fake conforming to `AppUpdating` | **19** |
| `unit-app` | RED-first assertion in `cellarTests`, in the shipped `AppSecuritySources` / `#filePath` idiom (reads the repository source or the test host's bundle information off disk) | **11** |
| `manual-evidence` | no harness can exist — the vendored updater framework ships no test harness — so the maintainer's observed output is recorded in `design.md` and the verify report | **1** |

What stays **design-owned and is deliberately absent here**: the choice of updater framework and its
version pin, the SPM/project-file integration shape, where the partial property list lives, how the
appcast is produced and published by CI, the persistence mechanism behind the Updates toggle, the
key-value-observation bridge and its main-actor hops, and release-notes presentation. None of those is
an observable property of a running Cellar.

Traceability: **D1** → "Automatic update checks stay off until the user asks" and "An explicit update
check is always reachable"; **D2** → no subject here (it lands on the `release-distribution` delta);
**D3** → the merge-preserves-history scenario; **D4** → the prerelease scenarios; **D5/D6** → "The feed
the running app trusts is fixed inside the bundle" and "The updater reaches nothing but the updater".
Proposal risks 1, 7, 8, 9 and 12 each land on a scenario below.

## ADDED Requirements

### Requirement: The app reports its own version honestly, and two versions compare unambiguously

The app MUST report the version pair it was built with — the bundle's short version string as the
marketing version and the bundle's version as the build number — and MUST NOT display, transmit, or
compare a version it did not build with.

Two versions MUST compare by marketing version first and by build number second, so that a rebuild of
the same marketing version is newer than its predecessor. A marketing version carrying a prerelease
suffix MUST parse as a prerelease and MUST order **below** the same marketing version without the
suffix. A version string the app cannot parse MUST produce a **typed failure outcome** — never a crash,
never a silent fallback to a fabricated version, and never an ordering result.

#### Scenario: The version pair is read from the running bundle

- GIVEN a bundle whose short version string is `1.0.0` and whose bundle version is `7`
- WHEN the app's version is read
- THEN it reports marketing version `1.0.0` and build number `7`
- Verification: `unit-core`

#### Scenario: A higher marketing version is newer

- GIVEN versions `1.0.1 (1)` and `1.0.0 (9)`
- WHEN they are compared
- THEN `1.0.1 (1)` is the newer of the two
- AND the build number does not override the marketing version
- Verification: `unit-core`

#### Scenario: A rebuild of the same marketing version is newer

- GIVEN versions `1.0.0 (2)` and `1.0.0 (1)`
- WHEN they are compared
- THEN `1.0.0 (2)` is the newer of the two
- Verification: `unit-core`

#### Scenario: A prerelease sorts below its own release

- GIVEN versions `0.0.1-rc.1` and `0.0.1`
- WHEN they are parsed and compared
- THEN `0.0.1-rc.1` is reported as a prerelease
- AND `0.0.1` is the newer of the two
- Verification: `unit-core`

#### Scenario: A malformed version is a typed outcome, not a crash

- GIVEN a version string that is empty, non-numeric, or otherwise unparseable
- WHEN it is parsed
- THEN parsing reports a typed failure identifying the input as invalid
- AND no comparison result, no default version, and no crash is produced
- Verification: `unit-core`

### Requirement: The feed the running app trusts is fixed inside the bundle

The running bundle MUST carry, readable from its own information dictionary, both the update feed
location and the public key used to verify update signatures.

The feed location MUST be an `https` URL served from `juancasanueva.github.io`; a `http` feed, a feed on
any other host, or a missing feed location MUST be treated as a build defect that fails a test rather
than as a runtime condition to recover from. The signature-verification key MUST be a base64-encoded
**32-byte Ed25519 public key**.

Neither value MUST be overridable at run time: no user setting, environment variable, command-line
argument, configuration file, or network response MUST be able to substitute a different feed or a
different verification key. A key supplied at run time is a key an attacker can supply. The public key
is public by construction — it ships inside every copy of the app — and MUST NOT be handled as a secret;
the corresponding private key MUST NOT exist anywhere in the repository in any form.

#### Scenario: The bundle carries the exact feed URL

- GIVEN the running application bundle's information dictionary
- WHEN the update feed value is read
- THEN it is exactly `https://juancasanueva.github.io/SWIFTUI_cellar/appcast.xml`
- AND its scheme is `https`
- Verification: `unit-app`

#### Scenario: The bundle carries a well-formed verification key

- GIVEN the running application bundle's information dictionary
- WHEN the update public key value is read
- THEN it is present, non-empty, and base64-decodes to exactly 32 bytes
- Verification: `unit-app`

#### Scenario: Nothing in the app can substitute a different feed or key

- GIVEN every source file in the app target and in `CellarCore`
- WHEN they are inspected structurally
- THEN none of them writes, injects, or reads an alternative update feed location or verification key
- AND no private signing key material appears anywhere in the repository
- Verification: `unit-app`

### Requirement: An appcast document is valid only if every field an update depends on is present and well formed

Cellar MUST be able to validate an appcast document **offline, without network access and without the
updater framework**, so that a malformed feed is caught by a test before an installed copy of the app
ever fetches it.

An item MUST be rejected unless it carries: a signature attribute, a numeric byte length, a version, a
short version string, an enclosure whose URL uses `https` and whose host is `github.com`, and a minimum
system version of exactly `26.0`. An item whose version carries a prerelease suffix MUST NOT appear in
the feed at all, and a document containing one MUST be rejected. Publishing a new version MUST preserve
every previously published item, ordered newest first; a valid document MUST NOT lose history.

#### Scenario: A complete item validates

- GIVEN an appcast document with one item carrying a signature, a numeric length, a version, a short
  version string, an `https` `github.com` enclosure, and minimum system version `26.0`
- WHEN it is validated
- THEN validation succeeds
- Verification: `unit-core`

#### Scenario: A missing signature is rejected

- GIVEN an appcast item with no signature attribute
- WHEN the document is validated
- THEN validation fails, naming the missing signature
- AND the document is not treated as partially usable
- Verification: `unit-core`

#### Scenario: A missing or non-numeric length is rejected

- GIVEN an appcast item whose enclosure length is absent, empty, or not a number
- WHEN the document is validated
- THEN validation fails, naming the length
- Verification: `unit-core`

#### Scenario: A missing version or short version string is rejected

- GIVEN an appcast item missing either its version or its short version string
- WHEN the document is validated
- THEN validation fails, naming the missing field
- Verification: `unit-core`

#### Scenario: An enclosure that is not an https github.com URL is rejected

- GIVEN an appcast item whose enclosure URL uses `http`, or whose host is not `github.com`
- WHEN the document is validated
- THEN validation fails, naming the enclosure
- Verification: `unit-core`

#### Scenario: A wrong minimum system version is rejected

- GIVEN an appcast item whose minimum system version is absent or is not `26.0`
- WHEN the document is validated
- THEN validation fails, naming the minimum system version
- Verification: `unit-core`

#### Scenario: A prerelease never appears in the feed, and a merge keeps history

- GIVEN a feed already carrying items for `1.0.0` and `1.0.1`
- WHEN an item for `1.1.0` is merged and the resulting document is validated
- THEN validation succeeds and all three items are present, ordered `1.1.0`, `1.0.1`, `1.0.0`
- AND a document containing any hyphenated prerelease version is rejected
- Verification: `unit-core`

#### Scenario: An installed build actually replaces itself from the published feed

- GIVEN a prerelease build installed in `/Applications` and a newer stable version published to the
  feed
- WHEN the user checks for updates and accepts the offered update
- THEN the update's signature verifies against the key in the running bundle and the app is replaced
  in place
- AND the replaced bundle launches through Gatekeeper with networking disabled
- Verification: `manual-evidence`

### Requirement: Automatic update checks stay off until the user asks, and the app's own setting is the authority

An update check is network egress, and Cellar gates every other egress behind explicit consent.
Automatic update checking MUST therefore be **off on a fresh install** and MUST stay off until the user
turns it on.

The app's **own persisted setting** MUST be the authority: at every launch the app MUST write that
setting to the updater, so that neither a value baked into the bundle nor a value the updater framework
persisted on its own can decide whether Cellar reaches the network. The app MUST NOT ship a bundled
default that enables automatic checking, and MUST NOT present the framework's own prompt asking the
user to enable automatic checks.

#### Scenario: A fresh install does not check automatically

- GIVEN a fresh install with no stored update preference
- WHEN the update preference is read
- THEN automatic update checking is off
- Verification: `unit-app`

#### Scenario: The user's choice survives a relaunch

- GIVEN a user who has turned automatic update checking on
- WHEN the app is relaunched
- THEN the preference still reads as on
- AND turning it off and relaunching reads as off
- Verification: `unit-app`

#### Scenario: The persisted preference is written to the updater at launch

- GIVEN a persisted preference and an updater whose automatic-check flag currently disagrees with it
- WHEN the launch-time update wiring runs
- THEN the updater's automatic-check flag equals the persisted preference
- AND this holds for both the on and the off case
- Verification: `unit-core`

#### Scenario: No bundled default and no framework prompt can enable checking

- GIVEN the running application bundle's information dictionary and the app's source
- WHEN they are inspected
- THEN no bundled key enables automatic update checking
- AND nothing in the app presents the updater framework's own enable-automatic-checks prompt
- Verification: `unit-app`

### Requirement: An explicit update check is always reachable

An explicit user action is its own consent, so a **"Check for Updates…"** command MUST be present in the
app menu, immediately after the About item, on every launch — including when automatic checking is off.

The command MUST be disabled **only** while a check genuinely cannot run, which in practice means a
check is already in flight. It MUST NOT be disabled because automatic checking is off, because no update
was found last time, or because the app has never checked. Invoking it MUST start exactly one check.

#### Scenario: The command is present in the app menu

- GIVEN the app's menu commands
- WHEN they are inspected structurally
- THEN a "Check for Updates…" command is declared in the app-information menu group, after the About
  item
- Verification: `unit-app`

#### Scenario: The command is enabled while automatic checking is off

- GIVEN an updater that can check, with automatic checking off
- WHEN the command's enabled state is evaluated
- THEN it is enabled
- Verification: `unit-core`

#### Scenario: The command is disabled only while a check is in flight

- GIVEN an updater reporting that it cannot currently check because a check is in flight
- WHEN the command's enabled state is evaluated
- THEN it is disabled
- AND it becomes enabled again as soon as the updater reports it can check
- Verification: `unit-core`

#### Scenario: Invoking the command starts exactly one check

- GIVEN an updater that can check
- WHEN the command is invoked once
- THEN exactly one update check is started
- Verification: `unit-core`

### Requirement: No update surface states something untrue, and no inert surface is rendered

Every update surface MUST describe the state the app is actually in. An app that has never checked for
updates MUST say so in words; it MUST NOT display a fabricated, defaulted, or zero date. Once a check
has completed, the surface MUST report that check's date.

The Settings **Updates** group MUST contain exactly the controls that have behaviour behind them: the
automatic-checking toggle and the last-checked label. Any control the design sketches for a capability
Cellar does not have — notably an update-channel picker — MUST be absent rather than present-but-inert.

#### Scenario: A never-checked app says so

- GIVEN no recorded last-check date
- WHEN the last-checked text is produced
- THEN it states that the app has never checked
- AND it contains no date, no placeholder date, and no epoch value
- Verification: `unit-core`

#### Scenario: A checked app reports the date it checked

- GIVEN a recorded last-check date
- WHEN the last-checked text is produced
- THEN it states that the app last checked on that date
- Verification: `unit-core`

#### Scenario: The label follows the updater's recorded date

- GIVEN an updater whose recorded last-check date changes from absent to a date
- WHEN the last-checked text is produced again
- THEN it changes from the never-checked wording to that date
- Verification: `unit-core`

#### Scenario: The Updates group renders nothing inert

- GIVEN the Settings Updates group
- WHEN its controls are inspected structurally
- THEN it declares only the automatic-checking toggle and the last-checked label
- AND no update-channel picker or other control without behaviour behind it is present
- Verification: `unit-app`

### Requirement: The updater reaches nothing but the updater

The dependency on the third-party updater framework MUST be confined to **exactly one file** in the
repository, proven by a source sweep rather than by convention, and no user-interface file MUST
reference the framework's types.

The update logic that Cellar owns MUST live in a `CellarCore` module that declares **no dependencies**,
so that "the updater cannot reach Homebrew, the package catalog, or persisted app data" is a
compile-time fact rather than a review comment. That module MUST NOT gain a dependency on any other
`CellarCore` target or on any external package.

#### Scenario: Exactly one file imports the updater framework

- GIVEN the comment-stripped source of every Swift file in the repository
- WHEN imports of the updater framework are counted
- THEN exactly one file imports it
- Verification: `unit-app`

#### Scenario: No user-interface file names the framework's types

- GIVEN the comment-stripped source of every view file in the app target
- WHEN it is inspected for the updater framework's updater and updater-controller types
- THEN none of them appears
- AND every update surface speaks only to Cellar's own update protocol
- Verification: `unit-app`

#### Scenario: The update module declares no dependencies

- GIVEN the `CellarCore` package manifest
- WHEN the update target is inspected
- THEN its dependency list is empty
- AND it depends on no Homebrew, catalog, or persistence target and on no external package
- Verification: `unit-app`

## Notes for archive

- On archive this delta is promoted to `openspec/specs/app-updates/spec.md` as the capability's first
  main spec, with the header, the verification-class table and a provenance section added, and the
  requirement and scenario bodies carried over byte-identically — the precedent set by
  `2026-08-23-m6-release-pipeline`.
- **Execution honesty to carry into provenance:** one scenario is `manual-evidence` and cannot be
  observed until a Developer ID certificate, the repository secrets, GitHub Pages, and a stable tag all
  exist. The remaining 30 scenarios are runnable from the merge commit.
