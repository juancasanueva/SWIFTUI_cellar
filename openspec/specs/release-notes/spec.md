# release-notes

This capability owns what Cellar may learn, and may transmit, to answer "what changes if I upgrade
this package": how a GitHub repository is derived from catalog URLs, when a request is permitted to
leave this Mac, what a request may cost, the four typed answers it can produce, how those answers
are cached, where the optional token lives, and what a release body is allowed to do when rendered.
Every requirement is behaviour of `CellarCore` values; no SwiftUI view is specified anywhere in this
file. Where the text says "an opened release-notes request", it means one explicit user action
naming one package at one version — the presentation that carries the action is not specified here.

**Design alignment** (`design.md`, Engram obs 7507 — authoritative where it is more specific than
this file): the outcome set is **five** top-level typed outcomes, not four collapsed ones, with the
rate-limit refusal structurally separate from every absence; tag matching normalizes Homebrew's
version suffixes before comparing; and the single request fetches the releases **list**, because the
per-tag endpoint answers `404` for two different absences and cannot tell them apart. Nothing in
D1–D6 moved.

## Requirements

### Requirement: Resolution is a union of the published URLs, never a guess

A package's GitHub repository MUST be derived from the **union** of four catalog-published values:
`homepage`, `formulaSources.stableURL`, `formulaSources.headURL`, and `caskInspection.downloadURL`.
A repository MUST be reported when **any** of the four yields one; a value that yields nothing MUST
NOT prevent another from resolving. Where more than one yields a repository, `homepage → headURL →
stableURL → caskInspection.downloadURL` MUST be applied as a **tie-break order only** — it MUST NOT
be applied as a precedence that stops evaluation before the remaining fields are considered.

A repository MUST be reported only for a `github.com` URL naming a repository path. Host comparison
MUST be case-insensitive and MUST tolerate a `www.` prefix; a trailing `.git`, a trailing slash, a
query string, a fragment, and any path segments beyond `owner/repo` MUST be discarded rather than
made part of the identity. `gist.github.com`, `raw.githubusercontent.com`, `*.github.io`,
`gitlab.com`, `codeberg.org` and every other host MUST NOT resolve. Owner or repository segments
that are empty, or that are GitHub's own reserved non-repository paths, MUST NOT resolve.

A resolved repository MUST carry the **provenance** of the field that produced it, so the claim is
inspectable rather than assumed. A package that no field resolves MUST report a typed unresolvable
value — never an empty string, an optional treated as failure, or a thrown error. Resolution MUST be
a pure function of the values it is given: it MUST NOT issue a network request, MUST NOT spawn a
`brew` process, MUST NOT consult the cache, and MUST NOT perform any search, name-similarity or
vendor-guessing step.

#### Scenario: A package resolvable only via `urls.stable` still resolves

- GIVEN a formula whose `homepage` is `https://gnu.org/software/foo` and whose `formulaSources`
  carries only `stableURL` = `https://github.com/acme/foo/archive/refs/tags/v1.2.0.tar.gz`
- WHEN its repository is resolved
- THEN it resolves to `acme/foo`
- AND the result names `stableURL` as the field that produced it

#### Scenario: The tie-break decides only which field is credited

- GIVEN a package where all four fields yield `acme/foo`
- WHEN its repository is resolved
- THEN it resolves to `acme/foo` with `homepage` credited as the producing field
- AND removing `homepage` alone still resolves to `acme/foo`, credited to `headURL`

#### Scenario: A cask resolves from its download URL

- GIVEN a cask whose `homepage` is `https://example.com` and whose `caskInspection.downloadURL` is
  `https://github.com/acme/tool/releases/download/v3.0/tool.dmg`
- WHEN its repository is resolved
- THEN it resolves to `acme/tool`, credited to the cask download URL

#### Scenario: Non-repository and non-GitHub hosts never resolve

- GIVEN packages whose only candidate URLs are, respectively, a `gist.github.com` URL, a
  `raw.githubusercontent.com` URL, a `*.github.io` pages URL, a `gitlab.com` URL and a
  `codeberg.org` URL
- WHEN each is resolved
- THEN every one reports the typed unresolvable value
- AND no partial `owner/repo` is reported for any of them

#### Scenario: Ornamented URLs normalize to one identity

