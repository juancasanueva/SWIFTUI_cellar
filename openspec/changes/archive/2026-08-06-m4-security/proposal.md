# Proposal: M4 Security (`m4-security`)

Anchors PRD.md **M4** (§7); features §3.5; risk §8; resolves §9 open question 3.

## Intent and Users

Cellar cannot say whether what a user installed is vulnerable, signed, notarized, or quarantined. M4 serves users auditing an inventory, triaging a CVE, judging whether an upgrade is security-motivated, or asking why a cask app will not launch. Exploration proved OSV cannot answer for most Homebrew formulae, so the promise becomes: state exactly what we know and what we do not.

## Product Rules (user-approved, binding)

- Coverage is typed: `covered(findings)` / `covered(clean)` / `notCovered(reason)` / `unavailable(error)`. "No source answered" MUST NEVER render as "no vulnerabilities"; not-covered is as visible as vulnerable.
- Discovery is OSV `querybatch` over a curated, in-repo, fixture-tested formula→ecosystem table — data, not inference. Anything absent is `notCovered`.
- NVD is enrichment only, by `cveIds` for already-found IDs; never per-package discovery. Volume scales with findings, not inventory.
- Formulae only for CVE. Casks get the local surface (signature, notarization, quarantine).
- Fix-version comparison only when both sides are strict SemVer; otherwise "fix published, comparison not possible for this version scheme". Unscored severity is `unrated`, never defaulted.
- Quarantine is read-only: enumerate, decode, explain, cross-reference with the signature verdict.
- Opt-in scan with a plain transmission disclosure; nothing sent before consent; cache readable offline; optional NVD key in the Keychain.

## Scope Boundaries

**In:** `SecurityKit` (advisory sources, pure matcher, mapping data, coverage/severity/provenance values, signature + quarantine inspectors behind protocols); `SchemaV2` lightweight `DismissedCVE`; Security section, findings, detail, dismissal, inspector panels.

**Out (non-goals):** quarantine clearing, bulk or single; cask CVE scanning; a Homebrew version comparator; per-package NVD discovery; local advisory index (declared **v1.1** path); `CatalogPackage` widening; `/Applications` sweeps (M5); any new `BrewMutating` family — the security upgrade is the existing `MutationCommand.upgrade`.

## Capabilities

- **ADDED `vulnerability-scanning`**: acquisition, caching, coverage states, conservative matching, severity tiers, fix-version semantics, dismissal keyed `(cveID, kind, name, version)`, provenance, degradation, disclosure.
- **ADDED `artifact-integrity`**: signing identity, notarization verdict, quarantine/provenance visibility for brew-managed artifacts; unprivileged only; explicit "could not assess".
- **MODIFIED `local-package-metadata`**: reconcile the no-version-comparator structural guard; snooze semantics stay byte-identical and MUST NOT reach the `SecurityKit` comparator.
- **Unchanged:** `catalog-sync`, `package-mutation`, `installed-inventory` (primary keg as-is), `installation-history`, `operation-activity`, `brew-execution`, `brew-detection`, `disk-usage`.

## Approach

`SecurityKit` depends on **`Catalog` only**, staying brew-free. `Persistence` gains a second inward edge (`→ {BrewClient, SecurityKit}`) for `DismissedCVE`; **`BrewClient` gains nothing**. Reuse the `CatalogSource` HTTP discipline, `CatalogSyncEngine` single-flight, `CatalogStore.adopt` ordinals, and `CleanupEvidence` typed honesty. Inspectors use Security.framework plus `getxattr`/`listxattr` — no subprocess, no `spctl`.

| Area | Impact |
|---|---|
| `Packages/CellarCore/Package.swift` | New product + tests target; `Persistence → SecurityKit` |
| `Sources/SecurityKit/`, `Tests/SecurityKitTests/Fixtures/` (new) | Sources, matcher, mapping, store, inspectors, OSV/NVD captures |
| `Sources/Persistence/` | `SchemaV2` stage, `DismissedCVE`, dismissal store |
| `cellar/Security/` (new), `AppSection`, `ContentView`, `cellarApp` | Section, selection, composition |

## Probe Gates Before Design

**U1** OSV `querybatch` over the real installed list — the coverage number that sizes the feature; capture as fixture. **U2** NVD `cveIds` round-trip: shape, CVSS across v2/v3/v4, unauthenticated limits. **U3** `SecStaticCodeCheckValidity` + `SecAssessmentTicketLookup` on a brew cask: latency, network dependence, unprivileged success. **U5** version-string corpus: how often strict SemVer applies. *(U4 dropped — clearing is out.)*

## Risks

| Risk | L | Mitigation |
|---|---|---|
| Thin coverage reads as broken | High | Coverage typed and prominent; UI claims only its real scope |
| False negatives shown as clean | Med | `notCovered` can never collapse to `clean`; spec + structural test |
| Comparator leaks to snooze | Med | Confined to `SecurityKit`; guard reconciled, not deleted |
| NVD rate limits | Med | Enrichment-only; key optional, Keychain-stored |
| Privacy vs PRD §1 principle 3 | Med | Opt-in, disclosed, reversible, offline-readable |
| First `V1 → V2` migration | Med | Lightweight, additive; V1 rules held |

## Rollback Plan

Remove the `SecurityKit` target/product and the `Persistence` edge from `Package.swift`; delete `Sources/SecurityKit/`, `Tests/SecurityKitTests/`, `cellar/Security/`; drop the `.security` `AppSection` case, its selection state, and the `cellarApp` construction. Xcode project changes are file-reference and group removal only — no target-membership or build-setting edits. `SchemaV2` reverts by deleting the additive stage and `DismissedCVE`; the app is pre-release, so no shipped store migrates.

## Delivery

Session budget **5,000** lines, `single-pr`. Forecast: **4,600–6,400** source+tests, **7,400–10,600** lifecycle. **No size exception or slicing decision is granted here** — the review workload guard resolves it after `sdd-tasks`.

## Success Criteria

- [ ] Specs derive every coverage state, matching rule, and non-goal without inventing product context.
- [ ] The no-comparator reconciliation is spec-level and testable, not a comment.
- [ ] U1/U2/U3/U5 outcomes recorded before design closes.
- [ ] Apply stays blocked pending the workload guard decision.
