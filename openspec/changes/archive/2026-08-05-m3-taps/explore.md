## Exploration: M3-2 Tap Management (`m3-taps`)

Focused exploration for PRD M3-2 only. Repository evidence was read at clean `main` commit
`023a519`, after M3-1 was archived and merged. Artifact store is hybrid; this OpenSpec file is the
authoritative copy and Engram topic `sdd/m3-taps/explore` is its persisted mirror.

### Current State

M3-1 shipped the generalization M3-2 was expected to consume:

- `BrewMutating` is a `Sendable`-only protocol exposing `arguments`, namespaced `verb`, optional
  `packageID`, `requiresConfirmation`, `invalidates`, and family-owned outcome classification.
  `OperationCenter.submit` and `request` take generic `some BrewMutating` parameters; stored activity
  and confirmation values use `AnyBrewMutation`.
- `InvalidationScope` currently declares `.installedInventory` and `.services`; bits for taps and
  disk usage were deliberately reserved but not declared. `MutationGates` already fans one command
  out to every intersecting domain gate and closes the same scopes at the terminal funnel.
- The shared terminal funnel already provides FIFO mutation serialization, activity identity, exact
  argv/copy-command, live logs, cancel, typed outcomes, one history entry, and per-domain refresh.
  `HistoryDraft.packageID` is optional, so a tap operation is representable without a persistence
  schema change.
- The existing confirmation mechanism is reusable for submitting a `TapCommand`, but its current
  presentation projection is not sufficient for M3-2: `ConfirmationRequest` carries commands only,
  while `MutationConfirmation` hard-codes uninstall/zap/bulk package copy. A force-untap confirmation
  must carry a typed disclosure naming affected installed packages. That metadata belongs beside the
  confirmation request, not in `BrewMutating`.
- `InstalledPackage.tap` is already decoded from the single installed snapshot, and
  `InstalledInventory` exposes both its ordered packages and `PackageID` lookup. Filtering the
  installed snapshot by exact tap name is the honest source for the force-untap blast radius.
- `package-detail` PD6 remains load-bearing: the catalog contains only `homebrew/core` and
  `homebrew/cask`; third-party packages are ordinary catalog misses. Current catalog lookup explicitly
  treats a miss as normal. M3-2 must not insert tap packages into `CatalogSnapshot`,
  `PackageSearchIndex`, or `PackageDetailView` to make tap rows navigable.
- `ContentView` is an exhaustive three-column `NavigationSplitView` over `AppSection`; M3-1 added
  `.services`, its store, its selection, and app-root gate wiring. Taps can follow the same
  composition shape with its own identity and selection, but it does not need a poll loop.
- Tests use Swift Testing, fixture-first decoders, protocol fakes, exact argv assertions,
  `#require` for dependent values, parameterized hostile inputs, structural scans with positive
  anchors, and store tests for single-flight/ordinal/last-good behavior. No broad test run was needed
  for this exploration.

The closed U2 probe remains authoritative: Homebrew `6.0.14-50-g7b0f22a` returned nine installed
taps from `brew tap-info --installed --json` in 0.97 s. Records include `name`, `user`, `repo` and
`repository`, `path`, `installed`, `official`, `formula_names`, `cask_tokens`, `remote`,
`custom_remote`, `private`, `trusted`, `formula_files`, `cask_files`, `command_files`, `HEAD`,
`last_commit`, and `branch`. `formula_names` are fully qualified (for example
`agavra/tap/tuicr`), and `last_commit` is prose such as `3 weeks ago`; it must not be parsed as a
date. No brew probe should be repeated for proposal.

### Exact Reusable Seams

