# Design: M5 Catalog Inspection

Derived from `proposal.md` (decisions D1–D5) and the two deltas under `specs/`. Probe input: **U4**
(obs 7482), which closed the design gate and **triggered D5**.

## Technical Approach

No new target, no new protocol boundary, no new external dependency: this slice widens an existing
key-subset and adds one presentation-only view. The whole design is the answer to one measured fact —
keeping `artifacts`/`depends_on`/`conflicts_with` as a JSON value tree costs **+28.3 MB resident,
+6.6 MB on disk and a 4.7× launch reload** over 16,214 records, and was rejected. Everything below is
the trimmed typed shape U4 accepted (+6.3 MB resident, +3.6 MB encoded, +21% reload).

Three rules follow from the measurement and govern every type in this document:

1. **Nothing untyped is ever persisted.** No `JSONValue`, no `[String: Any]`, no raw stanza payload.
2. **Nothing unmodelled is ever materialised.** The artifact wire reads only the stanza keys it
   represents; an unrepresented key is *counted from its key alone*, its value never decoded into a
   Swift object. (The parser still scans those bytes — the claw-back is allocation, not I/O.)
3. **URLs are `String`.** Foundation `URL` doubled the resident cost of the same data (+7.2 vs
   +3.3 MB). `URL` is reconstructed at the view boundary, for one package at a time.

## Architecture Decisions

| Choice | Rejected | Rationale |
|---|---|---|
| **Curated stanzas narrow to `app`, `binary`, `pkg`; `zap` and `uninstall` join the counted remainder** | D2's five-kind set; a raw stanza blob | See "The D5 Narrowing" below — this is the one decision U4 delegated. |
| Two grouped optionals on `CatalogPackage` (`caskInspection`, `formulaSources`), not seven flat fields | Seven flat fields | `CatalogPackage` has a hand-written 20-parameter `init` **and two full-field copy helpers** (`replacingEdges`, `replacingInstallCount`). Seven fields means 21 new lines across three call sites and a silent-drop bug in each; two fields means six. |
| `String` for every URL-shaped value | Foundation `URL` | U4: `URL` costs 2.2× the resident bytes of the same string at catalog scale. |
| `CaskDownloadChecksum` as a two-case enum with a single-value `Codable` | `String?` | Casks really publish `"sha256": "no_check"`. `String?` forces the UI to choose between printing `no_check` as if it were a digest and silently dropping a published fact. The enum costs zero extra bytes (it encodes as the same string) and makes the wrong render unrepresentable. |
| Nested groups omit empty collections at encode time | Synthesised `Codable` | A cask publishing `artifacts` with no representable stanza would otherwise persist `{"apps":[],"binaries":[],"packageInstallers":[],"unrepresentedStanzaCount":3}` ≈ 75 B × 7,684 ≈ **0.58 MB** of literal emptiness. Custom `encode(to:)`/`init(from:)` writes ~8 B instead; the public type still exposes arrays, never optionals, so the absence rule stays per-field. |
| Group is `nil` when the record published *none* of the widened keys | Always-present group of nils | Keeps "absent" cheap and keeps the uniformity rule (PD) literally true. |
| Footprint bound asserted as **ratios against a same-process baseline**, plus one absolute disk ceiling | Three absolute numbers | Absolute wall-clock and resident numbers are machine-dependent; ratios are not. Every ratio below rejects the measured widened-raw variant with headroom over the accepted one. |
| Resident measured via malloc-zone `size_in_use`, not `phys_footprint` | Reusing `MemoryProbe.physFootprint()` verbatim | U4 gotcha: under magazine malloc `phys_footprint` never falls on free, so a baseline-then-widened comparison **inside one process** reads the baseline's high-water mark as the widened figure. `physFootprint` stays correct for the existing growth-only budget in `CatalogMemoryTests` and is kept there. |
| A download URL becomes a tappable `Link` only for `http`/`https` | `Link(destination: URL(string:)!)` | `url` is attacker-influenced catalog text; a `Link` hands it to the workspace opener. The scheme predicate lives in CellarCore (`CaskInspection.browsableDownloadURL`) so it is testable without a view; other schemes render as selectable text. |

## The D5 Narrowing (the one judgment U4 delegated)

