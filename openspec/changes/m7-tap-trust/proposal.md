# Proposal: Tap Trust as a First-Class, Honest Capability (`m7-tap-trust`)

Anchors PRD.md **M3 "Services, Cleanup & Taps"** (:207-208, "taps manager"; §3.7 :108, "Warning copy
when adding third-party taps (untrusted code)") — the taps manager shipped at M3 with copy that
Homebrew 6 has since made false. **M6 "Ship"** (:217, :9) is why it is urgent now rather than later:
Cellar's own distribution channel is a third-party tap, so the first thing a new user does is add a
tap they must separately trust, and Cellar tells them the wrong story about what happened.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files + Engram, canonical project `swiftui_cellar`), `delivery_strategy=single-pr`,
`review_budget_lines=5000`, `strict_tdd=true`, RDD disabled.

Inputs: `openspec/changes/m7-tap-trust/explore.md` (Engram `sdd/m7-tap-trust/explore`, obs `#7723`),
orchestrator probes obs `#7721`, `#7722`, `#7724`, and the maintainer's decisions D1–D2 (below).
This document exceeds the generic 450-word phase budget deliberately: `openspec/config.yaml`
`rules.proposal` and the house precedent (`archive/2026-08-23-m6-cask-tap/proposal.md`) govern shape.

## Intent

Cellar tells the user a lie at the exact moment the user is deciding whether to run someone else's
code. The Add Tap confirmation says *"Adding acme/tools trusts third-party formulae and casks that
can distribute code."* On Homebrew 6 the `brew tap` it runs grants nothing (`cmd/tap.rb` has no trust
hook), so the sentence over-claims a capability grant that never happened — and the tap it just added
is inert. Nothing loads from it, its installed packages read **"Not installed."**, and an upgrade of
one of them is refused by brew with no recovery offered anywhere in the app.

**Product outcome.** A user can see whether each tap is trusted, grant that trust as its own explicit
answer, take it back, and understand a refusal instead of reading an exit status. Adding a tap says
truthfully what it did. Removing a tap takes the grant with it, so nothing is silently re-armed when
the tap comes back — including when a Brewfile import brings it back.

**The security shape is the point.** Trust is arbitrary third-party code running as the user, with the
user's permissions. This change makes that capability *representable, visible and revocable* without
making it *implicit anywhere*: not on add, not on import, not on refusal recovery, not on retry.

## Resolved Decisions (binding — taken by the maintainer 2026-08-23, MUST NOT be reopened)

| # | Decision | Rejected |
|---|---|---|
| **D1** | **Keep Homebrew's tap/trust split.** Add Tap stays `["tap", name]` with truthful copy. Trust and Untrust are separate, explicitly confirmed commands (`["trust", name]`, `["untrust", name]`). Untap revokes first (`untrust` **then** `untap`) (amended by D4, 2026-08-23: removal first). An untrusted-tap refusal is classified into a typed `MutationOutcome` offering a path to Trust. A **fully-qualified-argv bypass is PROHIBITED and MUST be asserted by a test** | explore Q1 **A** (add + trust as one confirmed batch — makes "fetch without granting execution authority" unrepresentable, and couples a git clone to arbitrary-code authority); **C** (two-outcome confirmation — needs a partial-confirm path that contradicts PM3's "declining submits none, never a partial subset"); explore Q4 **(a)** pre-launch gate (probe `#7724`: a per-package grant makes a tap-state gate block what brew would allow); **(b)** qualified argv (`trust.rb#explicitly_allowed?` treats naming the qualified package **as the grant** — it *is* the bypass, dressed as a fix) |
| **D2** | Rename `ConfirmationDisclosure.tapTrust` → **`.tapAdd(TapName)`**; add **`.tapTrustGrant(TapName)`** | Keeping a case named `tapTrust` on a command that grants no trust. The cross-spec churn *is* the change: the old name is the lie |

**Implied and binding**: `TapTrustState { trusted, untrusted, unreported }` decoded from tap-info's
`trusted: Bool?` (`.unreported` = Homebrew < 6, same rule as `InstalledPackage.declaresAutoUpdates`);
badge in `TapsListView` / `TapDetailView`; `InstalledPackage.tap` becomes `String?`; `TapProjection`
gains a third typed state for "installed but tap withheld"; Brewfile `trusted:` stays informational;
trust/untrust invalidate `.taps` **and** `.installedInventory`.

## Measured facts this change consumes (probes, not assumptions)