| Concern | Current seam | M3-2 use |
|---|---|---|
| Structured read | `ServicesPayloadSourcing` / `ServicesRun` and `InstalledPayload` patterns | A `TapPayloadSourcing` seam, pure exit/stdout reduction, tolerant off-main JSON decoder, and closed tap error enum |
| Store | `InstalledStore` / `ServicesStore` | `TapStore`: single-flight by installation URL plus invalidation mark, ordinal-guarded adoption, last-good survival, brew-absent guidance |
| Mutation command | `BrewMutating` + validated target wrappers | `TapCommand` conforms unchanged to the protocol; use a `TapTarget` over the shared non-empty/no-leading-dash/no-whitespace safety rule |
| Serialization/activity | generic `OperationCenter.submit` and `AnyBrewMutation` | Tap, plain untap, and force untap inherit FIFO, logs, cancel, copy-command, outcome, and history |
| Invalidation | `InvalidationScope` + `MutationGates` | Add `.taps`; tap and plain untap invalidate taps, while force untap invalidates taps plus installed inventory |
| Confirmation | generic `OperationCenter.request` + `ConfirmationBox` | Keep typed commands; add typed disclosure context for trust and force blast radius without adding UI copy or affected packages to `BrewMutating` |
| Installed cross-reference | `InstalledPackage.tap`, `InstalledInventory.packages/package(_:)` | Exact tap-name filter for installed badges, force disclosure, and installed-list handoff |
| History | optional `HistoryDraft.packageID`, searchable verb/argv | Null package identity, absent versions, namespaced tap verbs; no schema change |
| App composition | `AppSection`, `ContentView`, `cellarApp`, `MutationGates` | Add Taps sidebar/list/detail selection, one tap gate, store/refresher wiring, and tap-aware confirmation presentation |

**BrewMutating verdict:** M3-1's generic, `Sendable`-only shape remains reusable **without bending**.
`TapCommand` needs no new protocol requirement and should use the default classifier unless verified
tap-specific no-change markers justify a family override. The required widening is in confirmation
disclosure and presentation, not in the mutation abstraction.

### M3-2 Scope Confirmation

In scope:

- A tap list backed by structured `tap-info --installed --json`. This one probe can provide both the
  list and detail snapshot; separately running textual `brew tap` on every refresh would add a second
  process and a consistency join without adding information.
- Honest official-versus-third-party framing. Modern Homebrew may have no local `homebrew/core` or
  `homebrew/cask` clones because those official repositories are served through Homebrew's JSON API.
  Their absence from the installed-tap payload is normal, not breakage.
- Structured tap detail and package-per-tap inventory from `formula_names` and `cask_tokens`.
  Preserve published names first; normalize a fully-qualified formula name only by removing the
  selected tap's exact `name + "/"` prefix.
- Installed-package cross-reference from `InstalledPackage.tap`, including package kind so a formula
  and cask with the same token remain distinguishable. This must not route third-party records into
  the core/cask catalog.
- `brew tap user/repo`, plain `brew untap user/repo`, and a separate
  `brew untap --force user/repo` mutation.
- A third-party trust warning before add. The exact typed command shown is the exact argv submitted;
  warning prose is never parsed back into argv.
- Plain untap as the normal removal path. Force untap is a separate destructive action and never an
  implicit retry or hidden flag.
- Force confirmation naming **every currently affected installed package individually**, with kind,
  not only a count. A changed affected set must fail closed and request fresh confirmation rather
  than execute against stale disclosure.
- Tap refresh after every tap-family terminal outcome; force untap also refreshes installed inventory.
  Failed and cancelled terminals retain the same exactly-once per-declared-domain obligation.
- One history entry per tap mutation with a null package identity, exact argv, outcome, and a
  namespaced verb that remains searchable by `tap`, `untap`, and `force`.

### Non-Goals

- Brewfile import/export (M5), package installation from the tap inventory, tap search integration,
  or third-party package ingestion into the core/cask catalog.
- Weakening or modifying package-detail PD6; adding a third-party catalog-detail fallback; adding
  tap-derived fields to `CatalogPackage`.
- Automatically cloning `homebrew/core` or `homebrew/cask`, or presenting their API-backed state as a
  mutable local tap.
