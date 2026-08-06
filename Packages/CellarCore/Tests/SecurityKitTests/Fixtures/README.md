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

### Derived malformed payloads (phase 3, **not** captures)

Three files under `OSV/` are **derived**, not captured. They are recorded here
rather than hidden because a fixture whose provenance is "someone typed it" is
worth less than one whose provenance is "the real bytes, damaged in one named
way" — and because the manifest digests them identically to the captures, so a
reader must be able to tell which is which.

Every one is produced from `querybatch-affected-response.json`, the real 19-
advisory capture, by exactly one documented edit:

| File | Derivation | Proves |
|---|---|---|
| `querybatch-truncated-response.json` | the real bytes, cut at 180 bytes | An unreadable **envelope** fails the whole request |
| `querybatch-badrecord-response.json` | real result #2 (3 advisories), middle entry's `id` key deleted | An unreadable **record** costs that record and is counted |
| `querybatch-badresult-response.json` | real results #2 and #3, preceded by a string where an object belongs | An unreadable **result keeps its slot** |

The third one is the important one. OSV's `results` array is **positional** —
entry *i* answers query *i*, and nothing inside the entry names the package it
belongs to. Dropping a bad entry the way a lossy array drops a bad formula would
re-attribute every later answer to the wrong package: in this very fixture, three
real `llhttp` CVEs would be filed against whatever package was query 0, with
nothing in the payload left to catch it. So the slot survives, holding an
explicit "no answer", and `.unreadable` is deliberately not equal to
`.answered([])`.

The 17-byte `NVD/ratelimited-response.body` doubles as an OSV envelope fixture:
it is the real shape of a body that is not JSON at all, as opposed to JSON that
stops early.

---

## `NVD/` — enrichment by CVE identifier (probe **gate U2**)

Endpoint: `https://services.nvd.nist.gov/rest/json/cves/2.0` (GET).

| File | HTTP | Observation |
|---|---|---:|
| `cveids-request.txt` / `cveids-response.json` | 200 | 7 identifiers in **one** request; `totalResults: 7` |
| `cveids-unrated-request.txt` / `cveids-unrated-response.json` | 200 | 2 records with `metrics: {}` |
| `ratelimited-response.headers` / `.body` | **429** | Reproduced by 40 requests at concurrency 20 |
| `cveids-badrecord-response.json` | *(derived)* | The real 7-record capture with the **fourth** record's `id` deleted |

The exact query strings are in the `*-request.txt` files. The rate-limited pair
is stored as separate header and body files because **the body is not JSON**;
see below.

`cveids-badrecord-response.json` is **derived**, not captured — the same
discipline as the three derived `OSV/` payloads above, and derived by exactly one
documented edit. It exists to pin the difference between the two decoders: NVD's
`vulnerabilities` array is **not positional**, because every record names its own
CVE, so the unreadable record is dropped and the six survivors keep their
identities. OSV's `results` array carries no such name, which is why a bad entry
there keeps its slot instead. `totalResults` stays at the server's `7`, and the
gap between it and the six decoded records is the evidence that something was
lost.

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

### Correction to this capture's own commentary (phase 5)

`homebrew-version-spec-corpus.txt`'s header lists `1.2.3-p2` alongside
`1.2.3alpha4` as a "non-SemVer prerelease spelling" that must be rejected.
**That is wrong.** `p2` is an ordinary alphanumeric prerelease identifier, so
`1.2.3-p2` is valid SemVer 2.0.0 — structurally the same shape as the
`1.2.3-rc.1+build` task 5.3 requires the parser to accept, and the same shape as
the real `luv 1.52.1-0` in the installed inventory. `1.2.3alpha4` genuinely is
invalid, and the parser rejects it.

Accepting it is also the safe direction. Homebrew reads `-p2` as a patch level
*above* `1.2.3`, while SemVer orders a prerelease *below* its release, so the two
disagree — and the disagreement makes an installed `1.2.3-p2` look **older** than
a fix at `1.2.3`. That is a visible false positive rather than a silent false
negative, which is the direction this codebase chooses. No formula in the
captured inventory has this shape.

The corpus file's own header is **left byte-unchanged** so its recorded digest
still stands: the claim is corrected here and pinned by
`StrictSemVerTests.aHyphenatedPatchLevelIsValidSemVer`, rather than by editing a
file the manifest is meant to hold still.

### Notable rows

Two real rows carry more weight than the rest:

- `pcre2 10.47_1` (inventory) and `1.0.1e_1` (Homebrew) — a `_N` revision suffix
  on an upstream that is **not** strict SemVer. The lexical split succeeds and
  strict SemVer then rejects the upstream. Two separate rules reaching two
  separate answers is the whole point of the version boundary.
- `1.0_0` and `2.1.4_0` (Homebrew) — revision **zero**, written explicitly.
  `split` must report `0`, not `nil`; `1.0_0` and `1.0` are different strings.

---

## Addendum — the U3 probe (task 14.0), captured 2026-08-06

macOS 26.5.2 (25F84), arm64, **euid 501 — no elevation at any point**. SDK
`MacOSX26.5.sdk`. Homebrew 6.0.15-83-gd0b51c6. Full transcript:
`MachO/signature-probe-record.txt`. Cask layout survey: `Quarantine/cask-artifact-layout.txt`.

### U3 answer (a): `SecAssessmentTicketLookup` is **not callable at all** from a shipping app

Stronger than the design's question, and it changes what task 14.5 may do. The
symbol is **present in the shipped `Security` binary** and **absent from the
public SDK**: there is no `SecAssessment.h` under
`MacOSX26.5.sdk/…/Security.framework/Headers/`, and `SecAssessment` appears
nowhere in the framework's module map. `import Security` therefore does not
declare it, and a build that calls it fails with *cannot find
'SecAssessmentTicketLookup' in scope*.