| Fact | Value | Source |
|---|---|---|
| `brew tap` never trusts | `brew tap --help` has no trust flag; `cmd/tap.rb` has no trust hook | obs `#7721`, `#7722` |
| Trust state is already in Cellar's payload | `brew tap-info --json --installed` carries a per-tap boolean **`trusted`** | obs `#7722` |
| Grant / revoke commands | `brew trust <tap>`, `brew untrust <tap>`; persisted in `~/.homebrew/trust.json` | obs `#7721` |
| Both are idempotent | `trust` on an already-trusted tap → "Already trusted tap: …", exit 0; `untrust` on a never-trusted tap → exit 0 | obs `#7722`, `#7724` |
| Per-package grants are independent of tap grants | `brew trust --json v1` keys `taps` / `formulae` / `casks` / `commands`; casks listed grants while `taps` was empty | obs `#7722`, `#7724` |
| A per-package grant **restores** `tap` and unblocks bare-token argv | tap untrusted + `brew trust --cask <qualified>` → `brew info --installed --json=v2` reports the tap again; bare-token upgrade loads | obs `#7724` |
| Withheld tap collapses today | `brew info --installed --json=v2` reports `tap: null`; `InstalledDecoder.swift:76`/`:108` map it to `""` | obs `#7721`, source |
| Exact refusal stderr | ``Error: Refusing to load cask <qualified> from untrusted tap <tap>. Run `brew trust --cask <qualified>` or `brew trust <tap>` to trust it.`` | obs `#7721` |

**Unmeasured, and treated as such**: the refusal wording for a **formula** (only the cask form was
observed) and whether official taps report `trusted`. Both degrade safely — see Risks R6 and R8.

## Scope

### In scope

1. **Read** — `TapWire` decodes `trusted` with `decodeIfPresent(Bool.self)`; `TapRecord` publishes
   `trust: TapTrustState`. No new read command, no new store, no new invalidation domain.
2. **Show** — a trust badge projected in `TapProjection` beside `packageSummary`, consumed by both the
   list row and the detail header. `.unreported` renders no badge and no control.
3. **Grant / revoke** — `TapCommand` gains `.trustTap` and `.untrustTap`; Trust is confirmed with
   `.tapTrustGrant`, Untrust is not (it only reduces authority).
4. **Truthful add copy** — `.tapAdd` replaces `.tapTrust`; `TapDetailView.swift:183`'s "Add ones you
   trust." footer becomes trust-state aware.
5. **Revoke on removal** — Untap and Force Untap each submit `[untrustTap, removeTap|forceRemoveTap]`
   in that order. Both argvs stay character-for-character what TM7/TM8 already pin.
6. **Classify the refusal** — `MutationOutcome.refusedUntrustedTap` plus `Signature.isUntrustedTap`,
   stderr-only and tail-bounded, with **nothing parsed out of the payload**.
7. **Make `tap: null` representable** — `InstalledPackage.tap: String?`; `TapProjection` gains the
   withheld-tap state so an installed package stops being described as not installed.
8. **PRD.md §3.7 :108** — the taps-manager line describes tap-versus-trust honestly.
9. Spec deltas across four capabilities (below).

### Out of scope (non-goals — recorded, not omitted)

- **No per-package trust UI.** v1 is tap-level only. But the projection MUST NOT *block* what a
  per-package grant already allows (obs `#7724`), so no pre-launch gate is built — this is a
  correctness constraint, not just a deferral.
- **No `brew trust --json v1` read and no `TrustInventory` type.** It buys only per-package grants and
  adds a second source of truth for a question `tap-info` already answers.
- **No Brewfile-driven trust.** `trusted:` stays informational; the claim is made by the *file's
  author*, exactly the party a trust decision must not be delegated to (`brewfile-management` :508-510).
  `BrewfilePlan.swift` changes only to install the **bare token** a `/`-qualified entry names (**D3**),
  which is the opposite of a Brewfile-driven grant: it keeps the file's token out of argv, where
  Homebrew 6 would read it as one.
- **No Homebrew < 6 polyfill.** Absent `trusted` degrades to `.unreported`: no badge, no buttons, and
  `brew trust` is never spawned.
- **No fully-qualified argv anywhere.** Prohibited by D1 and asserted by a test.
- **No new confirmation on plain untap.** TM7's "ordinary removal MUST NOT require confirmation" holds.
- Deferred follow-ups: per-package trust surface; a trust column in Brewfile diff; trust state for
  official taps (they are non-mutable under TM4, so no control could appear anyway).

## Capabilities

