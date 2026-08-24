# Proposal: `m9-per-package-trust` — a read-only per-package trust surface

Anchors PRD §3.7 (:108). Carries `2026-08-23-m7-tap-trust` follow-up §9/§11 item 1.
Inputs: `explore.md` (obs `#7758`), maintainer scope decisions (obs `#7759`, binding).

## Intent

Homebrew 6 grants trust at two independent granularities; Cellar reads only one. On the maintainer's
Mac 8 taps render **Untrusted** while `brew trust --json v1` lists 9 formulae + 4 casks granted
individually — software that plainly works. The badge is correct *about the tap*; the user cannot
reconcile it, and Cellar shows nothing that could. Separately, per-package grants **survive an untap**,
so TM7's revocation leaves dormant grants a re-tap silently re-arms — invisible today.

## Scope

### In Scope
- New read `brew trust --json v1` with its **own** wire, payload source, store and invalidation domain.
- Three-valued state (`unreported` ≠ "zero grants"), mirroring `TapTrustState`.
- One projection value → `"N trusted individually"` on **both** the tap row and the detail header.
- `Trusted individually` marker on tap-detail package rows and beside `PackageDetailView`'s Tap fact.
- A dedicated **unattributed grants** section in Taps: orphans, URL-shaped formulae, and the
  `commands` namespace decoded and counted as "other". Nothing dropped silently.
- MODIFY **TM12** to scope its single-source clause to the *tap's own* trust state (do this first).
- MODIFY **PM10**: no pre-launch gate on per-package grant state either; C1 ban list extended with the
  new type names; C2's `≤ 1 slash per argv element` invariant stays byte-identical.
- `README.md:44-47` qualified-token sweep (doc-only; the canonical three-line install is unchanged).

### Out of Scope
- **Any** grant/revoke control for a package — it requires a `/`-qualified token in argv (PM10).
- The `brew untrust <qualified>` probe; it gates a future mutation slice only.
- R15 `BrewfileDiff.isPresent` fix — separate ~1-line slice.
- Changing the `Untrusted` badge; any negative per-package copy; a Brewfile trust column.

## Capabilities

### New Capabilities
- `package-trust`: reading, storing, attributing and surfacing Homebrew's per-package trust grants,
  read-only.

### Modified Capabilities
- `tap-management`: TM12's single-source clause scoped; additive count line permitted; badge unchanged.
- `package-detail`: the positive-only per-package marker beside the existing Tap fact.
- `package-mutation`: PM10 gains "no gate on per-package grant state"; the argv absence is reaffirmed.

## Approach

Clone the `m7-tap-trust` spine rather than extend it. `TrustGrantWire` / `TrustGrantPayloadSource` /
`TrustGrantStore` mirror `TapWire` / `TapPayloadSource` / `TapStore` — compile-time-constant argv,
in-flight coalescing, last-good retention, monotonic adoption. `TapProjection` gains the count and the
marker; attribution from a qualified entry to a `TapRecord` reuses `bareToken(_:publishedBy:)` and
`publishes(_:in:)`, never `split("/")`. Anything unattributed surfaces in its own section. All
per-package copy is **positive-only**: absence from the lists is not "untrusted".

## Affected Areas

| Area | Impact | Description |
|---|---|---|
| `BrewClient/TrustGrant{Wire,PayloadSource,Store}.swift` | New | The second read, store and domain |
| `BrewClient/TapProjection.swift` | Modified | Count value, marker, attribution |
| `BrewClient/TapCommand.swift:150-156`, `InvalidationScope` | Modified | New domain named by every family |
| `BrewClient/TapRefreshCoordinator.swift`, `cellar/cellarApp.swift` | Modified | Sequencing and DI |
| `cellar/Taps/TapsListView.swift`, `TapDetailView.swift` | Modified | Row line, markers, new section |
| `cellar/Browse/PackageDetailView.swift:557` | Modified | Marker beside the Tap fact |
| `Tests/BrewClientTests/MutationCommandTests.swift:471-479` | Modified | C1 ban list extended only |
| `README.md:44-47` | Modified | Qualified-token sweep |

## Risks

| Risk | Likelihood | Mitigation |
|---|---|---|
| R1 TM12 reads as absolute; this change contradicts it | High | MODIFY TM12 in the first work unit |
| R3 "2 trusted individually" reads as reassurance | Med | State grants, never a verdict (TM11) |
| R4 No `brew trust` verb → "0 grants" instead of `unreported` | Med | Three-valued state, tested |
| R6 Unattributable entries dropped | High | Unattributed section is a shipped surface |
| R7 Orphan grants stay armed | High | Say plainly: this surfaces, it does not revoke |
| R2/R5/R8 Wide `InvalidationScope` diff; second spawn; artifact overshoot | High | Forecast artifacts separately (m7 overshot 5–7×); split work units if the 5,000 budget is threatened |

## Rollback Plan

Revert the PR. Nothing persists: no file format, no migration, no stored state. The new store is
additive and read-only; deleting it returns the app to tap-only trust. The TM12/PM10 deltas revert with
the change folder; promoted specs are untouched until archive.

## Dependencies

Homebrew 6 with `brew trust --json v1`. Absent → `unreported`, by design.

## Success Criteria

- [ ] A tap with individually trusted packages shows the count on the row and header, from one value.
- [ ] Opening that tap names *which* packages, positively.
- [ ] Grants Cellar cannot attribute are visible and counted, including `commands`.
- [ ] No argv element in the whole mutation spine gains a second `/` (C2 test byte-identical).
- [ ] A Homebrew without `brew trust` renders `unreported`, never "0 grants".
