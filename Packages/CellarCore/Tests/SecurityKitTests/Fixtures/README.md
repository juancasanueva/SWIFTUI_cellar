# SecurityKit fixtures

Byte-exact captures backing the `m4-security` advisory pipeline, held to the
`Tests/BrewClientTests/Fixtures/Cleanup/` bar: every file records its endpoint,
its exact request, its capture date and its exit status, and every file's
SHA-256 is recorded in `probe-manifest.txt`.

These fixtures are **test input**, not illustration. `FixtureManifestTests`
recomputes every digest on each run, so a fixture cannot be quietly edited to
make a failing test pass.

## Capture environment

| Item | Value |
|---|---|
| Capture date | 2026-08-06 |
| macOS | 26.5.2 (25F84), arm64 |
| Homebrew | 6.0.15-83-gd0b51c6 |
| `curl` | 8.7.1 (libcurl/8.7.1, LibreSSL/3.3.6, nghttp2/1.68.1) |
| Network | unauthenticated; no NVD API key was used or present |

Every capture exited `0` at the tool level; HTTP status is recorded per capture
below, including the deliberate `429`.

---

## `OSV/` — advisory discovery and hydration (probe U1, re-captured)

Endpoint: `https://api.osv.dev/v1/querybatch` (POST) and
`https://api.osv.dev/v1/vulns/{id}` (GET).

Request bodies were **authored** in canonical JSON — `sort_keys`, two-space
indent, one trailing newline — because they are also the byte-comparison target
for `OSVSourceTests.discoveryPostsExactlyOneQuerybatchWithTheMappedSubset`. Every
response file is the **unmodified** response body exactly as the server returned
it, including its single-line compact encoding.

| File | Request | HTTP | Observation |
|---|---|---:|---|
| `querybatch-request.json` | 7 mapped packages at their **real installed versions** | — | The request the shipped `OSVSource` must produce |
| `querybatch-response.json` | ↑ | 200 | `{"results":[{},{},{},{},{},{},{}]}` — **all seven clean**. An intentional all-empty capture, not an omitted one |
| `querybatch-affected-request.json` | the same real packages at **older** versions | — | Chosen to reach real advisories; the packages are real, the versions are deliberate |
| `querybatch-affected-response.json` | ↑ | 200 | 19 advisories across 5 results, each as `{id, modified}` |
| `vulns-*.json` | `GET /v1/vulns/{id}` | 200 | Seven hydrations, chosen to cover every scoring shape below |

The 7 mapped packages are exactly U1's genuine matches (Engram obs 7451), all of
which are installed on the capture machine: `bat`, `eza`, `ripgrep`, `sd`
(crates.io), `uv`, `protobuf` (PyPI), `llhttp` (npm).

`querybatch-response.json` being entirely empty is the **realistic** result and
is itself an assertion: U1 measured real curated coverage at ≈3–5% of an
inventory, and the packages that *are* covered are current. The affected batch
exists so the matcher has real advisory data to match against; without it, every
matcher test would be exercising the clean path only.

### Scoring shapes covered by the hydrations

The tiering rule is CVSS v4.0 → v3.1 → v3.0 → v2, else an advertised severity,
else `.unrated`. Each branch has a real record:

| File | `severity[]` | advertised | Exercises |
|---|---|---|---|
| `vulns-GHSA-7gcm-g887-7qv7.json` | `CVSS_V4` | `HIGH` | v4.0 preferred, alias `CVE-2026-0994` |
| `vulns-PYSEC-2026-1805.json` | `CVSS_V4` | — | v4.0 with no advertised severity |
| `vulns-GHSA-p24j-h477-76q3.json` | `CVSS_V3` | `HIGH` | v3.1, alias `CVE-2021-36753` |
| `vulns-PYSEC-2026-899.json` | `CVSS_V3` | — | v3.1, alias `CVE-2022-1941` |
| `vulns-GHSA-4gg8-gxpx-9rph.json` | *(none)* | `MODERATE` | **advertised severity used when no score exists** |
| `vulns-RUSTSEC-2021-0139.json` | *(none)* | *(none)* | **`.unrated`** — no score anywhere |
| `vulns-RUSTSEC-2020-0163.json` | *(none)* | *(none)* | `.unrated`, triangulating the above |

`database_specific` on the two RUSTSEC records carries only `{"license": "CC0-1.0"}`
— a present-but-irrelevant member, which is exactly why "no advertised severity"
must be decided by looking for the `severity` key rather than for an empty object.

---

## `NVD/` — enrichment by CVE identifier (probe **gate U2**)

Endpoint: `https://services.nvd.nist.gov/rest/json/cves/2.0` (GET).

| File | HTTP | Observation |
|---|---|---:|
| `cveids-request.txt` / `cveids-response.json` | 200 | 7 identifiers in **one** request; `totalResults: 7` |
| `cveids-unrated-request.txt` / `cveids-unrated-response.json` | 200 | 2 records with `metrics: {}` |
| `ratelimited-response.headers` / `.body` | **429** | Reproduced by 40 requests at concurrency 20 |

