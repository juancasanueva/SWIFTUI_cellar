# Archive Report: M3-3 Disk Usage (`m3-disk-usage`)

## Result

- Status: success
- Archive date: 2026-08-05
- Archive destination: `openspec/changes/archive/2026-08-05-m3-disk-usage/`
- Closed PRD milestone: **M3**, slice **M3-3 — Disk Usage**
- Artifact store: hybrid (OpenSpec + Engram)

## Gates

- Persisted tasks: **17/17 complete**, with no unchecked implementation task.
- Apply state: complete; OpenSpec apply-progress is absent by historical design, with hybrid evidence
  persisted in Engram observation **#7280**.
- Verification: **PASS WITH WARNINGS**; **0 blockers**, **0 critical findings**, **10/10
  requirements**, and **15/15 scenarios** compliant.
- Runtime proof: **775/775 core tests**, **12 UI tests**, and **2 app tests** passed.
- Native archive dependency: ready according to authoritative `gentle-ai.sdd-status` v1; no blocked
  reason was reported.
- Delivery used the maintainer-approved `size:exception` for the historical implementation.

## Specs Synced

| Domain | Action | Result |
|---|---|---|
| `disk-usage` | Created | Full capability promoted with 9 requirements / 10 scenarios. |
| `installed-inventory` | Updated | One requirement replaced as a strict superset, adding the exact linked-keg scenario. Main total: 14 requirements / 58 scenarios. |

No ADDED, REMOVED, or RENAMED section affected `installed-inventory`; every requirement and scenario
outside the one MODIFIED replacement was preserved. The delta sync completed before the change folder
was moved.

## Engram Traceability

| Artifact | Topic key | Observation ID |
|---|---|---:|
| Proposal | `sdd/m3-disk-usage/proposal` | 7257 |
| Spec | `sdd/m3-disk-usage/spec` | 7258 |
| Design | `sdd/m3-disk-usage/design` | 7259 |
| Tasks | `sdd/m3-disk-usage/tasks` | 7260 |
| Apply progress | `sdd/m3-disk-usage/apply-progress` | 7280 |
| Refreshed verify report | `sdd/m3-disk-usage/verify-report` | 7283 |

The hybrid archive report is persisted under topic key `sdd/m3-disk-usage/archive-report` with prompt
capture disabled.

## Preservation

- The complete M3-2 archive at `openspec/changes/archive/2026-08-05-m3-taps/` remained byte-for-byte
  unchanged; pre- and post-archive SHA-256 manifests matched for all 10 files.
- M3-2 promoted content in `tap-management`, `package-mutation`, and `installation-history` was not
  edited. The `installed-inventory` sync changed only the named M3-3 replacement block and appended
  its provenance entry.
- `Packages/CellarCore/Tests/BrewClientTests/TapShippingProofTests.swift` remained unchanged by this
  phase (SHA-256 `e8a0909c485e4fceab3e8d93f6f59341d68dfb8ecbc8520e0aa3e7576830c570`).
- Unrelated `openspec/config.yaml` content remained unchanged by this phase (SHA-256
  `a691a4cf1c244af545021046a0aeb4d0c67c1e915f22b89bf6a4b56db095868f`).
- No source or test file was modified by the archive phase. No commit, push, or pull request was
  created.

## Residual Warning and Working-Tree Caveats

The non-blocking verification warning remains in the audit trail: historical apply-progress omits
explicit TRIANGULATE and SAFETY NET columns despite complete passing behavioral evidence. The working
tree still contains unrelated/pre-existing modified and untracked OpenSpec state, including the M3-2
archive/promoted specs, `openspec/config.yaml`, and `TapShippingProofTests.swift`; this archive phase
did not reconcile or stage those changes.