> Contract with `sdd-spec`. Requirement names below are the **exact** headings in `openspec/specs/`.

### New Capabilities

**None.** Trust is a property of a tap and a property of a mutation's outcome; `tap-management` and
`package-mutation` already own both.

### Modified Capabilities

- **`tap-management`** — six MODIFIED, two ADDED. *(Reconciled by the orchestrator after `sdd-spec`: the one ADDED requirement budgeted here was split into TM12 — trust is read from the snapshot and shown, three-valued — and TM13 — trust is granted or revoked only by an explicit answer. No rule was added or dropped; the split gives the prohibition its own testable subject.)*
- **`package-mutation`** — two MODIFIED, one ADDED.
- **`installed-inventory`** — one MODIFIED.
- **`brewfile-management`** — two MODIFIED (rename only; no rule changes).

| Spec | Requirement (exact heading) | Delta |
|---|---|---|
| `tap-management` TM5 | Tap package inventory preserves identity without entering the catalog | **MODIFIED** — a third typed installed state: tap withheld **and** selected tap untrusted **and** it publishes this exact `(kind, name)` → "Installed. Homebrew withholds its tap while this tap is untrusted." **Show in Installed** is still offered (the `PackageID` handoff is exact). Today's wording *mandates* the wrong answer |
| `tap-management` TM6 | Add accepts only a canonical tap target and always confirms typed argv | **MODIFIED** — add grants no trust; the disclosure is `.tapAdd` and says so. Argv unchanged |
| `tap-management` TM7 | Plain untap is primary and force availability is fail-closed | **MODIFIED** — the untap **action** submits `untrust` then `untap`, each with its own exact argv; `untap user/repo` still never grows a hidden flag; still no confirmation |
| `tap-management` TM8 | Force untap discloses a current complete affected set | **MODIFIED** — same revoke-first prepend; the disclosure presented is still the force-untap one |
| `tap-management` TM9 | Tap mutations use the shared mutation spine and scoped terminal invalidation | **MODIFIED — not in explore's delta table; found by this proposal.** TM9's text enumerates exactly three commands and states "Tap add and plain untap MUST NOT invalidate installed inventory". Trust and untrust MUST invalidate **taps and installed inventory** (obs `#7724`: the `tap` field itself changes with the grant), so the enumeration grows to five and the scenario's "only force also refreshes installed inventory" is now false. Catalog is still never invalidated |
| `tap-management` TM11 | Tap management does not expand into adjacent product capabilities | **MODIFIED** — the enumerated action set grows from six to eight: refresh, filter, Installed handoff, canonical add, plain untap, eligible force untap, **trust**, **untrust** |
| `tap-management` **TM12** | *Tap trust is read from the snapshot, shown, and granted only by an explicit answer* | **ADDED** — three-valued state; `.unreported` hides the whole surface and spawns no `brew trust`; **no path grants trust implicitly** (not add, not import, not refusal recovery, not retry); revocation precedes removal |
| `package-mutation` PM1 | Every mutation is a typed command carrying an explicit kind flag | **MODIFIED — not in explore's delta table; found by this proposal.** (a) prose renames `tap-trust disclosure` → `tap-add disclosure` (:101, :109); (b) **the batch-disclosure rule needs a resolution** — see Approach §5 and Open Question 1 |
| `package-mutation` PM3 | Uninstall and zap are the only mutations behind a confirmation gate | **MODIFIED** — the shared gate's inventory becomes `.tapAdd`, `.tapTrustGrant` and `.forceUntap`; every trust grant MUST be confirmed; untrust MUST NOT be |
| `package-mutation` **PM10** | *A refusal to load from an untrusted tap is a typed outcome, and no argv ever becomes the grant* | **ADDED — not in explore's delta table; found by this proposal.** Sibling to PM4 (sudo) and PM5 (lock): stderr-only, tail-bounded, nothing extracted. **Plus the prohibition**: no mutation argv MAY carry a `/`-qualified package token, because naming it *is* the grant. `MutationName.isSafe` permits `/` (`MutationCommand.swift:130-133`), so the prohibition must be a rule with a test, not an accident of validation |
| `installed-inventory` II2 | Asymmetric formula and cask installation shapes both decode | **MODIFIED** — a **withheld** tap is not an **empty** tap. `tap` becomes optional and null is preserved as absence, on exactly the terms this requirement already states for tri-state `auto_updates` |
| `brewfile-management` BF5 | `trusted:` is parsed, surfaced, and confers nothing | **MODIFIED (rename only)** — :231, :239 name `ConfirmationDisclosure.tapTrust`. **The rule is unchanged**, and Homebrew 6 makes its reasoning stronger, not weaker |
| `brewfile-management` BF7 | A selection becomes existing typed mutations, and nothing else is submitted | **MODIFIED (rename only) — not in explore's delta table.** :322, :330, :353 name `tapTrust`. The "batch disclosure comes from the first command" rule at :321-323 is **unaffected** by Approach §5, because a Brewfile batch is always led by a tap add that declares its own disclosure |