- GIVEN the URLs `https://www.github.com/Acme/Foo.git`, `https://github.com/Acme/Foo/`, and
  `https://github.com/Acme/Foo/releases/tag/v1.0?utm=x#top`
- WHEN each is resolved
- THEN all three produce the same repository identity
- AND no reported repository name retains `.git`, a trailing slash, a query or a fragment

#### Scenario: Unresolvable is a typed answer, and costs nothing

- GIVEN a package whose four candidate values are all absent or non-GitHub, and a recording network
  seam
- WHEN its repository is resolved
- THEN it reports the typed unresolvable value and nothing is thrown
- AND the settled outcome is the no-repository-resolved case, naming the candidate sources tried,
  distinct from "the repository publishes no releases"
- AND the recorder saw no request

### Requirement: Nothing leaves this Mac before a dated release-notes grant

Release notes MUST carry their **own** consent value, distinct from the security-scan grant. It MUST
be constructible in a consenting state only by supplying a date, so a grant always knows when it was
given; revocation MUST return the value to the same state as never-granted, leaving no residue that
could later be read as a lapsed grant. The authorisation check MUST be a throwing refusal rather
than a boolean, so a missing grant surfaces as a typed, showable refusal and never as a silent
no-op, an empty result, or a pending state that never settles.

No release-notes request MUST be issued before that grant exists. A grant for security scanning MUST
NOT authorise a release-notes request, and a release-notes grant MUST NOT authorise any other
egress. The disclosure accompanying the grant MUST be supplied by `CellarCore`, MUST name the host
(`api.github.com`), MUST state that a repository name — which reveals that this Mac has that package
installed and is about to upgrade it — is what leaves the machine, and MUST NOT claim that nothing
identifying is transmitted.

These rules are the same rules the security-scan grant obeys. `ReleaseNotes` re-declares the consent
and credential seams because the target depends on `Catalog` only; that is one mechanism applied
twice under a distinct service name, and it MUST NOT introduce a second set of rules.

#### Scenario: Without a grant, nothing is transmitted and the refusal is typed

- GIVEN no release-notes grant recorded and a recording network seam
- WHEN release notes are requested for a package with a resolvable repository
- THEN the request is refused with the typed pending-consent refusal
- AND the recorder saw no request at all

#### Scenario: The security-scan grant does not authorise release notes

- GIVEN a granted security-scan consent and no release-notes grant
- WHEN release notes are requested
- THEN the request is refused with the typed pending-consent refusal and no request is issued

#### Scenario: The disclosure names the host and what is revealed

- GIVEN the disclosure text this capability supplies
- WHEN it is inspected
- THEN it names `api.github.com` and states that a repository name is transmitted
- AND it contains no claim that the request is anonymous or that nothing about this Mac is revealed

#### Scenario: Revocation leaves no residue

- GIVEN a release-notes grant dated in the past and a recording network seam
- WHEN the grant is revoked and release notes are requested
- THEN the value equals the never-granted value, including its absent date
- AND the request is refused and the recorder saw no request

### Requirement: One request per opened release-notes request, and bulk work issues none

An opened release-notes request MUST cause **at most one** GitHub request. Release-notes work MUST
be started only by an explicit request naming one package; it MUST NOT be started by a bulk
operation, a scheduled task, a background refresh, a prefetch, or as a side effect of inventory,
catalog sync, or any package mutation. A rate-limited or failed outcome MUST NOT trigger an
automatic retry.

That one request MUST fetch the repository's published releases as a **list**, bounded by a page
size, and every outcome MUST be derived from that single response. Specifically, "the repository
publishes no releases" and "no release matches this version" MUST be distinguished from one response
— an empty list versus a non-empty list carrying no matching tag — and MUST NOT be distinguished by
issuing a second request, nor conflated by an endpoint that answers identically for both. A page
that filled its bound without yielding a match MUST NOT silently become a claim that no such release
exists; it MUST be reported with the qualifier required by "Four absences are four values, and a
rate-limit refusal is none of them".

Acquisition MUST use an ephemeral session configuration with no shared `URLCache` and no cookie
storage, MUST send a conditional request when a validator is held, MUST enforce a response byte
limit, and MUST NOT carry credentials other than the optional token this capability stores. A
release body, once obtained, MUST NOT cause any further acquisition: no remote image or asset
referenced by the body may be fetched, and no link within it may be followed automatically.

