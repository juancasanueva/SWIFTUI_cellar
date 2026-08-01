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