> **`sdd-spec` obligations.** (1) TM2 ("Tap decoding is tolerant, kind-aware…") needs **no** delta — an
> unknown key was already tolerated; TM12 owns the new field. (2) TM10's "no process spawns when brew
> is absent" must read on five commands, not three — verify whether its wording is already
> command-agnostic before writing a delta. (3) Each spec's `## Verification classes` counts live
> outside requirement blocks; ADDED deltas cannot carry them, so state the hand-update obligation under
> *Notes for archive* (the `m6-sparkle-updates` / `m6-cask-tap` precedent).

## Approach

**1 — Read, with no new I/O.** `TapWire` adds `case trusted` and `decodeIfPresent(Bool.self)`;
`TapRecord` publishes `trust: TapTrustState`. `BrewTapPayloadSource` (`tap-info --installed --json`)
is untouched. Three-valued rather than `Bool` because "not reported" is not "reported false" — this
single choice *is* the whole version-drift mitigation.

**2 — Show, in one projection.** Badge copy lives in `TapProjection` beside `packageSummary`, so the
list row, the detail header and the tests read one source. `.unreported` yields no badge and no
control. Official taps never reach the surface anyway: `TapProjection.officialNames` filters them and
TM4 keeps them non-mutable.

**3 — Two commands, two explicit answers.** `TapCommand` gains `.trustTap(TapName)` → `["trust", name]`
and `.untrustTap(TapName)` → `["untrust", name]`. Literal verbs plus `tap.rawValue`, so
`MutationCommandTests.swift:289`'s "no `\(`, `joined(`, `split(` in an argv body" scan stays green with
no exemption. `requiresConfirmation`: **true** for trust, **false** for untrust. `packageID` is `nil`
for both. `invalidates` is `[.taps, .installedInventory]` for both.

**4 — Untap revokes first.** `Untap` and `Force Untap` submit two ordered commands through the shipped
`request([commands])` path. Order is load-bearing (untrust must run while the tap still resolves) and
unconditional, because `brew untrust` on a never-trusted tap exits 0 (obs `#7722`). This is the whole
stale-grant fix: without it, a Brewfile import can silently re-arm a grant the user revoked by
untapping, with no new consent and no way for Cellar to see it.

**5 — The batch-disclosure conflict this creates, and its recommended resolution.** PM1 requires that a
batch's disclosure be **the first submitted command's** disclosure, and that erasure "MUST NOT change,
downgrade or discard a disclosure". Prepending `.untrustTap` to Force Untap makes the *first* command
one that declares no disclosure of its own — which under today's rule falls back to `.packageRemoval`
("This removes installed software."), silently downgrading the force-untap package disclosure and
stating something false about an untrust.

> **Recommended resolution (Open Question 1).** MODIFY PM1 so a batch's disclosure is the first
> submitted command's **own declared** disclosure, skipping commands that rely on the protocol
> default. This *strengthens* the anti-downgrade rule rather than weakening it, needs no new
> disclosure case, and leaves `brewfile-management` BF7's ordering rule intact.
>
> Alternatives recorded: (a) reorder the batch — **rejected**, revocation must precede removal;
> (b) submit the untrust outside the confirmed batch — **rejected**, it would run a command the sheet
> never listed; (c) give `.untrustTap` its own disclosure — **rejected**, the force batch would then
> lead with revoke copy on a removal confirmation.

**6 — Let brew refuse, then explain it.** `MutationOutcome.refusedUntrustedTap` with
`Signature.isUntrustedTap` matching ONE structural phrase about the tap — `"untrusted tap"`, design-owned,
case-sensitive — on the stderr tail only (corrected at design DD-6: a second, looser phrase would offer a
Trust button for refusals trust cannot fix). brew is the **only** authority that can decide,
because it alone sees both grant kinds. The message is deliberately tap-agnostic and tap-scoped —
never "this package is untrusted", which a per-package grant would make false:

> "Homebrew refused to load this package because its tap is not trusted. Trust the tap in Taps, then
> try again."

