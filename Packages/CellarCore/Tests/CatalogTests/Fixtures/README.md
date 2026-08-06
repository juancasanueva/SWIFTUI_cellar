# Catalog test fixtures

Captured live from `formulae.brew.sh` on **2026-08-01** (formula.json / cask.json
`ETag: "6a6e2a26-…"`, `Last-Modified: Sat, 01 Aug 2026 17:17:26 GMT`).

Only excerpts are committed. The bulk dumps are ~31 MB (formulae) and ~17 MB (casks)
and must never enter the repository.

| File | Shape | Why it exists |
|---|---|---|
| `formula-wget.json` | one full record, verbatim | PD1 formula detail; proves unmodelled keys are ignored |
| `formula-git.json` | one full record, verbatim | PD2 direct dependencies (`[pcre2, gettext]` runtime / `[gettext, pkgconf]` build), PD3 inversion |
| `cask-iterm2.json` | one full record, verbatim | PD1 cask detail, `name: ["iTerm2"]`, `caveats: null` |
| `formula-slice.json` | 50 records, one per line, heavy keys stripped | deprecated/disabled records, mixed `uses_from_macos` |
| `cask-slice.json` | 50 records, one per line, heavy keys stripped | multi-entry `name` arrays, `desc: null`, deprecated/disabled |
| `formula-unknown-keys.json` | `wget` plus two invented keys | CS5 "unknown keys are ignored" |
| `analytics-formula-365d.json` | envelope + 40 items | CS9 comma-grouped counts, formula namespace |
| `analytics-cask-365d.json` | envelope + 40 items | CS9 cask namespace |

## Inspection fixtures (M5, `m5-catalog-inspection`)

Synthetic, not captured: they exist to pin shapes the live excerpts happen not to publish. Each is
registered in `Fakes/Fixtures.swift` (`Fixture.inspectionFixtures`), which is what proves the file
reached the test bundle.

| File | Shape | Why it exists |
|---|---|---|
| `cask-every-stanza.json` | `app` + `binary` + `pkg` + `uninstall` + `zap`; `depends_on` with formula, cask and macOS | every projected stanza kind with its `target` companion, and a remainder of exactly `2` |
| `cask-unrepresented.json` | one `app` stanza plus `zap`, `uninstall` and an invented `wormhole` kind | the counted remainder is `3`; also carries an unmodelled `depends_on`/`conflicts_with` relation key |
| `cask-only-unrepresented.json` | `font` + `zap`, no projected stanza at all | a cask of only unmodelled kinds still decodes, with a non-zero count |
| `cask-bare.json` | publishes none of `url`, `sha256`, `artifacts`, `depends_on`, `conflicts_with` | absence is absence, not an empty string/list/zero |
| `cask-bare-null.json` | publishes all five widened keys as `null` | `null` and omitted are the same answer |
| `cask-no-check.json` | `"sha256": "no_check"` | the literal is a *declaration of no checksum*, never rendered as a digest |
| `formula-headless.json` | `urls.stable` and no `urls.head` | an absent head source URL stays absent |

## Discovery fixtures (M5, `m5-discover`)

Synthetic, and in their own `Discovery/` subdirectory: none of them is a payload excerpt, and mixing
them into the table above would suggest they were captured from `formulae.brew.sh`. Each is
registered in `Fakes/Fixtures.swift` (`Fixture.discoveryFixtures`) and read through
`Fixture.discovery(_:)`, which is what proves the file reached the test bundle.

| File | Shape | Why it exists |
|---|---|---|
| `curated-tolerant.json` | 3 well-formed entries beside **five** distinct malformed ones, plus category and entry keys the decoder does not model | PD-R3 *Unknown fields and malformed entries are tolerated* — no blurb, blank blurb, no token, no kind, unknown kind; each is skipped **and counted**, and one bad entry never costs the file |
| `curated-duplicate.json` | formula `ripgrep` declared in two categories | PD-R3 *A duplicate token resolves once* — the first declaration wins and the redundant one is counted |
| `curated-unsorted.json` | categories `zeta`/`alpha`/`mu`, entries deliberately not alphabetical | PD-R3 *Declared order survives decoding* — a decoder that re-sorted would pass an alphabetical fixture |
| `roster-corrupt.json` | bytes that are not valid JSON | CS-A1 sc3 — corrupt means "seen nothing", never an error |
| `roster-wrong-version.json` | `schemaVersion: 99`, otherwise well-formed | CS-A1 sc3 — the gate is exact in both directions against `DiscoverySchema.currentVersion`, not against the snapshot's |
| `arrivals-corrupt.json` | bytes that are not valid JSON | CS-A2 sc4 — corrupt means "no arrivals" |
| `arrivals-wrong-version.json` | `schemaVersion: 99`, two decodable arrivals | CS-A2 sc4 — a readable body behind a rejected version is still "no arrivals" |
| `arrivals-undatable.json` | one entry whose `firstSeenAt` is a string, between two well-formed entries | CS-A2 sc5 — the undatable entry is dropped and the other two survive, so the decode is lossy per entry rather than per file |

The three hostile roster/arrivals fixtures are **untrusted on-disk input** (threat-matrix TM3): both
sidecars are writable by any local process, so every one of these shapes has to degrade to "seen
nothing" without throwing and **without the read mutating the file it rejected** (TM2).

`cask-iterm2.json`, `cask-slice.json` and `formula-slice.json` are the widening's regression control
and must stay **byte-identical**: the slices are what prove the widened wire decodes exactly the
records the previous build decoded. Note that `cask-iterm2.json` serialises its `app` destination as
a `target` key **beside** the stanza key, while `cask-every-stanza.json` uses the in-array companion
object — Homebrew emits both, and both must attach rather than count.

Stripped keys (slices only, to keep the diff reviewable): `bottle`, `urls`, `variations`,
`ruby_source_*`, `tap_git_head`, `installed`, `head_dependencies`, `post_install_steps`,
`link_overwrite`, `service`, `executables`, `pour_bottle_only_if`, `patches`,
`conflicts_with_reasons` (formulae); `artifacts`, `url_specs`, `variations`, `ruby_source_*`,
`tap_git_head`, `sha256`, `languages`, `container`, `installed*` (casks).

## Re-capture

```bash
tmp=$(mktemp -d)
curl -s -o "$tmp/formula.json"  https://formulae.brew.sh/api/formula.json
curl -s -o "$tmp/cask.json"     https://formulae.brew.sh/api/cask.json
curl -s -o "$tmp/an-formula.json" https://formulae.brew.sh/api/analytics/install-on-request/365d.json
curl -s -o "$tmp/an-cask.json"    https://formulae.brew.sh/api/analytics/cask-install/365d.json

# single-record fixtures come straight from the per-package endpoints:
curl -s https://formulae.brew.sh/api/formula/wget.json   > formula-wget.json
curl -s https://formulae.brew.sh/api/formula/git.json    > formula-git.json
curl -s https://formulae.brew.sh/api/cask/iterm2.json    > cask-iterm2.json
```

The slices and analytics excerpts are produced from `$tmp` with the selection recorded in
this table (50 records each, edge cases first, then alphabetical fill), written one JSON
record per line.

## Validator probe (task 0.3 / design D7)

`curl -sI` on all four endpoints returns **both** `ETag` and `Last-Modified`. Replaying
either `If-None-Match: "6a6e2a26-1d95bbf"` or
`If-Modified-Since: Sat, 01 Aug 2026 17:17:26 GMT` returns `HTTP/2 304`. Conditional
revalidation therefore ships with both validators, as designed — no CS2 re-scoping needed.
