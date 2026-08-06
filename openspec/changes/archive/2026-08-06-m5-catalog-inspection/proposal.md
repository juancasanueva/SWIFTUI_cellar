# Proposal: M5 Catalog Inspection (`m5-catalog-inspection`)

Anchors PRD.md **M5** (§7); features §3.1 (pre-install cask inspection) and §3.2 (release-notes
inputs). Slice **1 of 5** per the recorded M5 decision round (Engram obs 7477). Exploration:
`openspec/changes/m5-pro-parity/explore.md` (obs 7476).

## Intent and Users

A user about to install a cask cannot see what it will put on their machine. Cellar shows
description, homepage and version, then hands off to an installer that drops an app bundle,
binaries, launch agents and later-zappable paths the user never saw. **That data is already inside
the record Cellar downloads and discards.** This slice serves the user deciding *whether* to
install — the moment before an irreversible-feeling action — and, secondarily, unblocks slice 3 by
widening the formula URL keys release-notes resolution needs. It is the only ordering edge in M5.

## Product Rules (user-approved, binding)

- **Catalog-derived only.** No `brew info`, no new brew invocation, no per-package network call.
- **No pre-install signature or notarization claim.** Not derivable from catalog data; M4's
  `ArtifactIntegrityEngine` + `CodeSignatureInspecting` stay post-install. The UI MUST NOT imply a
  verdict it does not hold.
- **Absent is not empty.** A cask publishing no `depends_on` renders no row; a stanza the projection
  cannot represent is counted and named, never silently dropped (`skippedRecordCount` idiom).
- **Displayed, never executed.** `uninstall` and `zap` stanzas are shown as text; Cellar runs none of
  them and offers no action from this surface.
- **What is shown is what is decoded** for every cask — no field appears for one record and silently
  vanishes for another.

## Scope