…shown beside the verbatim log, which already carries brew's own exact `brew trust …` line.

**7 — Stop collapsing `tap: null`.** `InstalledPackage.tap: String?`; `InstalledDecoder.swift:76`/`:108`
drop the `?? ""`. *Corrected at design (DD-11): this does **not** produce a compile error at every
reader — Swift promotes the non-optional operand of `==`, so `$0.tap == tap` (`TapProjection.swift:146`),
`$0.tap == tap.rawValue` (`ContentView.swift:546`) and `package.tap == "homebrew/core"`
(`cellar/Home/HomebrewUpdateNeed.swift:85-86`) all keep compiling and stay semantically correct. Only the
declaration and the two decoder sites change; the three readers are pinned by an explicit test instead.*
`TapProjection` gains the withheld state. Note `CatalogPackage.tap` is a **different, unchanged** property.

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `Packages/CellarCore/Sources/BrewClient/TapWire.swift` | Modified | `trusted` decode; `TapTrustState`; `TapRecord.trust` |
| `.../BrewClient/TapCommand.swift` | Modified | `.trustTap` / `.untrustTap`; `.tapAdd` / `.tapTrustGrant` disclosures; new argv, verb, confirmation and invalidation arms |
| `.../BrewClient/TapProjection.swift` | Modified | trust badge projection; `exactInstalled` (:141-147) gains the withheld state |
| `.../BrewClient/InstalledDecoder.swift` :76, :108 | Modified | `?? ""` removed |
| `.../BrewClient/InstalledModels.swift` :80 | Modified | `tap: String?` |
| `InstalledPackage.tap` readers | **Unchanged — verified** | `TapProjection.swift:146`, `cellar/ContentView.swift:546`, `cellar/Home/HomebrewUpdateNeed.swift:85-86`, plus cask/detail presentation — **≈6-9 sites, none of them a compile error**: Swift promotes the non-optional operand of `==`, so each keeps compiling and stays semantically correct (`nil` equals nothing). Pinned by `InstalledDeriveTests · everyTapReaderTreatsAbsenceAsNoMatch` instead of by the compiler |
| `.../BrewClient/MutationOutcome.swift` | Modified | `.refusedUntrustedTap` + `Signature.isUntrustedTap` + `message` / `summaryLabel` / `isFailure` arms |
| `.../BrewClient/BrewMutating.swift` | Modified | batch-disclosure resolution (Approach §5) |
| `cellar/Taps/TapsListView.swift`, `TapDetailView.swift` (:183) | Modified | badge, Trust/Untrust controls, trust-aware footer |
| `cellar/Activity/MutationConfirmation.swift` (~:153, :168) | Modified | title "Trust this tap?", confirm label "Trust" |
| `PRD.md` §3.7 :108 | Modified | honest tap-versus-trust line |
| `Packages/CellarCore/Tests/BrewClientTests/*` (6 files) + `cellarTests` + `cellarUITests` | Modified/New | see Strict TDD plan |
| `openspec/changes/m7-tap-trust/specs/{tap-management,package-mutation,installed-inventory,brewfile-management}/spec.md` | **New** | four deltas |
| `.../BrewClient/BrewfilePlan.swift` | Modified | **D3** — its install arm builds from the entry's bare token; **no longer a 0-line binding** |
| `.../BrewClient/MutationCommand.swift`, `TapPayloadSource.swift`, `cellar.xcodeproj/project.pbxproj` | **Untouched — binding** | **D3** adds no `/` gate to `MutationName.isSafe` or `PackageTarget.init?`; no new read command; no project-file edit (`PBXFileSystemSynchronizedRootGroup`) |

## Strict TDD plan

`config.yaml` sets `strict_tdd: true`; `rules.tasks` requires RED before GREEN for every behavioural
task. Inner loop `swift test --package-path Packages/CellarCore`; app target
`xcodebuild test … -only-testing:cellarTests`.

