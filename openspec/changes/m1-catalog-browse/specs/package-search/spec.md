# Delta for package-search

New capability — no existing spec. All requirements are ADDED.

Scope: the in-memory query contract over a persisted catalog snapshot — identity, normalisation,
ranking order, filters, and the measured latency ceiling.

## ADDED Requirements

### Requirement: Index identity is (kind, name)

Every indexed record MUST be identified by the pair `(kind, name)` where `kind` is `formula` or
`cask`, and MUST expose its `kind` on every result. A name that exists in both namespaces MUST
produce two distinct results, and a lookup by name alone without a kind MUST NOT be able to resolve
ambiguously to one of them silently.

#### Scenario: Same name in both namespaces yields two results

- GIVEN a snapshot containing formula `docker` and cask `docker`
- WHEN the query `docker` runs
- THEN two distinct results are returned, one with kind `formula` and one with kind `cask`

#### Scenario: Kind is exposed on every result

- GIVEN any non-empty result set
- WHEN each result is inspected
- THEN each carries exactly one of `formula` or `cask`

### Requirement: Matching runs over pre-normalised ASCII-folded text

Searchable text (name and description) MUST be normalised once at index build to case-folded,
ASCII-folded form, and queries MUST be normalised the same way before matching. Matching MUST be
performed against the pre-normalised text, so a query differing from the stored text only in case or
diacritics MUST match.

#### Scenario: Case-insensitive match

- GIVEN a record named `gh`
- WHEN the query `GH` runs
- THEN the record matches

#### Scenario: Diacritics fold to ASCII

- GIVEN a record whose description contains `café`
- WHEN the query `cafe` runs
- THEN the record matches
- AND the query `café` matches the same record

### Requirement: Deterministic ranking order

Results MUST be ordered by match class, strongest first: (1) exact name/token match, (2) name/token
prefix match, (3) name substring match, (4) description substring match. A record MUST be ranked by
its strongest match class only. Within a class, results MUST be ordered by 365-day install count
descending; an absent count MUST sort after every present count. Remaining ties MUST be broken by
normalised name ascending, then `formula` before `cask`, so the order is total and reproducible.

#### Scenario: Match classes order the result set

- GIVEN records `wget` (exact), `wget2` (prefix), `libwget` (name substring), and `curl` whose
  description contains `wget`
- WHEN the query `wget` runs
- THEN the order is `wget`, `wget2`, `libwget`, `curl`

#### Scenario: Install count breaks a class tie

- GIVEN prefix matches `node` with count 900,000 and `nodenv` with count 12,000
- WHEN the query `node` runs
- THEN `node` precedes `nodenv`

#### Scenario: Absent counts sort last within a class

- GIVEN two prefix matches, one with count 5 and one with an absent count
- WHEN the query runs
- THEN the record with count 5 precedes the record with the absent count

#### Scenario: Full ties are broken deterministically

- GIVEN two prefix matches with equal counts and names `alpha` (cask) and `alpha` (formula)
- WHEN the query runs twice
- THEN the formula precedes the cask in both runs

### Requirement: Filters answerable from the catalog alone

The query MUST accept filters for `kind` (formula, cask, or both), `excludeDeprecated`, and
`excludeDisabled`. Deprecated and disabled packages MUST be included by default and MUST expose
their deprecation and disabled flags so a consumer can badge them. No filter MUST depend on
installed, not-installed, or outdated state — the persisted catalog cannot answer those.

#### Scenario: Deprecated packages are included by default with badge data

- GIVEN a snapshot containing a deprecated formula matching the query
- WHEN the query runs with default filters
- THEN the deprecated formula is present in the results and its deprecation flag is true

#### Scenario: Deprecated packages can be filtered out

- GIVEN the same snapshot
- WHEN the query runs with `excludeDeprecated`
- THEN the deprecated formula is absent and non-deprecated matches remain

#### Scenario: Kind filter restricts the namespace

- GIVEN a snapshot containing formula `docker` and cask `docker`
- WHEN the query `docker` runs restricted to `cask`
- THEN exactly one result is returned and its kind is `cask`

#### Scenario: No filter references installed state

- GIVEN the declared filter set
- WHEN it is enumerated
- THEN it contains no installed, not-installed, or outdated predicate

### Requirement: Empty and non-matching queries are ordinary results

An empty or whitespace-only query MUST return the whole filtered catalog in the default order
(install count descending, then the documented tiebreak), not an error and not zero results. A query
that matches nothing MUST return an empty result set rather than throwing.

#### Scenario: Empty query returns the full catalog

- GIVEN a snapshot of 15,000 records
- WHEN the query is the empty string
- THEN 15,000 results are returned, ordered by install count descending

#### Scenario: No match returns an empty set

- GIVEN a snapshot with no record matching `zzzzznotapackage`
- WHEN that query runs
- THEN zero results are returned and nothing is thrown

### Requirement: Measured as-you-type latency ceiling

Query latency MUST hold p95 below 8 milliseconds over a fixture of realistic size (approximately
15,500 records with real names and descriptions), measured over a built index and excluding index
build time. This ceiling is a requirement with an automated assertion, not an aspiration.

#### Scenario: p95 stays under 8 ms on a realistic fixture

- GIVEN an index built from a fixture of approximately 15,500 records
- WHEN at least 100 representative as-you-type queries of varying length are executed
- THEN the 95th-percentile query duration is below 8 milliseconds

#### Scenario: Index build is a single pass over the snapshot

- GIVEN a snapshot of approximately 15,500 records
- WHEN the index is built
- THEN each record is normalised exactly once and the built index answers queries