#### Scenario: A bulk upgrade issues zero GitHub requests

- GIVEN a granted release-notes consent, a recording network seam, and 30 outdated packages
- WHEN all 30 are upgraded in one bulk operation
- THEN the recorder saw zero GitHub requests

#### Scenario: One opened request costs one request

- GIVEN a granted consent, an empty cache and a recording network seam
- WHEN release notes are requested once for one package at one version
- THEN the recorder saw exactly one request

#### Scenario: A release body cannot cause a second egress

- GIVEN a matched release body containing a remote image reference and several links
- WHEN it is prepared for display
- THEN the recorder still shows exactly one request
- AND no request naming the image host or any linked host was issued

#### Scenario: Acquisition carries no ambient state

- GIVEN the session configuration this capability uses
- WHEN it is inspected
- THEN its cache is absent, its cookie storage is absent, and its response byte limit is set
- AND a request issued with a held validator carries the conditional-request header

### Requirement: Four absences are four values, and a rate-limit refusal is none of them

A release-notes result MUST be exactly one of **five** top-level typed outcomes:

| Outcome | Carries |
|---|---|
| A **matched release** | the resolved repository and that release, including its body |
| **No repository could be resolved** | which candidate sources were tried |
| **The repository publishes no releases** | the resolved repository |
| **No release matches this version** | the resolved repository, the version, how many releases were inspected, and whether the inspected page filled its bound |
| **The fetch is unavailable** | a typed failure reason |

None of the four non-matched outcomes MUST be represented as an empty body, an empty string, a
`nil`, or a never-settling pending state; each MUST be distinguishable by a consumer without
inspecting free text; and the unavailable outcome MUST NOT be collapsed into any of the three
absences, nor any absence into another.

A `403` or `429` carrying an exhausted rate-limit budget MUST be reported as the unavailable outcome
with its **own** typed rate-limit reason, carrying the reset time and the published budget when
present. It MUST NOT be reported as "no releases", "no matching release" or "no repository", MUST
NOT be reported as a plain HTTP-status failure or a transport failure, and MUST NOT be written to
the cache as an answer. Every other failure reason — refusal pending consent, a rejected credential,
another non-success status, transport, byte-limit, malformed payload, cancellation — MUST be
distinguishable from the rate-limit reason and from each other.

#### Scenario: An empty releases list is its own state

- GIVEN a resolved repository whose releases response is an empty list
- WHEN the result settles
- THEN it reports "the repository publishes no releases"
- AND it does not report an unavailable outcome, a matched release, or a no-matching-version state

#### Scenario: Releases exist but none matches the version

- GIVEN a resolved repository publishing releases for `v1.0.0` and `v1.1.0`, and an installed
  version of `2.44.0`
- WHEN the result settles
- THEN it reports "no release matches this version", carrying the count of releases inspected
- AND no nearest, latest or approximate release is returned in its place

#### Scenario: A version past the page bound is a qualified miss, never "no releases"

- GIVEN a repository whose fetched page filled its bound with releases all newer than the installed
  version, so the matching release is not among them
- WHEN the result settles
- THEN it reports "no release matches this version" with the page-was-full qualifier set, so the
  claim reads as "not among the most recent releases fetched" rather than as an absolute absence
- AND it does not report "the repository publishes no releases"
- AND no second request was issued to look further back

#### Scenario: A rate-limit refusal is distinct and carries its reset time

- GIVEN a response of `403` with an exhausted rate-limit budget and a reset time
- WHEN the result settles
- THEN it reports the unavailable outcome with the typed rate-limit reason and that reset time
- AND it does not report any of the three absence outcomes
- AND no automatic retry was issued

#### Scenario: A rejected token is not a rate limit

- GIVEN a stored token the host rejects, and a response of `401`
- WHEN the result settles
- THEN it reports the unavailable outcome with the rejected-credential reason
- AND that reason is distinct from the rate-limit reason, so no reset time or budget is claimed

#### Scenario: A transport failure is not a rate-limit refusal

- GIVEN a request that fails at the transport layer
- WHEN the result settles
- THEN it reports the unavailable outcome with a reason distinct from the rate-limit reason
- AND no outcome claims the repository publishes no releases

### Requirement: Tag matching is deterministic, and a miss is an answer