- Cleanup, disk usage, services follow-ups, security scanning of tap contents, or arbitrary Git
  repository management beyond the product decision below.
- Enabling RDD, creating receipts, implementing code, running broad tests, or changing delivery
  mechanics in this phase.

### Affected Areas

- `Packages/CellarCore/Sources/BrewClient/BrewMutating.swift` — declare `.taps`; existing protocol
  and `MutationGates` remain otherwise unchanged.
- `Packages/CellarCore/Sources/BrewClient/OperationCenterBulk.swift` — confirmation disclosure must
  represent trust and force-untap package lists without reconstructing argv from display text.
- `Packages/CellarCore/Sources/BrewClient/OperationCenter.swift` — app composition will register the
  tap gate; the generic submission funnel itself needs no redesign.
- `Packages/CellarCore/Sources/BrewClient/InstalledModels.swift` — consumed as-is for exact tap
  cross-reference; changing the installed projection is not currently justified.
- `Packages/CellarCore/Sources/Catalog/PackageSearchIndex.swift` — protected boundary; third-party tap
  inventory must never enter it.
- Likely new `Packages/CellarCore/Sources/BrewClient/TapCommand.swift` — validated tap target and the
  three explicit mutation shapes.
- Likely new `TapPayloadSource.swift`, `TapWire.swift`, `TapStore.swift`, and `TapProjection.swift` —
  acquisition, tolerant decode, freshness, package normalization, and installed cross-reference.
- `cellar/Shell/AppSection.swift`, `cellar/ContentView.swift`, `cellar/cellarApp.swift` — Taps section,
  independent selection, store, gate, terminal refresh owner, and root injection.
- Likely new `cellar/Taps/` views — official API explanation, third-party list/detail, package
  inventory, add, plain untap, and force untap affordances.
- `cellar/Activity/MutationConfirmation.swift` — replace package-only title/label assumptions with a
  typed family-aware projection; do not switch on rendered strings.
- `Packages/CellarCore/Tests/BrewClientTests/` — tap fixtures, decoder/source/store/projection/command,
  invalidation, confirmation, history, PD6 guard, and structural tests following M3-1 conventions.

### Approaches

1. **Dedicated tap inventory and command family on the shared spine** — one structured tap snapshot,
   a tap-owned store/projection, and `TapCommand: BrewMutating`.
   - Pros: preserves PD6, reuses M3-1 without protocol changes, keeps one FIFO/history/activity path,
     supports exact scoped invalidation, and isolates Homebrew schema tolerance.
   - Cons: confirmation needs a typed disclosure extension; package names require careful
     qualification handling; app composition gains another store/gate.
   - Effort: Medium/High.

2. **Fold tap packages into catalog or installed package-detail models** — make tap records look like
   catalog packages so existing detail navigation works.
   - Pros: superficially reuses existing package UI.
   - Cons: directly weakens PD6, pollutes the 16k-record search/index contract, conflates repository
     inventory with installed state, and makes ordinary third-party catalog misses exceptional.
   - Effort: High and architecturally incorrect.

3. **Run tap mutations through a separate centre** — keep tap-specific commands and confirmation
   outside `OperationCenter`.
   - Pros: locally small first diff.
   - Cons: breaks serialization against Homebrew's process-external lock and duplicates activity,
     cancel, logs, history, error classification, and invalidation behavior.
   - Effort: Low initially, high permanently; rejected.

### Product Decisions Required Before Proposal

1. **How should official core/cask sources appear when they are not local taps?**
   - Recommended: a non-actionable **Official sources** section containing Homebrew Core and Homebrew
     Cask, explicitly labelled “API-backed; no local tap required,” followed by the mutable
     third-party taps section.
   - Tradeoff: clearer than banner-only copy and stable in an empty state, but the rows must be
     visually distinct so users do not expect tap/untap controls.

