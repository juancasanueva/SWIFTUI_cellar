# Delta for package-search

Existing capability — `openspec/specs/package-search/spec.md` (6 requirements / 16 scenarios).

Delta summary: 1 ADDED requirement / 3 scenarios. Nothing is MODIFIED, REMOVED or RENAMED. In
particular "Measured as-you-type latency ceiling" keeps its text and both of its scenarios verbatim,
including "Index build is a single pass over the snapshot" — moving the build off the main actor
must not become a licence to build it more slowly or in more than one pass. The requirement below
constrains *where* the build runs; it takes nothing away from *how fast* it must be.

## ADDED Requirements

### Requirement: Index construction never runs on the main actor

Building the search index over a snapshot MUST run off the main actor, so the main actor stays
responsive while a snapshot of realistic size (approximately 15,500–16,000 records) is indexed. The
built index MUST be indistinguishable from one built on the caller's executor: the same records,
the same normalisation, the same ranking order, and the same query results. Moving the build off
the main actor MUST NOT relax the existing single-pass build requirement, and MUST NOT relax the
p95 8 ms query ceiling, which continues to be measured over a built index and to exclude build
time.

#### Scenario: The main actor stays responsive during an index build

- GIVEN a snapshot of approximately 15,500 records
- WHEN the index for that snapshot is built
- THEN other main-actor work submitted after the build starts runs to completion before the build
  finishes
- AND the main actor is never blocked for the duration of the build

#### Scenario: An off-main build answers identically

- GIVEN the same fixture used by the ranking and filter requirements
- WHEN the index is built off the main actor and the documented queries run against it
- THEN the results and their order are identical to the documented ranking, filter and
  empty-query outcomes

#### Scenario: The latency ceiling and single-pass build still hold

- GIVEN an index built off the main actor from a fixture of approximately 15,500 records
- WHEN at least 100 representative as-you-type queries of varying length are executed
- THEN the 95th-percentile query duration is below 8 milliseconds
- AND each record was normalised exactly once while the index was built