A Homebrew version string is not an upstream tag, so matching MUST first **normalize** the version:
a formula's revision suffix (`2.43.0_1` → `2.43.0`) and a cask's build suffix (`1.2.3,456` →
`1.2.3`) MUST be stripped before any comparison. A version carrying such a suffix MUST NOT be
allowed to miss a release the upstream project did publish.

The normalized version MUST then be matched against the repository's published release tags by a
deterministic rule set covering **at minimum** an exact tag and a tag differing only by a leading
`v`; comparison MUST be case-insensitive. The rule set MAY cover further published tag shapes — the
full candidate table is a design concern — but it MUST NOT fall back to the newest release, a
substring hit, or a nearest-version guess when no tag satisfies it. Matching MUST be a pure function
of the version, the package name and the published tags, reproducible without a network. When
exactly one release satisfies the rule set it MUST be returned; when none does, the result MUST be
"no release matches this version".

#### Scenario: A `v`-prefixed tag matches an unprefixed version

- GIVEN a repository publishing a release tagged `v2.44.0` and a version of `2.44.0`
- WHEN matching runs
- THEN that release is returned

#### Scenario: An exact tag matches

- GIVEN a repository publishing a release tagged `2.44.0` and a version of `2.44.0`
- WHEN matching runs
- THEN that release is returned

#### Scenario: A formula revision suffix is stripped before matching

- GIVEN a repository publishing a release tagged `v2.43.0` and an installed formula version of
  `2.43.0_1`
- WHEN matching runs
- THEN that release is returned
- AND the revision suffix did not cause a "no release matches this version" result

#### Scenario: A cask build suffix is stripped before matching

- GIVEN a repository publishing a release tagged `1.2.3` and an installed cask version of
  `1.2.3,456`
- WHEN matching runs
- THEN that release is returned
- AND the build suffix did not cause a "no release matches this version" result

#### Scenario: A near miss is a miss, not the newest release

- GIVEN a repository publishing releases tagged `v2.44.1` and `v2.45.0`, and a version of `2.44.0`
- WHEN matching runs
- THEN the result is "no release matches this version"
- AND neither published release is returned

### Requirement: A two-tier TTL cache, keyed by repository and version

Results MUST be cached in this capability's own store, keyed by `(repository, version)`. A **matched
release body** MUST remain valid for **7 days**; every **negative** answer — unresolvable, no
releases, no matching release — MUST remain valid for **24 hours**. A refused-or-failed outcome
carrying the rate-limit reason MUST NOT be cached as an answer at all. A cached entry within its TTL
MUST be served without issuing a request; a cached entry past its TTL MUST NOT be served as fresh.

The store MUST be schema-version gated: a missing file, an unreadable or corrupt file, and a file
whose recorded schema version does not match MUST all mean "cached nothing", MUST NOT throw, and
MUST NOT be partially adopted. The store MUST bound its entry count. It MUST NOT read or write the
catalog snapshot, MUST NOT invalidate any catalog cache, and MUST NOT move any catalog schema
version.

#### Scenario: A matched body inside 7 days costs no request

- GIVEN a matched body cached 6 days ago and a recording network seam
- WHEN release notes are requested for the same `(repository, version)`
- THEN the cached body is returned and the recorder saw no request

#### Scenario: A matched body past 7 days is re-asked

- GIVEN a matched body cached 8 days ago
- WHEN release notes are requested for the same `(repository, version)`
- THEN a request is issued rather than the stale entry being served

#### Scenario: A negative answer expires after 24 hours

- GIVEN a "no matching release" answer cached 25 hours ago
- WHEN release notes are requested for the same `(repository, version)`
- THEN a request is issued
- AND the same answer cached 23 hours ago would have been served without a request

#### Scenario: A rate-limit refusal is never cached

- GIVEN an empty cache and a response of `403` with an exhausted rate limit
- WHEN the result settles and the store is read back
- THEN the store holds no entry for that `(repository, version)`

#### Scenario: A corrupt or mismatched store means cached nothing

- GIVEN a store file that is, in turn, absent, byte-corrupt, and carrying a different schema version
- WHEN it is loaded in each case
- THEN each load yields no entries, nothing is thrown, and no partial entry set is adopted
- AND the catalog snapshot on disk is unchanged in every case

### Requirement: The token is a Keychain secret, and it is optional

