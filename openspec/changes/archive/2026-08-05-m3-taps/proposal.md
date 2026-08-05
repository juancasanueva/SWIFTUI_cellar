# Proposal: M3-2 Tap Management (`m3-taps`)

## Intent and Users

Cellar cannot explain modern Homebrew source state, inspect third-party inventories, or safely add/remove taps. M3-2 serves users checking source state, adding a known tap, understanding exposed packages, removing it safely, or handling force-required removal. It delivers one auditable workflow without conflating tap inventory with Cellar’s catalog.

## Product Rules

- Read list/detail from one `tap-info --installed --json` snapshot. Show non-actionable Homebrew Core and Cask under **Official sources**, labelled “API-backed; no local tap required”; only third-party rows are mutable.
- Accept canonical `user/repo` additions only. Every add confirmation names the tap, exact command, and third-party code risk.
- List formulae/casks by kind. Installed matches offer **Show in Installed**; uninstalled names remain plain text with “Not in Cellar’s core/cask catalog.” Tap inventory never enters catalog search/detail; PD6 remains byte-for-byte unchanged.
- Plain untap is primary. Force appears only for a non-empty, current installed cross-reference and confirms every affected package with kind.
- If that set changes while confirmation is open or queued, fail closed before process spawn, refresh, and require fresh confirmation.
- Brew absence yields guidance and no process. Stale/failed installed inventory disables force rather than guessing. Zero third-party taps retains official rows and add. Unknown fields or malformed records preserve decodable records; malformed envelopes fail with last-good state retained. Large inventories require lazy/filterable presentation.
- Every terminal outcome refreshes taps exactly once; force also refreshes installed inventory. Every mutation writes one searchable, null-package history entry with namespaced verb and exact argv.

## Scope Boundaries

This slice excludes URLs/custom/private remotes, tap-inventory package installation, third-party catalog ingestion/fallback, Brewfile, security scanning, CI, cleanup, disk usage, RDD/receipts, and unrelated follow-ups.

## Capabilities

- **ADDED `tap-management`**: inventory, framing, cross-reference, mutations, freshness, disclosure.
- **MODIFIED `package-mutation`**: whole-block PM3 superset for typed add/force confirmation; existing uninstall/zap rules remain.
- **MODIFIED `installation-history`**: whole-block IH1/IH5 supersets for namespaced tap verbs, null identity, and search.
- **Unchanged:** `package-detail`, `operation-activity`, `installed-inventory`, `brew-execution`, `brew-detection`.

## Approach

Use dedicated `TapInventory`/`TapStore` and `TapCommand: BrewMutating` on the shared FIFO spine. `BrewMutating` stays unchanged; typed confirmation disclosure is the extension point.

| Area | Impact |
|---|---|
| `Packages/CellarCore/Sources/BrewClient/` | Tap source/store/commands, `.taps`, disclosure/invalidation |
| `cellar/Taps/`, composition, confirmation | UI, Installed handoff, typed presentation |

## Constraints, Risks, and Rollback

Forecast remains **3,000–4,200** source+test and **5,400–7,900** lifecycle lines. Against 1,200 with `single-pr`, `size:exception` is required before apply and is not granted. Risks: stale disclosure, PD6 leakage, hostile payloads, and known no-CI exposure. Roll back Taps composition, `.taps`, tap types, and disclosure additions; no catalog/schema migration exists.

## Success Criteria

- [ ] Specs can derive every rule and unchanged boundary without inventing product context.
- [ ] Apply remains blocked pending explicit `size:exception` approval.