2. **What add surface ships, and how strong is the trust warning?**
   - Recommended: M3-2 accepts canonical `user/repo` only and requires an explicit confirmation on
     every add, naming the tap and exact command and warning that third-party taps can distribute
     untrusted formulae/casks. Defer URL/custom-remote input.
   - Tradeoff: materially smaller and safer input surface; advanced users with private/custom remotes
     still need Terminal. Supporting arbitrary URLs requires URL/credential handling and stronger
     source disclosure.

3. **What happens when a package name in a tap is selected?**
   - Recommended: installed matches offer **Show in Installed**; uninstalled names are plain text with
     “Not in Cellar's core/cask catalog.” Do not open catalog detail for either.
   - Tradeoff: the section jump is less seamless than inline package detail, but it preserves PD6 and
     avoids inventing a second third-party package-detail capability inside this slice.

4. **When should force untap be offered?**
   - Recommended: plain untap is always the primary removal action; show force untap only when the
     current installed cross-reference is non-empty, as a separate destructive action whose
     confirmation lists every formula/cask.
   - Tradeoff: keeps the dangerous flag out of the normal path; users cannot preselect force for a
     zero-package tap, where it has no product value anyway.

5. **What if the affected package set changes after force confirmation is presented?**
   - Recommended: fail closed — invalidate the pending request and require a refreshed confirmation
     naming the new set before any process is spawned.
   - Tradeoff: one more confirmation under concurrent/queued changes, but executing with an outdated
     disclosure would make “names every affected installed package” untrue.

### Dependencies

- M3-1 is shipped and archived; its `BrewMutating`, `AnyBrewMutation`, `InvalidationScope`,
  `MutationGates`, terminal funnel, and null-package history behavior are prerequisites.