U4 measured, per cask-artifacts encoded byte delta: `target` 0.84 MB, **`zap` 1.23 MB**, `font`
0.54 MB, `uninstall` 0.19 MB, and `app`/`pkg`/`binary` together **0.15 MB**. The accepted +3.6 MB
figure excludes `target`/`font`/`uninstall`; `zap` was left to this document.

**Decision: `zap` and `uninstall` contents are not projected.** Both are counted in
`unrepresentedStanzaCount` and surfaced as "N other install steps aren't shown here."

- **Cost of the alternative, on the record:** +1.23 MB encoded (**+34% over the whole accepted
  widening**) and an estimated +2–3 MB resident, for a field outside the proposal's success criteria.
- `zap` is not a name list. It is a directive map (`trash`, `rmdir`, `delete`, `launchctl`,
  `pkgutil`, `signal`, `login_item`, `script`, …). Representing it faithfully re-introduces exactly
  the heterogeneous-tree shape U4 rejected — the byte cost is the smaller half of the objection.
- The binding success criterion is "download URL, checksum, **what gets installed where**,
  dependencies and the auto-updates flag". `app`/`binary`/`pkg` answer it for 0.15 MB. `zap` answers
  a different question — what an *uninstall* would remove — which Cellar can answer at uninstall
  time, where `MutationCommand.uninstall(…, zap:)` already lives.
- **This is a narrowing, not an overreach.** D5's own fallback is stricter: *drop `artifacts`
  entirely*. This design keeps the cheap 0.15 MB that carries the success criterion and drops the
  expensive rest. D2's five-kind list and D4's "zap and uninstall render faithfully" are superseded
  by D5 *as triggered*, which is the mechanism D5 exists to provide.

**Consequence — a spec amendment is required at apply time, not an implicit divergence.** In
`specs/package-detail/spec.md`: the closed set becomes `app`, `binary`, `pkg`; the scenario "Every
curated stanza kind is exposed" narrows to three kinds with remainder `0`; the scenario "Zap and
uninstall stanzas are data, not runnable operations" is restated over the projected stanzas plus the
counted remainder (the displayed-never-executed rule survives — there is now nothing runnable to
expose at all, which is a strictly stronger guarantee). Recorded as Open Question 1.

## Interfaces

```swift
// Sources/Catalog/CatalogInspection.swift — all Codable, Sendable, Hashable value types.
public struct CaskInspection {           // nil for formulae, and for a cask publishing none of these
    public let downloadURL: String?
    public let declaredChecksum: CaskDownloadChecksum?
    public let installPlan: CaskInstallPlan?     // nil when `artifacts` was not published
    public let requirements: CaskRequirements?
    public let conflicts: CaskConflicts?
    /// `http`/`https` only; every other scheme yields nil and renders as text.
    public var browsableDownloadURL: URL? { … }
}
public enum CaskDownloadChecksum { case declared(String), notChecked }   // "no_check"
public struct CaskInstallArtifact { let source: String; let target: String? }
public enum CaskInstallDestination { case explicit(String), defaultApplicationsFolder }
public struct CaskInstallPlan {
    let apps, binaries, packageInstallers: [CaskInstallArtifact]
    let unrepresentedStanzaCount: Int            // 0, never absent, when all were represented
}
public struct CaskRequirements { let formulae, casks: [String]
                                 let macOSRequirement: String?; let unrepresentedCount: Int }
public struct CaskConflicts    { let casks, formulae: [String]; let unrepresentedCount: Int }
public struct FormulaSources   { let stableURL, headURL: String? }   // strings, from urls.stable/head
```

`CatalogPackage` gains exactly `caskInspection: CaskInspection?` and `formulaSources: FormulaSources?`,
both defaulted to `nil` in the public `init` so no existing call site changes.
`CatalogSnapshot.currentSchemaVersion` becomes `2`, and the `revision` doc comment — which today
claims "so `schemaVersion` stays 1" — is corrected in the same edit; it is falsified by the bump.