| # | Unit | File | RED because |
|---|---|---|---|
| 1 | `trusted` true / false / absent → `.trusted` / `.untrusted` / `.unreported`; fixture mirrors the real `tap-info` shape (PR #67 lesson) | `TapDecodeTests.swift` | `TapWire` names no `trusted` key |
| 2 | argv `["trust","acme/tools"]` / `["untrust","acme/tools"]`; Untap and Force Untap submit untrust **first**; `requiresConfirmation` true/false; `invalidates == [.taps,.installedInventory]`; `packageID == nil`; namespaced `verb` | `TapCommandTests.swift` | the cases do not exist |
| 3 | exact `warningText` for `.tapAdd` and `.tapTrustGrant`; `.packageRemoval` / `.forceUntap` / protocol default unchanged | `ConfirmationDisclosureTests.swift` | `.tapTrust` still asserts a grant (`:93`) |
| 4 | badge per trust state; `.unreported` yields no control; the withheld third state; exact-match behaviour preserved | `TapProjectionTests.swift` | no trust projection; `exactInstalled` has two states |
| 5 | `tap: null` → `nil`; `"acme/tools"` → that value; key absent → `nil`; the record is still projected | `InstalledDecodeTests.swift` (:104) | `?? ""` collapses null today |
| 6 | refusal prose on stderr + non-zero exit → `.refusedUntrustedTap`; same prose on **stdout** → `.failed`; exit 0 → `.succeeded` | `ClassificationTests.swift` | the case does not exist |
| 7 | **the prohibition**: no mutation argv contains a `/`-qualified package token, on any path including refusal recovery and retry | `MutationCommandTests.swift` (beside :289) | `MutationName.isSafe` permits `/` (`:130-133`) |
| 8 | a force-untap batch led by `.untrustTap` still presents the **force-untap** disclosure, not the default | `MutationCommandTests.swift` / spine suite | Approach §5's conflict is live |
| 9 | `TapManagementAction.allCases` == 8; pinned button set == `["Add Tap","Untap","Force Untap","Show in Installed","Trust","Untrust"]`; excluded-capability scan still clean | `TapShippingProofTests.swift` (:90, :194, :287) | the pinned sets are 6 and 6 |
| 10 | Add Tap raises exactly one `.tapAdd`; Trust raises exactly one `.tapTrustGrant`; **Untrust raises none**; Brewfile import still raises exactly one and grants nothing | `cellarTests/BrewfileCompositionTests.swift` + a tap composition test | the cases do not exist |
| 11 | Trust control present only for `.untrusted`; absent for `.trusted` and `.unreported`; badge text | `cellarUITests` | no control exists |
| 12 | `TapCommand.swift`'s `arguments` body stays free of `\(`, `joined(`, `split(` | `MutationCommandTests.swift:289` (shipped) | must stay green — a regression guard, not a new RED |

**`manual-evidence`** (maintainer's Mac, Homebrew 6.0.18; cannot be automated):

1. `brew tap juancasanueva/cellar` → Cellar shows **Untrusted** → in-app **Trust** →
   `brew trust --json v1` lists the tap → badge flips with no manual reload.
2. A bare-token upgrade of a package from an untrusted tap, launched from inside Cellar, renders
   `.refusedUntrustedTap` with brew's own `brew trust …` line visible in the log.
   **NOTE — binding: never run `brew upgrade` without `--dry-run` on the maintainer's Mac** (obs
   `#7724`). Use `--dry-run`, or the installed Home-Cellar, which declares `auto_updates`.
3. **Untap** a trusted tap → `brew trust --json v1` no longer lists it (the stale-grant fix).
4. Homebrew < 6 degradation is **not reproducible** here; it is covered by the `.unreported` decode
   test plus a documented limitation.

## Delivery

`single-pr` on `feat/m7-tap-trust` (branch-pr: `^(feat|…)/[a-z0-9._-]+$`), work-unit commits, RED → GREEN
per unit. Suggested work units, each a candidate chained-PR slice if the maintainer later wants one:

| WU | Unit | Rollback boundary |
|---|---|---|
| WU1 | decode `trusted` + `TapTrustState` + badge projection (tests 1, 4a) | drop the decode; badge disappears |
| WU2 | truthful copy: `.tapAdd` / `.tapTrustGrant` + the four spec renames (test 3) | revert the rename |
| WU3 | `InstalledPackage.tap: String?` + withheld state (tests 5, 4b) | independent — a strict honesty improvement with no dependency on trust |
| WU4 | `.trustTap` / `.untrustTap` + UI controls + shipping proof (tests 2, 9, 10, 11) | drop the two cases and their pinned entries |
| WU5 | untrust-before-untap + batch-disclosure resolution (tests 2, 8) | drop the prepend; `removeTap` returns to one command |
| WU6 | `.refusedUntrustedTap` + the argv prohibition (tests 6, 7) | drop the case; refusals return to `.failed` with the log |

### Size forecast

| Bucket | Lines |
|---|---|
| Core (`TapWire`, `TapCommand`, `TapProjection`, `InstalledDecoder`/`InstalledModels` + ≈6-9 readers, `MutationOutcome`, `BrewMutating`) | ~240 |
| App (`TapsListView`, `TapDetailView`, `MutationConfirmation`, `PRD.md`) | ~120 |
| Tests (7-8 files) | ~420 |
| Specs — explore's five MODIFIED + one ADDED | ~300 |
| Specs — the three deltas **this proposal added** (TM9, PM1, PM10, BF7) | ~150 |
| **Bottom-up subtotal** | **~1,230** |

The house's measured **1.9-2.3×** correction (established across M5 slices 3-5, reconfirmed by
`m6-release-pipeline`) is applied to the **code + test** buckets only — 780 → **1,480-1,795** — because
the spec buckets are enumerated requirement-by-requirement above and are not subject to the same
discovery drift. With specs (~450) and SDD artifacts (`proposal.md`, `design.md`, `tasks.md`, four spec
deltas) at ~600-900, the **PR total is roughly 2,530-3,145 authored lines**.