The exact query strings are in the `*-request.txt` files. The rate-limited pair
is stored as separate header and body files because **the body is not JSON**;
see below.

### U2 — the two answers this gate was opened to get

**U2 (a): does NVD accept a plural `cveIds` parameter?** — **Yes.** Seven
comma-separated identifiers in a single `cveIds=` query returned
`totalResults: 7` with HTTP 200. The design's batched-enrichment shape holds, and
`NVDSourceTests.identifiersAreBatchedAtOneHundred` is testing a real API
behaviour rather than an assumption. Singular `cveId=` also works for one
identifier and is *not* what the design uses.

**U2 (b): does a record with only a CVSS vector string and no `baseScore` yield
a tier, or stay `.unrated`?** — **The design default (`.unrated`) stands, but the
question's premise does not.** A CVSS metric with a vector and no `baseScore`
does not occur in this schema: wherever a `cvssMetricV2`/`V31`/`V40` entry
exists, its `cvssData` carries `baseScore`. Across every record captured here,
`vectorString` and `baseScore` are always present together.

The real no-score shape is different and is captured in
`cveids-unrated-response.json`: a CVE at `vulnStatus: "Received"` carries
`metrics: {}` — no CVSS metric of any version at all. A second shape appears in
`cveids-response.json`: `CVE-2022-1941` and `CVE-2026-0994` carry an `ssvcV203`
metric which has **no `cvssData` member**, so a decoder that iterates `metrics`
and assumes every entry is a CVSS score would crash or mis-tier on a record that
also has perfectly good v3.1 scores.

**Consequence for the tasks, recorded rather than silently followed** (this is
what task 2.2 requires): task 3.5's planned assertion
`aVectorOnlyRecordFollowsTheU2Answer` tests a case that cannot arise, so it is
replaced by two assertions that test the shapes that do —
`aRecordWithNoCvssMetricStaysUnrated` and
`aNonCvssMetricEntryIsIgnoredRatherThanTiered`. The design default is unchanged;
only the route to it is. Task 3.5 has been amended in `tasks.md`.

### The rate-limited response is not JSON

`ratelimited-response.body` is **17 bytes of `text/plain`**: `error code: 1015`.
It is a Cloudflare edge response, not an NVD JSON error envelope, and it arrives
with `retry-after: 0`.

This is direct evidence for the design's "classify status before any decode
attempt" rule. A client that decoded first would report a JSON decoding failure
for what is actually a rate limit, and `NVDSourceTests`'
`aRateLimitedEnrichmentKeepsFindingsUnratedAndNeverMakesAPackageClean` would be
asserting the wrong error. The unauthenticated limit is documented as 5 requests
per 30 seconds; in practice 10 sequential requests passed and a burst of 40 at
concurrency 20 produced exactly 20 × 429, so the limit is concurrency-sensitive
rather than a simple sliding window.

**Redaction:** the `set-cookie: __cf_bm=` value in
`ratelimited-response.headers` is replaced with `<REDACTED>`. It is a Cloudflare
bot-management session token with no evidentiary value. Every other header byte
is verbatim. No API key, credential or personal identifier appears in any file
in this directory.

---

## `Versions/` — the Homebrew version-string corpus (probe **gate U5**)

Three files, each carrying its own provenance header. Together they are the
`arguments:` source for `HomebrewRevisionTests`, `StrictSemVerTests` and
`VersionBoundaryTests`.

| File | Source | Rows |
|---|---|---:|
| `installed-versions.txt` | `brew list --formula --versions`, exit 0 | 159 |
| `homebrew-version-spec-corpus.txt` | Homebrew's `test/version_spec.rb` | 149 |
| `homebrew-pkg-version-spec-corpus.txt` | Homebrew's `test/pkg_version_spec.rb` | 10 |

### U5 — the measured split

Over the **real** 159-formula inventory:

| Class | Count | Share |
|---|---:|---:|
| strict SemVer | 125 | 78.6% |
| strict SemVer + `_N` revision | 9 | 5.7% |
| neither | 25 | 15.7% |

**78.6% is what the fix-comparison feature is worth**, because fix comparison
runs over the *installed* string: the 9 revision-suffixed rows are covered by
OSV but are not comparable, which is precisely the spec's `1.2.3_1` / `1.2.4`
scenario.

The two Homebrew corpora are the adversarial half — the inventory says what is
*common*, Homebrew's own tests say what is *possible*. They contribute `R13B`,
`R15B03-1`, `2017-04-17`, `20040914`, `8d`, `20c`, `2007f`, `HEAD`,
`HEAD-abcdef`, `1.2.3-p2` and `1.0.1e_1`.

Two real rows carry more weight than the rest:

- `pcre2 10.47_1` (inventory) and `1.0.1e_1` (Homebrew) — a `_N` revision suffix
  on an upstream that is **not** strict SemVer. The lexical split succeeds and
  strict SemVer then rejects the upstream. Two separate rules reaching two
  separate answers is the whole point of the version boundary.
- `1.0_0` and `2.1.4_0` (Homebrew) — revision **zero**, written explicitly.
  `split` must report `0`, not `nil`; `1.0_0` and `1.0` are different strings.