- Closed U2 probe evidence (#7128) is sufficient for proposal; no new brew probe is required.
- Current installed inventory must remain available as the force-disclosure source. Brew-absent and
  stale/failed inventory states must disable force rather than guess the blast radius.
- Strict TDD remains binding, with `swift test --package-path Packages/CellarCore` as the package loop.
- The five product decisions above must be settled interactively before proposal text treats them as
  requirements.
- Session review budget is 1,200 lines even though `openspec/config.yaml` still says 2,000. That
  discrepancy must be explicitly reconciled before tasks/apply; this exploration does not edit config.

### Likely Spec Capabilities

- **ADDED `tap-management`**: one structured installed-tap snapshot; tolerant schema; official API
  framing; tap package inventory; installed cross-reference; add/trust warning; plain versus force
  untap; full force disclosure and stale-confirmation behavior; scoped refresh; brew-absent guidance;
  PD6 guard.
- **MODIFIED `package-mutation`**: PM3 currently says uninstall and zap are the *only* confirmed
  mutations. It must be replaced as a whole-block superset so tap trust confirmation and destructive
  force untap can use the shared gate without weakening existing uninstall/zap rules. PM1, PM6, and
  PM7 already cover a new family and need no change unless proposal adds behavior not found here.
- **MODIFIED `installation-history`**: IH1/IH5 must add namespaced tap verbs and null-package/search
  semantics. No schema migration is expected.
- **UNCHANGED `package-detail`**: PD6 remains byte-identical; `tap-management` should carry a guard
  scenario proving third-party package inventory never enters catalog search/detail.
- **Likely unchanged**: `operation-activity`, `installed-inventory`, `brew-execution`,
  `service-management`, and `brew-detection`; their current generic clauses already cover the reuse.

### Edge Cases and Open Technical Questions

- Zero installed third-party taps: official API explanation still renders and add remains available.
- Very large taps: package inventory needs lazy rendering and likely detail-local filtering; eagerly
  materializing thousands of SwiftUI rows is avoidable.
- Formula and cask with the same token: every installed disclosure and row identity must carry kind.
- Fully qualified formula names versus possibly unqualified cask tokens: preserve raw payload values,
  normalize only an exact selected-tap prefix, and test both forms.
- Malformed individual tap records or unknown added keys: skip/count bad records without losing the
  whole snapshot; malformed envelope, non-zero exit, cancellation, and blank stdout remain distinct.
- `repo` and `repository` disagreeing: choose and document one precedence while preserving tolerant
  decode; do not silently merge unlike values.
- Private/custom remotes may expose sensitive URL user-info. Any displayed remote must remove
  credentials, and tap payloads must not be persisted merely for convenience.
- Exact duplicate-add, missing-tap untap, and “packages still installed” output markers are not part
  of U2. Design should verify them from Homebrew source/fixtures before adding a tap-specific
  `.noChange` override; default classification must not guess from prose.
- A force request can become stale while open or while waiting behind another mutation. The proposal
  must make the selected fail-closed policy observable and testable rather than treating the package
  list as decorative copy.

### Size Forecast

The old **1,700–2,300 source+test** forecast is no longer credible. M3-1's actual diff from its
baseline through merged remediation was **2,800 source lines + 4,617 test lines + 5,803 OpenSpec
lines = 13,220 authored changed lines**. M3-2 is narrower and reuses its spine, but force disclosure,
PD6 containment, structured package inventory, and a second family-aware confirmation surface are
real work.

| Bucket | Reforecast | Basis |
|---|---:|---|
| CellarCore + app source | 1,250–1,750 | tap source/decoder/store/projection/command, disclosure, app section/views/wiring |
| Swift Testing source | 1,750–2,450 | fixtures plus decoder/source/store/projection/argv/invalidation/confirmation/history/PD6 guards |
| **Authored source + tests** | **3,000–4,200** | 1.3–1.8× the old band top, still well below M3-1's 7,417 actual |
| Pre-apply SDD planning artifacts | 1,700–2,500 | this exploration, proposal, tap + modified deltas, design, and TDD tasks |
| Verify/archive/follow-up artifacts later | 700–1,200 | explicit lifecycle burden, separated from pre-apply planning |
| **Likely single-PR lifecycle total** | **5,400–7,900** | authored lines; generated receipts excluded because RDD is disabled |

Against the **1,200-line** session budget, source+tests alone are approximately **2.5–3.5× over**;
the likely single-PR lifecycle is approximately **4.5–6.6× over**. With `delivery_strategy:
single-pr`, an explicit accepted **`size:exception` is required before apply**. This exploration does
not grant it, and no later phase may infer acceptance from the selected strategy.

### Risks

- Force untap is a wide-blast mutation whose disclosure can become stale; execute only after a
  current, complete, kind-qualified installed-package confirmation.
- PD6 can be broken accidentally by “reusing” catalog detail for third-party package names; preserve
  a separate tap inventory and ordinary catalog misses.
- Homebrew's tap-info schema is richer and less uniform than the minimal projection; qualified names,
  prose timestamps, alias keys, private remotes, and unknown fields require tolerant fixture coverage.
- The current confirmation UI is package-specific even though the core request is generic; widening
  UI copy by verb-string switches would create another brittle exhaustive surface.
- The 1,200-line budget is materially below both the repository config and the reforecast; apply is
  blocked until the maintainer explicitly accepts a size exception for single-PR delivery.
- **There is no CI, so merged PRs are not automatically verified; all green-suite claims remain local
  snapshots unless CI is funded later.** This is a known project risk, not added M3-2 scope.

### Recommendation

Use a dedicated `TapInventory`/`TapStore` and `TapCommand` family on the shipped mutation spine.
Declare `.taps`, use structured `tap-info --installed --json` as the single list/detail snapshot,
cross-reference installed packages by exact `InstalledPackage.tap`, and extend confirmation with
typed disclosure metadata while leaving `BrewMutating` and PD6 unchanged.

### Ready for Proposal

**Yes, after an interactive proposal-question round resolves the five product decisions above.** The
orchestrator should ask them one at a time with the recommendations and tradeoffs shown here. The next
step is not implementation, and proposal must not silently grant the required `size:exception`.