- **400-line budget risk: High** — this change is far above the default reviewer guard. Stated
  explicitly rather than discovered at PR time.
- Against the governing **5,000** budget: **Low** — ≤63 % at the ceiling. `single-pr` holds with **no
  `size:exception`**.
- If the maintainer prefers slices, the natural cut is **WU1-WU3** (read, badge, honesty, optional tap)
  then **WU4-WU6** (grant, revoke, refusal classification).

`sdd-tasks` MUST reuse this correction and MUST emit the exact guard lines
`Decision needed before apply: Yes|No`, `Chained PRs recommended: Yes|No`, and
`400-line budget risk: Low|Medium|High`.

## Risks

| # | Risk | L | Mitigation |
|---|---|---|---|
| **R1** | **Trust is a capability grant.** An implicit grant on *any* path — add, Brewfile import, refusal recovery, retry — hands arbitrary code execution to a third party without consent | **High** | TM12 states it as a rule; test 10 asserts it positively; test 7 asserts the argv prohibition as an **absence** over the whole mutation surface, not by review |
| **R2** | **The qualified-argv bypass looks like a bug fix.** `trust.rb#explicitly_allowed?` treats naming the qualified package as the grant, and `MutationName.isSafe` would not stop it | **High** | D1 prohibits it; test 7 pins it; PM10 records *why*, so a future reader does not "fix" the refusal |
| **R3** | **Stale grants** — untap leaves the entry in `trust.json`, and a Brewfile import can silently re-arm it | **High** | Untrust-before-untap (Approach §4); manual evidence 3 |
| **R4** | **The batch-disclosure downgrade** introduced by the untrust prepend would silently defeat the force-untap disclosure — the exact defect PM1 was written to fix | Med | Named in Approach §5; resolution recommended; test 8 pins it |
| **R5** | **Homebrew version drift** — a brew without a trust concept | Med | `.unreported` hides the badge and both controls and spawns no `brew trust`; test 1 |
| **R6** | **Refusal-prose drift**; the **formula** wording was unmeasured at proposal time — **measured 2026-08-23 (obs #7738), same phrase, closed** | Low | One structural phrase (`"untrusted tap"`), design-owned; a miss degrades to `.failed` with the verbatim log — the fallback `MutationOutcome` already documents. Widening needs no design change |
| **R7** | **Per-package grants** — a package individually trusted under an untrusted tap must never be described as untrusted, and must never be blocked | Med | No pre-launch gate (D1); all copy is **tap**-scoped; obs `#7724` is the evidence |
| **R8** | **`tap` optional migration** — ≈6-9 readers, and `CatalogPackage.tap` is a same-named different property | Low | **Not** compiler-enforced at the readers: Swift promotes the non-optional operand of `==`, so all three keep compiling and stay semantically correct (`nil` equals nothing). Only the declaration and the two decoder sites change; test 5 pins the decoder and `InstalledDeriveTests · everyTapReaderTreatsAbsenceAsNoMatch` pins the readers |
| **R9** | **Shipping-proof drift** — the pinned button set and action enum fail loudly | Low | Desired behaviour; test 9 updates both deliberately |
| **R10** | **Cross-spec rename churn** — `tapTrust` is named in four requirements across two other capabilities | Low | Enumerated exactly in Capabilities; mechanical and compiler-checked in Swift, prose-only in specs |
| **R11** | **Invalidation cost** — trust/untrust now refresh installed inventory as well as taps | Low | It is *required* (obs `#7724`: the `tap` field changes); TM9 declares it; one refresh per terminal, per the shipped rule |

## Rollback Plan

`rules.proposal` mandates one for anything touching the Xcode project file or target membership.
**`cellar.xcodeproj/project.pbxproj` is a binding 0-line diff**: `cellarTests/` and the CellarCore test
targets are `PBXFileSystemSynchronizedRootGroup`s, so new test files need no project edit.

The change is additive except for three pieces, reversible **in this order**:

1. Drop the untrust prepend and the batch-disclosure resolution — `removeTap` / `forceRemoveTap` return
   to one command each (WU5).
2. Drop `.trustTap` / `.untrustTap`, their UI controls and their shipping-proof entries (WU4, WU6).
3. Drop the `trusted` decode — the badge disappears, no behaviour changes (WU1).

`InstalledPackage.tap: String?` (WU3) and the `.tapAdd` rename (WU2) **can stay independently**: the
first is a strict honesty improvement with no dependency on the trust surface, and the second only
stops the app making a false claim. Reverting either is also a clean single-commit revert.

No cache file, no schema version, no Keychain item, no migration and no dependency is added, so a
revert orphans nothing. Post-revert checks: `swift build --package-path Packages/CellarCore` and
`xcodebuild build -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64'`.

**What rollback does NOT do**: reverting Cellar does not revoke a grant already written to
`trust.json`. `brew untrust <tap>` in Terminal remains the exit, and this must be stated in the PR body.

## Success Criteria

- [ ] The Add Tap confirmation no longer claims a grant; `.tapAdd`'s exact text is asserted by test 3.
- [ ] A tap's trust state is visible in both the list and the detail, sourced from one projection, and
      **absent entirely** when Homebrew does not report `trusted`.
- [ ] Trust and Untrust exist as separate commands with exact argv `["trust", name]` / `["untrust", name]`;
      Trust is confirmed with `.tapTrustGrant`, Untrust is not.
- [ ] `brew trust --json v1` no longer lists a tap after that tap is untapped from Cellar.
- [ ] An upgrade refused for an untrusted tap renders `.refusedUntrustedTap` with a path to Trust and
      the verbatim log — and **no** Cellar code path retries it with a qualified name.
- [ ] No mutation argv on any path contains a `/`-qualified package token (test 7 is green and
      non-vacuous).
- [ ] An installed package whose tap is withheld is never described as "Not installed.", and still
      offers **Show in Installed**.
- [ ] `TapManagementAction.allCases` == 8 and the pinned button set matches, with the excluded-capability
      scan still clean.
- [ ] Every RED unit 1-11 fails before its implementation and passes after; unit 12 never goes red.
- [ ] Four spec deltas land with the requirement names listed in Capabilities; `PRD.md` §3.7 no longer
      implies that adding a tap trusts it.
- [ ] `project.pbxproj`, `MutationCommand.swift` and `TapPayloadSource.swift` show **0-line diffs**;
      `BrewfilePlan.swift` changes only its install arm (**D3**) and is no longer bound to zero.

## Open Questions (settle at design — each has a default)

1. **The batch-disclosure rule (Approach §5).** Modify PM1 so a batch's disclosure skips commands that
   declare only the protocol default? *Default: yes* — it strengthens the anti-downgrade rule, adds no
   case, and leaves BF7 intact. This is the one question that touches a shipped security invariant.
2. **If the revocation fails, does the untap still run?** *Default: yes.* The user's primary intent is
   removal, and blocking it on a failed revoke leaves them unable to remove the tap at all; the failed
   untrust appears as its own visible operation in Activity rather than being swallowed.
3. **Control labels and badge placement.** *Default:* buttons labelled exactly **"Trust"** and
   **"Untrust"**; an **"Untrusted"** badge beside the tap name in the list row and in the detail header,
   with the Trust button inline in the detail header.
4. **Refusal message wording.** *Default:* Approach §6's sentence verbatim, tap-scoped and
   tap-agnostic, shown beside the untruncated log.
5. **Does the withheld-tap middle state still offer "Show in Installed"?** *Default: yes* — the handoff
   selects by exact `PackageID`, and that identity is exact regardless of what brew withholds.

**Not a question, recorded so it is not re-opened as one:** plain Untap gains **no** confirmation now
that it revokes a capability. TM7's "ordinary removal MUST NOT require confirmation" already pins it,
and revocation only *reduces* authority. The binding open-question count is therefore **five**, which is
the count the spec deltas and `design.md` state.
