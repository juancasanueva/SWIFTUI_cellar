# Exploration: `m9-per-package-trust` — surfacing Homebrew 6 per-package trust grants

> ARTIFACT BODY. The executor had no Write tool; the orchestrator persists this verbatim to
> `openspec/changes/m9-per-package-trust/explore.md` (house precedent: 11 of 12 archived changes use
> `explore.md`, not the shared convention's `exploration.md`).

Anchors PRD **§3.7 (:108) "Taps manager"**, the same clause `m7-tap-trust` rewrote. Carries archive
follow-up §9 item 1 / §11 item 1 of `2026-08-23-m7-tap-trust`.

## Executive answer

Ship a **read-only** per-package trust surface. `brew trust --json v1` is a genuinely new read (a second
payload source, store and invalidation domain — `tap-info` does **not** carry it), but everything a user
needs to stop misreading the `Untrusted` badge is *display*. Adding grant/revoke controls means putting a
`/`-qualified package token into argv, which is the exact mechanism `package-mutation` **PM10** prohibits
as an absence over the whole mutation surface — and that prohibition exists because naming a qualified
token **is** the grant on Homebrew 6. Do not open that door in the same slice that first reads the data.

## Current State

### Where tap trust lives today (all shipped by `m7-tap-trust`)

| Layer | File | What it does |
|---|---|---|
| Wire | `Packages/CellarCore/Sources/BrewClient/TapWire.swift:12-16` | `TapTrustState { trusted, untrusted, unreported }` |
| Wire | `TapWire.swift:72,94-97,132` | Decodes the per-tap `trusted: Bool?`; `decodeIfPresent` maps absent **and** explicit `null` to `.unreported`, never `.untrusted` |
| Model | `TapWire.swift:18-50` | `TapRecord.trust: TapTrustState` |
| Source | `TapPayloadSource.swift:41` | The **only** tap read: `BrewCommand.read(["tap-info", "--installed", "--json"])` — compile-time constant argv |
| Store | `TapStore.swift:13-119` | `@MainActor @Observable`, in-flight coalescing, last-good retention, monotonic `installedSequence` adoption |
| Projection | `TapProjection.swift:100-132` | `TapTrustPresentation { badge: String?, canGrant: Bool, canRevoke: Bool }` — **one** value both surfaces read |
| Projection | `TapProjection.swift:166-174` | `packageSummary(for:)` → `"5 formulae · 1 cask"` (the natural host for a trust count) |
| Projection | `TapProjection.swift:204-245` | `bareToken(_:publishedBy:)`, `publishes(_:in:)`, three-valued `installState` |
| Commands | `TapCommand.swift:81-120` | `.trustTap`/`.untrustTap` → argv exactly `["trust", name]` / `["untrust", name]`; `packageID` is **always nil** (`:135`) |
| Disclosure | `TapCommand.swift:48-79` | `.tapAdd(TapName)`, `.tapTrustGrant(TapName)` |
| Recovery | `UntrustedTapRecovery.swift:20-35` | Derives the trustable tap from Cellar's own snapshot; exactly-one-candidate or nothing |
| View — row | `cellar/Taps/TapsListView.swift:48-54` | badge + `packageSummary` under the tap name |
| View — detail | `cellar/Taps/TapDetailView.swift:52-114` | badge in header, `Trust`/`Untrust`/`Untap`/`Force Untap` chips |
| View — detail | `TapDetailView.swift:149-180` | Per-package rows with `statusExplanation` and **Show in Installed** |
| View — badge | `TapDetailView.swift:303-329` | `TapTrustBadge` — takes its text, never composes it; deliberately not uppercased |

### How `brew trust --json v1` is consumed today

**It is not.** Zero call sites. Cellar has never spawned `brew trust` in a read position. Everything the
app knows about trust comes from one boolean on `tap-info`. `brew trust --json v1` was used only as an
out-of-band *probe* during `m7-tap-trust` (obs `#7721`, `#7722`, `#7724`) and as manual evidence in
Phase 9 (TM13.5). So the per-package data is "one read away" in the sense that the command exists and
its shape is measured — not in the sense that a payload already reaches the app.

### The gap, precisely

On the maintainer's Mac: 8 third-party taps render **Untrusted**, while `brew trust --json v1` lists
**9 formulae + 4 casks** granted individually. Those packages upgrade fine. The badge is *accurate* —
it is about the tap — and TM12 forbids any string in that surface from claiming a package is untrusted.
The user is left to reconcile "Untrusted" with software that plainly works.

### Measured Homebrew 6 facts this change inherits (do not re-derive)

1. `brew trust --json v1` keys: **`taps`, `formulae`, `casks`, `commands`**. Entries are fully qualified
   (`#7721`, `#7722`).
2. Per-package grants are **independent** of tap grants; `brew untrust --cask <qualified>` removes only
   the package entry (`#7724` P2).
3. A per-package grant **restores** the withheld `tap` field in `brew info --installed --json=v2`, and a
   bare-token `brew upgrade` then loads the package (`#7724` P3).
4. Naming a `/`-qualified package on the command line **is** the grant (`trust.rb#explicitly_allowed?`)
   (`#7721`).
5. `formulae` entries are **not always `owner/repo/name`** — a real entry observed was
   `https://github.com/cloudmanic/spice-edit/spice-edit` (`#7721`).
6. `trust.json` lives at `~/.homebrew/trust.json` or `$XDG_CONFIG_HOME/homebrew/trust.json`. Cellar must
   **not** read it directly (apply rule: always shell out to `brew`).
7. Trust/untrust are idempotent, exit 0 (`#7722`, `#7724` P5).

### The three shipped constraints any per-package surface must not break

**C1 — No pre-launch gate (PM10, `openspec/specs/package-mutation/spec.md:654-656`).** A per-package
grant makes a tap-state gate block what brew allows. Enforced *structurally*: `MutationCommandTests.swift:471-479`
scans `MutationCommand.swift` for the literal tokens `TapTrustState`, `.untrusted`, `.trusted`, `.trust`,
`TapRecord`, `TapInventory`, `TapProjection`, `trustableTap`, `UntrustedTapRecovery` and fails if any
appears. New type names must be added to that ban list, not merely kept out by accident.

**C2 — The argv prohibition (PM10, `spec.md:647-652`).** `MutationCommandTests · noPackagePositionEverCarriesAQualifiedToken`
(`:500-613`) enumerates every `MutationCommand`, `TapCommand`, `ServiceCommand`, `CleanupCommand` and
`BrewfilePlan` argv and asserts **no element carries two or more `/`**. `brew trust --cask owner/tap/pkg`
carries two. A grant/revoke control cannot be added without editing this test and MODIFYING PM10.
`MutationCommand.swift` was a binding **0-line diff** across all of `m7-tap-trust`; that is what makes
DD-8 checkable.

**C3 — TM12's single-source clause (`openspec/specs/tap-management/spec.md:544-546`).** *"It MUST NOT
require a second probe, a second store, a second source of truth, or a new invalidation domain."* Read
strictly, "it" is *a tap's trust state*, which still comes from `tap-info`. But the sentence is absolute
enough that a reviewer will read it as governing the whole trust surface. **TM12 must be MODIFIED** to
scope the clause explicitly, or this change contradicts a promoted spec on its first line.

### The correctness rule that governs all copy

**Absence from the per-package lists is not "untrusted."** A package under a *trusted* tap is loadable
with no per-package entry at all. The only honest per-package statement is **positive**: "Trusted
individually." There is no honest negative rendering, and TM12 already forbids one.

## Affected Areas

- `Packages/CellarCore/Sources/BrewClient/TapWire.swift` — sibling three-valued state for the new read
- `Packages/CellarCore/Sources/BrewClient/TapProjection.swift` — the count line and the per-package marker
- `Packages/CellarCore/Sources/BrewClient/TapPayloadSource.swift` — pattern to clone for the new source
- `Packages/CellarCore/Sources/BrewClient/TapStore.swift` — pattern to clone for the new store
- **NEW** `TrustGrantPayloadSource.swift`, `TrustGrantWire.swift`, `TrustGrantStore.swift`
- `Packages/CellarCore/Sources/BrewClient/TapCommand.swift:150-156` — `invalidates` must name the new domain
- `InvalidationScope` (mutation spine) — a new member touches every command family's declaration + tests
- `Packages/CellarCore/Sources/BrewClient/TapRefreshCoordinator.swift` — refresh sequencing
- `cellar/cellarApp.swift` — DI wiring for the new store
- `cellar/Taps/TapsListView.swift:52` — row subtitle
- `cellar/Taps/TapDetailView.swift:57-65, 149-180, 195-237` — header meta, package rows, footer
- `cellar/Browse/PackageDetailView.swift:557` — existing `fact("Tap", …)` row, the natural package-level anchor
- `Packages/CellarCore/Sources/BrewClient/BrewfileDiff.swift:118-128` — **R15**: `isPresent` keys on
  `formula.id` (the file's *qualified* identity) rather than `entry.installTarget`, so a qualified line
  always projects "missing". A ~1-line fix plus tests, independent of everything above.
- `Packages/CellarCore/Tests/BrewClientTests/MutationCommandTests.swift:471-479, 500-613` — the two guards
- `README.md:44` — recommends `brew install --cask juancasanueva/cellar/home-cellar`, which **is** a
  per-package grant. Doc-only sweep, zero code.

## Approaches

### 1. Tap-row count only — read-only
Add the read, render `"5 formulae · 1 cask · 2 trusted individually"` on the tap row and detail header.
Nothing per-package.
- Pros: smallest surface that removes the misreading; no new copy about individual packages; no view
  restructuring; TM12 MODIFIED is a one-clause edit.
- Cons: the detail package list still says nothing, so a user who opens the tap to find *which* two are
  trusted cannot; orphan grants stay invisible.
- Effort: **Low**. ~2 work units. Est. **1,800–2,400** lines (code+tests ~900–1,200; artifacts ~900–1,200).

### 2. Full read-only trust surface — **recommended**
Option 1 plus: a "Trusted individually" marker on the matching rows of the tap detail package list; the
same marker on package detail beside the existing `Tap` fact; and an honest accounting of grants Cellar
cannot attribute to an installed tap (orphans, URL-shaped formulae, the `commands` namespace).
- Pros: answers "which packages", not just "how many"; surfaces **orphan grants** — per-package grants
  survive an untap, so exactly the dormant, invisible grant TM7's revocation exists to prevent still
  exists at package granularity, and a re-tap silently re-arms it; keeps the C1/C2 guards byte-untouched.
- Cons: needs a second surface decision (where orphans live); more copy to review; `commands` is a
  namespace Cellar has no concept for.
- Effort: **Medium**. ~4 work units. Est. **3,400–4,400** lines. Fits the 5,000 budget, not comfortably.

### 3. Option 2 + per-package grant/revoke controls
Adds a `TrustCommand` family with `--formula`/`--cask` and a qualified token.
- Pros: complete management story; a user could revoke an orphan grant from inside Cellar.
- Cons: **requires MODIFYING PM10's argv prohibition** and rewriting the binding absence test — the one
  invariant `m7-tap-trust` kept as a 0-line diff. Needs a new confirmation disclosure case (R13-class
  blast: three source-scanning guards move). And it is **unmeasured** whether `brew untrust --cask <qualified>`
  itself registers a grant through `explicitly_allowed?` before removing it — if it does, Cellar can
  never emit it. Do not design this before that probe.
- Effort: **High**. ~7 work units. Est. **5,500–7,000** lines → `size:exception` or chained PRs.

### 4. Option 3 + R15 Brewfile diff fix + a Brewfile trust column
- Pros: closes three carried follow-ups at once.
- Cons: two unrelated capabilities in one review; the R15 fix is ~1 line and does not need this change.
- Effort: **Very High**. Est. **6,500–8,000** lines. Reject.

| Approach | Pros | Cons | Effort | Est. lines |
|---|---|---|---|---|
| 1. Count only | Smallest honest fix | No per-package answer | Low | 1,800–2,400 |
| 2. Full read-only | Answers "which"; surfaces orphan grants | More copy; orphan placement question | **Medium** | **3,400–4,400** |
| 3. + grant/revoke | Complete management | Breaks PM10's binding invariant; needs a probe first | High | 5,500–7,000 |
| 4. + R15 + column | Three follow-ups closed | Two capabilities, one review | Very High | 6,500–8,000 |

## Recommendation

**Option 2, read-only, with R15 split out as its own trivial slice.**

Design rules the proposal should carry forward:

- **D-a** The per-package read is its own payload source, store and invalidation domain. TM12 is MODIFIED
  to scope its single-source clause to the *tap's own* trust state, which continues to come from `tap-info`.
- **D-b** The new state is **three-valued**, exactly like `TapTrustState`. A Homebrew that cannot answer
  `brew trust --json v1` is `unreported`, and `unreported` must be distinguishable from "zero grants" in
  both the model and the copy. This is the whole Homebrew < 6 mitigation, reused.
- **D-c** All per-package copy is **positive-only**. There is no rendering for "this package has no
  individual grant", because that is not a fact about trust.
- **D-d** The tap badge does not change. `Untrusted` stays exactly as TM12 pins it; the count is a
  separate, additive line that never softens it.
- **D-e** Attribution from a qualified entry to a `TapRecord` reuses `TapProjection.bareToken(_:publishedBy:)`
  and `publishes(_:in:)` — never a naive `split("/")`, which breaks on the URL-shaped formula entries.
  Anything that does not attribute is surfaced as an unattributed grant, never dropped silently.
- **D-f** No control anywhere in this change submits a trust command for a package. Asserted as an
  absence, and the C2 test's `≤ 1 slash per argv element` invariant stays **byte-identical**.
- **D-g** The C1 source-scanning ban list is *extended* with the new type names, so a later change cannot
  reintroduce a pre-launch gate through the new store.

## Risks

- **R1** TM12's "no second probe / second store / new invalidation domain" clause reads as absolute. Without
  a MODIFIED delta this change contradicts a promoted spec. **Mitigation: MODIFY TM12 first.**
- **R2** A new `InvalidationScope` member touches every command family's declaration and its tests — a
  wide, shallow diff that inflates the line count without adding behaviour.
- **R3** Copy risk: "2 trusted individually" beside an `Untrusted` badge can read as reassurance. The
  wording must state a fact about grants, not a verdict about safety (TM11 forbids a verdict outright).
- **R4** Degradation: on a Homebrew without `brew trust`, the command fails. The store must land in
  `unreported`, not "0 grants" — the same defect a `Bool` would have caused in `m7`.
- **R5** A second subprocess per refresh. `trust.json` is a local file so the cost should be small, but it
  is a real spawn and must inherit `TapStore`'s in-flight coalescing and last-good discipline.
- **R6** Unattributable entries (URL formulae, `commands`, grants for taps that are not installed) are a
  guaranteed non-empty set on the maintainer's own Mac. A design that assumes `owner/repo/name` will
  silently drop them.
- **R7** **Orphan grants are a latent security finding, not just a display gap.** TM7 revokes the *tap*
  grant behind a successful untap precisely so a re-tap cannot silently re-arm it. Per-package grants are
  not revoked by that path and survive the untap. Read-only surfacing makes them visible; it does not
  remove them, and the proposal must say so plainly rather than implying the surface closes the hole.
- **R8** Size. `m7-tap-trust` overshot its artifact forecast **5–7×** (600–900 forecast → 4,385 actual).
  Forecast the artifact bucket separately and do **not** apply the code correction to it (m7 learning E).

## Open product questions for the maintainer

1. **Probe first, before any mutation design**: does `brew untrust --formula|--cask <qualified>` itself
   register a grant via `explicitly_allowed?` before removing it? This decides whether Option 3 is ever
   available. (Read-only Option 2 does not depend on the answer.)
2. Where do **orphan / unattributed grants** live — a section in Taps, a Settings row, or nowhere in v1?
3. Is the `commands` namespace decoded-and-counted as "other", or ignored entirely?
4. Does the count line live on the tap **row**, the **detail header**, or both? (TM12's one-projection
   rule says whichever it is, it comes from a single value.)
5. Does package detail get a "Trusted individually" marker, or is v1 scoped to the Taps section only?
6. Fold **R15** in, or ship it as its own ~1-line slice? (Recommendation: separate.)
7. Sweep `README.md:44` in this change or separately? (Doc-only; either works.)

## Ready for Proposal

**Yes** — for Option 2, read-only, with question 1 deferred (it gates Option 3 only) and questions 2–7
answerable as proposal defaults. Tell the maintainer: the recommended slice reads `brew trust --json v1`
into its own store and *shows* per-package grants; it deliberately adds no way to grant or revoke one,
because doing so requires putting a qualified token in argv — the exact thing PM10 forbids as an absence
over the whole mutation surface.