An optional GitHub personal access token MUST be stored only through a Keychain-backed seam, as a
generic-password item under a service name **distinct** from the security-scan credential's, with
after-first-unlock accessibility and synchronisation explicitly disabled. It MUST NOT be written to
`UserDefaults`, `@AppStorage`, a preferences plist, a cache file, a log, or any diagnostic output,
and a stored token MUST NOT be readable back into any display or echo path. The store MUST offer
removal.

When a token is present, requests MUST be authenticated with it. When no token is present, requests
MUST still be issued unauthenticated — the absence of a token MUST NOT be an error, MUST NOT block
the request, and MUST NOT degrade an answer into a guess; it degrades only the available request
budget.

#### Scenario: A stored token authenticates the request

- GIVEN a token stored through the seam and a granted consent
- WHEN a release-notes request is issued
- THEN the request carries the authorization header derived from that token

#### Scenario: No token is not an error

- GIVEN no token stored and a granted consent
- WHEN a release-notes request is issued
- THEN the request is issued unauthenticated and the result settles normally
- AND no failure outcome names the missing token

#### Scenario: The token has exactly one home

- GIVEN the `ReleaseNotes` target's sources and the store's query dictionary
- WHEN they are inspected structurally
- THEN the target references no `UserDefaults` and no `@AppStorage`
- AND the query declares a generic password, a service name different from the security-scan
  credential's, after-first-unlock accessibility, and synchronisation disabled

#### Scenario: A stored token is removable and never echoed

- GIVEN a stored token
- WHEN it is removed and the store is read back, and when any log or diagnostic output produced
  during a request is inspected
- THEN the read-back yields no token and nothing is thrown
- AND no inspected output contains the token's characters

### Requirement: A release body renders without failure, and unsupported constructs degrade to text

A matched release body MUST be presentable without failing on any input a GitHub release can carry.
Markdown constructs the platform renderer does not support — including GFM tables, task lists and
`@`-mentions — MUST degrade to readable text rather than being dropped, throwing, or producing a
failure outcome. A body that cannot be parsed as Markdown at all MUST still be presentable as plain
text. Preparation MUST NOT change the outcome: a body that degrades still reports a matched release.

A matched release whose body is empty MUST report a matched release with an explicitly empty body,
distinct from "no release matches this version" and from "the repository publishes no releases".

#### Scenario: Unsupported GFM constructs survive as text

- GIVEN a release body containing a GFM table, a task list and an `@`-mention
- WHEN it is prepared for display
- THEN preparation does not throw and the outcome is still a matched release
- AND the table's and task list's textual content is present in the prepared value

#### Scenario: An unparseable body is still readable

- GIVEN a release body of malformed Markdown, and one at the byte limit
- WHEN each is prepared for display
- THEN each yields a presentable value and neither throws

#### Scenario: An empty body is a matched release, not an absence

- GIVEN a release matching the version whose body is an empty string
- WHEN the result settles
- THEN it reports a matched release carrying an explicitly empty body
- AND it does not report either absence state

### Requirement: Release notes cost no brew process and no catalog change

No part of this capability MUST spawn a `brew` process — resolution, fetching, matching, caching and
rendering are all derived from catalog values, network responses and this capability's own store.
This capability MUST NOT add a field to `CatalogPackage` or `CatalogSnapshot` and MUST NOT move the
catalog schema version.

#### Scenario: The whole flow spawns no brew process

- GIVEN a recording process seam, a granted consent and a fixture-backed network seam
- WHEN a package is resolved, fetched, matched, cached and read back from cache
- THEN the recorder saw no process spawned

#### Scenario: The catalog footprint is unchanged

- GIVEN the shipped catalog types and their footprint assertion
- WHEN the suite runs with this capability present
- THEN the footprint assertion passes unchanged
- AND `CatalogPackage` carries no field this capability introduced

## Provenance