Reached through `dlsym` **for the probe only**, it returned `false` in under
0.2 ms for every one of the four notarized casks — including with the
force-online flag — which is not a meaningful answer either. Whatever its real
contract is, it is not one this app can rely on through supported API.

**Consequence, and it is the amendment task 14.0 anticipated:** the inspector
does not call it. Non-stapled notarization is `.couldNotAssess(.assessmentUnavailable)`.
A weaker feature, not a different architecture — exactly as the design predicted.

### U3 answer (b): the supported path works unprivileged, and is **local**

`SecStaticCodeCreateWithPath` → `SecCodeCopySigningInformation` →
`SecStaticCodeCheckValidity(… "notarized")` succeeded at euid 501 on all four
notarized casks, with no prompt of any kind.

| Artifact | identifier | team | `notarized` | latency (5 consecutive calls) |
|---|---|---|---|---|
| Ghostty.app | `com.mitchellh.ghostty` | `24VZTF6M5V` | pass | 50.1, 46.6, 47.1, 46.4, 47.6 ms |
| VLC.app | `org.videolan.vlc` | `75GAHG3SZQ` | pass | 437.1, 429.7, 444.4, 452.7, 436.2 ms |
| CodexBar.app | `com.steipete.codexbar` | `Y5PE65HELJ` | pass | 61.5, 60.6, 60.7, 59.2, 59.3 ms |
| Applite.app | `dev.aerolite.Applite` | `9CLTNBW4Z3` | pass | 24.5, 22.6, 23.8, 22.9, 22.8 ms |

**Network dependence: none observed.** Three independent pieces of evidence.
(1) Latency is flat across five consecutive calls — a first call that reached
the network would be slower than the four after it, and none is. (2) The spread
tracks **bundle size**, not distance: VLC is ~9× Applite's time and ~9× its
content. (3) The negative case answers *immediately*: an ad-hoc-signed formula
binary fails `notarized` in **20.2 ms** with `-67050`, not after a network
timeout. The requirement is evaluated against the stapled ticket and the code
hashes, on this machine.

`anchor apple generic` passes for all four (Developer ID chains to the Apple
root). `anchor apple` fails for all four with `-67050` — it means *Apple's own
system binary*, which none of these is. Both are recorded because the design
names the first and it would be easy to reach for the second.

### U3 answer (c): formula keg binaries are **ad-hoc signed**, never notarized

`/opt/homebrew/Cellar/ripgrep/15.2.0/bin/rg`: identifier
`rg-555549448f89ec4d458733e9aff65b2c3b7acce2`, **no team identifier, no
authority chain**, `flags: 2` (`kSecCodeSignatureAdhoc`). All three requirements
fail with `-67050`.

This is the ordinary, correct state of a bottle, and it is why "unsigned",
"ad-hoc" and "could not assess" must be three distinct verdicts rather than
three ways of writing "not signed": the overwhelmingly common formula outcome is
*ad-hoc*, and rendering that as a failure would make the panel useless.

### Fixture check obs 7454(1): the Caskroom holds **symlinks**, not bundles

Surveyed across all 11 installed casks. Of the ten with an `.app` artifact:

- **9 are symbolic links** in the Caskroom pointing into `/Applications`, where
  the real bundle lives. `SecStaticCodeCreateWithPath` works on either path
  because it resolves them, but the bundle itself is not in the Caskroom.
- **1 is not** — `the-unarchiver` leaves a Caskroom *directory* containing a
  second nested `The Unarchiver.app`, and `SecStaticCodeCreateWithPath` rejects
  it with `-67028 bundle format unrecognized`. The real bundle is the
  root-owned `/Applications/The Unarchiver.app`.
- Every cask records its real destination itself, in the `app` artifact's
  `target` field.

**Binding on task 15.3.** A blind Caskroom walk finds nine symlinks and one
broken shell. `ArtifactLocator` resolves the **brew-recorded** artifact target,
and this is not an `/Applications` sweep: only paths Homebrew itself recorded
are ever visited.

### Quarantine captures

`Quarantine/*.txt` are the raw `com.apple.quarantine` values as `getxattr`
returned them, byte for byte. The `flags;hexTimestamp;agentName;UUID` shape the
design names is confirmed on real data, and two edges came with it:

| File | Raw value | Note |
|---|---|---|
| `vlc-com.apple.quarantine.txt` | `01c3;6a65eb27;Safari;3E44AF78-…` | all four components present |
| `codexbar-com.apple.quarantine.txt` | `03c1;6a719a00;;67F02780-…` | **agent name empty** — a real, common shape |
| `applite-com.apple.quarantine.txt` | `03c1;6a7198fa;;27BAE636-…` | second empty-agent case, different flags path |

`ghostty-com.apple.provenance.hex` is the 11 raw bytes of `com.apple.provenance`
in hex. It is **binary and undocumented**, which is exactly why the spec requires
presence to be *reported* and the contents never guessed.

Also present on these bundles and deliberately out of scope: `com.apple.macl`,
`com.apple.FinderInfo`, `com.apple.fileprovider.fpfs#P`. Recorded so that
"we enumerate the attributes we understand" is a stated boundary rather than an
oversight.

### Mach-O fixtures

`MachO/*.bin` are the four magics **as the bytes appear on disk**, which is not
the same as the four constants the design lists — `ripgrep-header-64.bin`, a real
brew-installed executable, starts `cf fa ed fe`, and that is `0xfeedfacf` read as
a little-endian `UInt32`. A predicate that compares the first four bytes to
`0xfeedfacf` in the wrong byte order matches nothing on this machine.
`manpage-header-64.txt` and `shell-script.sh` are the out-of-scope shapes.