**Wire.** `CaskWire` gains `url`, `sha256`, `artifacts`, `depends_on`, `conflicts_with`, all
`decodeIfPresent`. `CaskArtifactsWire` decodes the array element-by-element through a dynamic
`StanzaKey: CodingKey`: for each element's keys, a key in `{app, binary, pkg}` decodes its value as a
lossy item list; **every other key increments the counter without its value being decoded**; a
non-object element counts `1` and is skipped. Inside a stanza, a `String` element is a `source` and a
following `{"target": …}` object attaches to it (Homebrew's `app "X.app", target: "Y"` serialisation);
any other object is ignored. Nothing here throws — an unreadable stanza costs a count, never the
record. `FormulaWire.versions` is joined by a `urls` object mirroring the same tolerance. Note for
apply: the formula stable digest key is `checksum`, not `sha256` — out of scope here, do not conflate.

**Concurrency and isolation.** Every new type is a struct of `String`/`Int`/`enum`/arrays, so
`Sendable` is trivially satisfiable and is **declared explicitly** on each public type rather than
inferred. Decoding stays exactly where it is: `CatalogDecoder.decode(_:at:)` in
`CatalogSyncSupport.swift`, `@concurrent` on its own line **before** `public static func`, off the
caller's executor — the widening adds no `await`, no actor, no isolation boundary and no new
`Sendable` crossing. `CaskInspection` crosses from the decoder into `CatalogSnapshot` into the
`@MainActor` store as part of an already-`Sendable` `CatalogPackage`; no new domain is created. No
`@unchecked Sendable`, no `nonisolated(unsafe)`, no `#available`.

**App layer.** New `cellar/Browse/PackageInspectionSection.swift`, one call inserted into
`PackageDetailView.content(for:)` after `facts(for:)`. Always visible for casks (D4), never behind a
disclosure; rows for absent values are not rendered at all, per the view's existing rule. It reads
CellarCore values and formats English; every *fact* it needs (the default `/Applications`
destination, the link-safety predicate) is a CellarCore computed property, so the app target keeps
only view code. Identifiers `inspection-download`, `-checksum`, `-installs`, `-requires`,
`-conflicts`, `-remainder`. Copy carries no verdict vocabulary: the checksum row reads "the value
this cask declares — Cellar has not downloaded or checked anything".

## Data Flow

```text
casks.json ──▶ CaskWire ──▶ CaskArtifactsWire (counts unmodelled keys, never decodes them)
                   │              │
                   └──────────────┴──▶ CatalogDecoder.project(cask:)  [@concurrent, off-main]
                                              │
                                   CatalogPackage.caskInspection
                                              │
                        CatalogSnapshot(schemaVersion: 2) ──▶ catalog.json  (+ catalog-state.json)
                                              │
                              CatalogStore (@MainActor) ──▶ PackageDetailView
                                              │                     │
                                              └── no brew, no HTTP ──┴─▶ PackageInspectionSection
```

## File Changes

| Files | Action |
|---|---|
| `Sources/Catalog/Wire/CaskWire.swift`, `Wire/FormulaWire.swift` | Modify — five and two new `decodeIfPresent` keys. |
| `Sources/Catalog/Wire/CaskArtifactsWire.swift`, `Wire/CaskRelationsWire.swift` | Create — typed lossy stanza scanner; `depends_on`/`conflicts_with` tolerance. |
| `Sources/Catalog/CatalogInspection.swift` | Create — the seven projected value types and their compact `Codable`. |
| `Sources/Catalog/CatalogModels.swift` | Modify — two grouped fields, both copy helpers, `currentSchemaVersion` 1 → 2, `revision` doc-comment fix. |
| `Sources/Catalog/CatalogDecoder.swift` | Modify — `project(cask:)` / `project(formula:)` only. |
| `cellar/Browse/PackageInspectionSection.swift` | Create — presentation only. |
| `cellar/Browse/PackageDetailView.swift` | Modify — one call site. |
| `Tests/CatalogTests/Fixtures/` | Create — `cask-every-stanza.json` (app+binary+pkg+uninstall+zap, `depends_on` with formula/cask/macOS), `cask-unrepresented.json` (app + 3 unknown kinds; and one with only unknown kinds), `cask-bare.json` + a `null`-publishing sibling, `cask-no-check.json`, a headless formula. `Fixtures/README.md` updated. |
| `Tests/CatalogTests/{DecodeTests,DetailTests,FileStoreTests,ProjectionTests}.swift` | Modify — widened decode, projection, schema-2 classification. |
| `Tests/CatalogTests/CatalogFootprintTests.swift` | Create — the recorded bound. |

`Package.swift` is untouched. The Xcode project gains one file reference in the existing `Browse`
group — no target-membership, build-setting or scheme edit — so rollback is reference removal plus
`git revert`.

## Testing Strategy

Strict TDD, RED before GREEN, in this order:

1. **Wire** — five cask keys decode; omitted *and* `null` both yield typed absence; `no_check` yields
   `.notChecked`; formula `urls.stable`/`urls.head`, head absent; `depends_on` in a non-`macos` form.
2. **Stanzas** — all three curated kinds with `target` companions; three unknown kinds count `3`; a
   cask of *only* unknown kinds decodes with count ≥ 1 and is not skipped; a non-object element
   counts; the remainder is `0`, not absent, when everything was represented, and is distinct from
   `skippedRecordCount`.
3. **Invariance** — the full slice fixtures produce the *same* record count and skipped count as
   before the widening (the spec's regression guard).
4. **Projection** — a package carrying inspection survives `replacingEdges` and
   `replacingInstallCount` unchanged. This test exists because those two helpers enumerate every
   field by hand and are the most likely silent-drop site in the change.
5. **Schema 2** — a v1 snapshot and a v1 sidecar are each independently no-cache; a v2 file is
   no-cache for a v1-expecting build (rollback symmetry, forced by temporarily overriding the
   expected version); nothing throws; the recording `FakeCatalogFileSystem` proves neither file was
   written or removed by the read.
6. **Footprint** (`.heavyFixture`, `.serialized`, `.timeLimit(.minutes(2))`, extending the shipped
   `SyntheticPayload`/`MemoryProbe` pattern) — generate 7,684 synthetic casks + 8,530 formulae, then
   measure baseline-shaped vs widened in one process: **encoded ≤ 1.6× baseline and ≤ 16 MB
   absolute; malloc-zone resident ≤ 1.6× baseline; snapshot load time ≤ 2.0× baseline.** Measured
   trimmed values are 1.42× / 1.35× / 1.21×; the rejected raw variant measured 1.78× / 2.59× / 4.75×
   and fails all three. An **anchor** assertion keeps the synthetic profile honest: the synthetic
   per-record encoded size stays within ±25% of the real fixtures' per-record size, so the bound
   cannot pass by measuring an unrealistically thin record.
7. **No new acquisition** — a recording `FakeCatalogSource` plus a recording process launcher: a
   widened sync issues exactly the previously requested resources, detail resolves offline with brew
   absent, and the catalog directory holds only `catalog.json` and `catalog-state.json`.
8. **Structural guards** — a source scan of `Sources/Catalog/CatalogInspection.swift` and
   `cellar/Browse/PackageInspectionSection.swift` finds no `signature`/`notariz`/`verified`/`trust`
   identifier and no `Process`/`OperationCenter`/`MutationCommand`/`removeItem` reference; a scan of
   the projection finds no `JSONValue`-shaped or `[String: Any]` stored property.

## Threat Matrix

| Boundary | Applicability | Response / RED |
|---|---|---|
| Subprocess / process integration | **Applicable — by prohibition** | The section displays installer-declared behaviour and runs nothing. No stanza is projected as an operation; `zap`/`uninstall` are not projected at all. RED: structural scan (8) plus a recording launcher asserting zero spawns during detail resolution. |
| Untrusted-string → URL opening | **Applicable** | `url` is catalog-published text handed to a `Link`. Only `http`/`https` become links; `javascript:`, `file:`, `data:` and scheme-less values render as selectable text. RED: parameterised over hostile scheme corpus against `browsableDownloadURL`. |
| Executable-file classification | **Applicable — by prohibition** | No signature, notarization, identity, team or trust field exists; `sha256` is a *declared* expectation, typed so `no_check` cannot render as a digest. RED: field enumeration over a fully populated cask yields no verdict-bearing field. |
| Network egress | **Applicable — by prohibition** | Zero new requests; inspection resolves from the snapshot alone. RED: scenario 7. |
| Filesystem write during inspection | **Applicable — by prohibition** | Reads never mutate; classification of a rejected file rewrites nothing. RED: scenario 5. |
| VCS/PR automation, routing, documentation-path classification | N/A — no such boundary | None. |

## Migration / Rollout

Pre-release, no users: the `1 → 2` bump discards every on-disk snapshot and sidecar exactly once, and
the shipped non-blocking cold-launch path (CS8) covers the one re-download. The bump is symmetric —
a reverted build classifies a v2 file as no cache, re-syncs once and rewrites nothing — which is what
makes `git revert` of this slice a complete rollback.

## Open Questions

- [ ] **The D5 narrowing needs the user's acknowledgement, and the delta needs the amendment above.**
      `zap`/`uninstall` contents are dropped against the literal text of D2/D4, under D5's authority
      and with the byte cost recorded. If the user wants "what a zap would remove" pre-install, it is
      +1.23 MB encoded and a directive-map model, and D5's bound must be re-opened deliberately.
- [ ] **`CatalogPackage.homepage` is still a Foundation `URL`.** U4 showed `URL` costs ~2.2× `String`
      at 16k scale, so the *existing* baseline carries avoidable resident bytes. Out of scope here
      (not a widened key, and it would change a shipped field's type); registered as a follow-up.
      **Confirmed at apply time (task 8.2):** the field is unchanged, every *widened* URL-shaped
      value is `String`, and `URL` is reconstructed only at the view boundary via
      `CaskInspection.browsableDownloadURL`.

## Apply-Time Amendments (recorded, not silent)

Two things the implementation had to decide differently from the text above. Both are recorded here
rather than absorbed, because both change what a reader should expect from the code.

- **`target` is a recognised companion key, not a counted stanza kind.** The design describes only
  the in-array form (`{"app": ["X.app", {"target": "Y"}]}`). `Fixtures/cask-iterm2.json` — a verbatim
  live record — publishes the *sibling* form (`{"app": ["iTerm.app"], "target": "…"}`). Counting that
  key would make iterm2's remainder `2`, but `package-detail` R5 and task 4.1 both bind it to `1`.
  `target` is a modifier of a stanza, not a stanza kind, so **both** serialisations attach to the
  element's artifacts and neither increments the remainder. `StanzaWireTests` pins both forms.
- **The five widened `CaskWire` keys decode with `try?`, not `try`.** A cask publishing `artifacts`
  as an object rather than a list would otherwise cost the whole record, which `catalog-sync` T5
  forbids: the widening must not change which records decode. Only the keys that existed before the
  widening may cost a record. `DecodeTests.anUnreadableWidenedValueCostsNoRecord` pins it with all
  five published in unreadable shapes at once.

## Apply-Time Measurement (task 6.1, recorded)

The footprint harness measures the anchored synthetic corpus (7,684 casks + 8,530 formulae) at:

| Quantity | Bound | Measured | U4's rejected raw variant |
|---|---|---|---|
| encoded snapshot | 1.6× and ≤ 16 MB | **1.56×**, 11.4 MB | 1.78× |
| resident, loaded | 1.6× | **1.23×** | 2.59× |
| snapshot load time | 2.0× | **1.57×** | 4.75× |

The anchor was strengthened during apply. Comparing a synthetic *total* against a real record's
*total* proved to be apples-to-oranges — `cask-iterm2.json` has an unusually thin base — so the
harness now anchors two things independently: the synthetic **baseline** per-record size against the
50 verbatim records in each `*-slice.json`, and the synthetic **widening delta** against the delta
the same verbatim record actually pays, measured by re-projecting it with the widened keys removed.
Both sides of the delta anchor are the same record, so no corpus mismatch can flatter it. The real
deltas are 393 B per cask and 154 B per formula; the generator produces 386 B and 147 B.
- [ ] **Artifact-stanza vocabulary drift.** The counted remainder is honest but silent about *which*
      kinds it counted. If the remainder is routinely large, a debug-only kind histogram would tell
      us whether a fourth curated kind is worth its bytes.

*Size note: this document exceeds the 800-word skill budget, as every archived design in this
project does. The project convention — a design dense enough that apply needs no re-derivation —
wins, as it did for the spec phase.*