**In:** `CaskWire` + `CatalogPackage` widened with `url`, `sha256`, `artifacts`, `depends_on` and
`conflicts_with` (the fifth key is **not** decoded today, contrary to the exploration's reading);
`FormulaWire` + `CatalogPackage` widened with `urls.stable` / `urls.head` (carried for slice 3, not
rendered here); `CatalogSnapshot.currentSchemaVersion` bumped to **2**; probe **U4** and the
resident-memory/footprint decision it gates, with a regression test; an always-visible cask
inspection section in `cellar/Browse/PackageDetailView.swift`.

**Out (non-goals):** any pre-install signature/notarization surface; rendering formula URLs;
release-notes fetching (slice 3); Discover (slice 2); Brewfile (slice 4); health dashboard and
bulk pin/snooze (slice 5); new brew commands, new HTTP endpoints, new `InvalidationScope` bits, new
CellarCore targets.

## Capabilities

- **MODIFIED `catalog-sync`** — *Tolerant decoding of the published payload shapes* gains the
  widened cask/formula keys and their absence tolerance; *Slim persisted projection with a state
  sidecar* gains a measured footprint bound and the `schemaVersion` 1 → 2 transition rule.
- **MODIFIED `package-detail`** — *Required detail projection* gains the cask inspection fields plus
  an explicit prohibition on any pre-install signature verdict.
- **New capabilities:** None.
- **Unchanged:** the other 14 shipped capabilities.

## Approach

Widen the wire key-subset, not the strategy: every new field stays `decodeIfPresent`, preserving the
catalog design's key-subset discipline (D8) that makes a 31 MB dump decode into megabytes. Projection stays inside `Catalog`;
`CatalogDecoder.project(cask:)`/`project(formula:)` are the only decode changes. Artifacts land as a
typed value (stanza kind + payload) rather than free-form JSON, so the UI renders a closed set and
the unknown remainder is counted. The app target adds a presentation-only section; no store, no
acquisition, no actor-isolation change. All decode work stays `@concurrent static func` over `Data`.

| Area | Impact |
|---|---|
| `Sources/Catalog/Wire/CaskWire.swift`, `Wire/FormulaWire.swift` | Modified — new keys |
| `Sources/Catalog/CatalogModels.swift`, `CatalogDecoder.swift` | Modified — projection + artifact value type |
| `Sources/Catalog/CatalogFileStore.swift` | Modified — `currentSchemaVersion` 1 → 2 |
| `cellar/Browse/PackageDetailView.swift` (+ possible new subview file) | Modified/New — inspection section |
| `Tests/CatalogTests/` (+ `Fixtures/cask-iterm2.json` companions) | New cases, memory/footprint regression test |

## Probe Gate Before Design

**U4** — full-catalog resident memory **and** persisted-snapshot size **and** load time, with the
widening vs. today, on the real ~8k-cask payload. Design MUST NOT close before U4 reports. If U4
shows an unacceptable cost, decision **D5** applies: narrow the projection. There is no
raw-payload-retention branch and no per-cask fetch branch to evaluate.

## Risks

| Risk | L | Mitigation |
|---|---|---|
| Resident-memory / disk regression across ~8k casks | High | U4 measures before design closes; regression test pins the bound |
| Schema bump discards every existing cache → one full re-download | Low | Accepted (D1): no users yet; the non-blocking first-run path with observable progress already exists (CS8) |
| UI implies a security verdict it does not hold | Med | Spec-level prohibition + wording reviewed against M4's coverage vocabulary |
| Artifact stanza shapes are heterogeneous and undocumented | Med | Closed typed set + counted unknown remainder; fixture-driven |
| Slice 3 blocked by an incomplete formula widening | Low | `urls.stable`/`urls.head` land here even though nothing renders them |

## Rollback Plan

Additive and revertible by `git revert` of the slice PR. `Package.swift` is untouched — no new
target, product or dependency edge. Xcode project changes, if any, are **file-reference and group
additions only**; no target-membership, build-setting or scheme edit, so rollback is reference
removal. Reverting restores `currentSchemaVersion = 1`; the on-disk v2 snapshot is then classified as
"no cache" (`loadSnapshot` returns `nil`) and the app re-syncs once — degraded for one sync, never
corrupt. The bump is symmetrical in both directions, which is what makes it a safe rollback.

## Delivery

Session budget **5,000** lines, `single-pr`, strict TDD. Forecast **900–1,400** authored source+tests,
**2,000–3,200** including lifecycle artifacts. **No size exception is granted here** — the review
workload guard resolves after `sdd-tasks`.

## Success Criteria

- [ ] A user can see download URL, checksum, what gets installed where, dependencies and the
      auto-updates flag **before** installing a cask.
- [ ] No surface claims a pre-install signature or notarization verdict.
- [ ] U4 is recorded, and the memory/footprint bound is a test, not a comment.
- [ ] `urls.stable`/`urls.head` are projected and asserted, so slice 3 starts unblocked.
- [ ] D1–D5 are each traceable to a spec requirement before design closes.

## Resolved Decisions (user-approved, binding)

Answered in the proposal question round. These are decisions, not assumptions; specs derive from
them and MUST NOT re-open them.

- **D1 — Snapshot schema bumps to 2.** `CatalogSnapshot.currentSchemaVersion` goes `1 → 2`, so every
  existing on-disk snapshot is classified as "no cache" and re-downloaded once. Rationale: *there are
  no users yet*, so the one-time full re-download costs nothing real, and inspection data is present
  the first time a user opens a cask rather than after the next 24 h sync. The deferred-visibility
  alternative (keep `1`, all-optional fields) is **rejected**: it would ship a feature that silently
  does nothing on first launch.
- **D2 — Curated artifact stanzas with a counted remainder.** The projection carries `app`, `binary`,
  `pkg`, `zap` and `uninstall`; every other stanza is counted and surfaced as "N other stanzas not
  shown". This bounds the memory widening and keeps the absent-is-not-empty rule honest.
- **D3 — `conflicts_with` is in scope.** It becomes the fifth widened `CaskWire` key. It answers the
  "will this break something I already have" question, which is the point of pre-install inspection.
- **D4 — Always-visible section, plain-language rendering.** The inspection section is not behind a
  disclosure. `app`, `binary` and `pkg` stanzas render in plain language ("installs iTerm.app into
  /Applications"); `zap` and `uninstall` render faithfully as paths/commands.
- **D5 — U4 fallback is projection narrowing.** If measurement rejects eager projection, drop
  `artifacts` and keep `url`/`sha256`/`depends_on`/`conflicts_with`. Retaining the raw casks payload
  on disk and per-cask network fetching are both **rejected** — this slice adds no new egress and no
  new on-disk payload, and that promise outranks stanza coverage.