- Established by change `m5-release-notes` (archived `2026-08-07`, PRD milestone **M5** "Pro-parity
  flows", slice 3 of 5 — pre-upgrade release notes), ADDED-only delta — **9 requirements / 39
  scenarios**, promoted from
  `openspec/changes/archive/2026-08-07-m5-release-notes/specs/release-notes/spec.md`. This is the
  first main spec for the capability; nothing was modified, removed or renamed, and the change
  touched no other main spec. This file adds the header, the `## Requirements` wrapper and this
  provenance section — the requirement and scenario bodies are byte-identical to the delta's.
- **The design-alignment paragraph above is carried verbatim from the delta.** The `design.md` it
  cites is archived at `openspec/changes/archive/2026-08-07-m5-release-notes/design.md` (Engram
  `#7507`) and stays authoritative wherever it is more specific than this file — most importantly
  the five-outcome set standing behind the requirement titled "Four absences are four values", whose
  name counts the absences and not the rate-limit refusal that is deliberately none of them.
- Traceability to the change's binding decisions (proposal Engram `#7504`, D1–D6 user-approved). Each
  names what was rejected, so a later change cannot reintroduce a rejected alternative as a fresh
  idea:
  - **D1** → "Nothing leaves this Mac before a dated release-notes grant". Release notes get their
    own dated grant in M4's disclosure vocabulary: a different host (`api.github.com`), different
    disclosed data (a repository name reveals this Mac has that package and is about to upgrade it),
    and different timing. **Rejected:** reusing the security-scan grant, which would silently hand a
    CVE-scanning consenter a second egress destination — exactly what dating a grant prevents — and
    no consent at all.
  - **D2** → the same requirement's distinct-service and distinct-grant clauses. `ReleaseNotes`
    re-declares the consent and credential seams instead of importing `SecurityKit`: one mechanism
    applied twice under a distinct Keychain service name, never a second set of rules.
    **Rejected:** a `ReleaseNotes → SecurityKit` edge, which would couple release notes to the CVE
    scanner for two value types, and a shared consent/credentials micro-target, which would dissolve
    the property that each secret has exactly one way to be read.
  - **D3** → "A two-tier TTL cache, keyed by repository and version". A matched body is valid 7 days
    and every negative answer 24 hours, while no unavailable outcome is cached at all.
    **Rejected:** one uniform TTL, and caching negatives indefinitely — a cached rate-limit refusal
    would outlive the window it describes.
  - **D4** (entry points: the outdated row's "What's new?" sitting *beside* `MutationMenu` rather
    than inside it, plus a package-detail section when a repository resolves) is an app-side
    decision with no `CellarCore` behaviour, so it is carried by the change's `tasks.md` and
    deliberately **not** by a requirement here. Recorded so a later reader does not read its absence
    as a gap. **Rejected:** fetching when a detail view appears, and an outdated-row-only entry.
  - **D5** → "The token is a Keychain secret, and it is optional". The optional GitHub PAT field
    ships in this slice inside the release-notes consent surface rather than waiting for the M6
    Settings screen, following M4's precedent of shipping the NVD key inside `SecurityConsentSheet`.
    **Rejected:** building and testing a Keychain store with no way to fill it, which would leave a
    user who hits the 60 req/h wall without an exit for a whole milestone.
  - **D6** → "Resolution is a union of the published URLs, never a guess" — the union rule, the
    `homepage → head → stable → cask url` tie-break, and resolvability being answerable without
    egress so an entry point can be gated on it. **Rejected:** GitHub search or name-similarity
    fallback, and naive homepage-first precedence — probe U5 (Engram `#7503`) measured `homepage`
    as the weakest field everywhere (24.5% of installed formulae, 9.1% of casks) against
    `urls.stable`'s 54.7%, with the union reaching 81.4% of explicitly-installed formulae and zero
    fields disagreeing on owner/repo.
- **"One request per opened request" is the spine of this capability, not a performance note.** The
  60 req/h unauthenticated budget is a product constraint rather than a tuning knob: a bulk upgrade
  of N packages issues zero release-notes requests, and that is asserted by a recording transport,
  never assumed. The single request fetches the releases *list* precisely so that "publishes no
  releases" and "no release matches this version" can be told apart from one response — the per-tag
  endpoint answers `404` for both and cannot distinguish them.
- **A rate-limit refusal is not an absence.** The four absence states and the one unavailable
  outcome are five distinct values by construction, so a refusal can never reach a user disguised as
  "this package has no release notes".
- **The capability owns no catalog state.** It adds no field to `CatalogPackage` or
  `CatalogSnapshot`, moves no catalog schema version, and spawns no `brew` process; its TTL cache is
  its own file under its own schema version. `CatalogFootprintTests` passes unchanged.
- The archived delta spec is the verbatim audit trail.
