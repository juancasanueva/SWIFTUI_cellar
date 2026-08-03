# Delta for catalog-sync

Existing capability — `openspec/specs/catalog-sync/spec.md` (13 requirements / 39 scenarios).

Delta summary: **1 MODIFIED requirement — 4 scenarios (3 carried forward unchanged, 1 added)**. The
MODIFIED requirement is reproduced in full so the archive step loses nothing. Nothing is ADDED,
REMOVED or RENAMED.

The requirement already rules the catalog "MUST end up serving the newer snapshot" but never defines
**newer**, so it is decided by the order adoption was *called* and an older snapshot entering after a
newer one has installed wins. Settled: "newer" is the snapshot's revision ordinal (materialization
order, already monotonic), not a fetched-at timestamp — no new state. The added scenario is the RED
anchor; the three existing ones pass against today's behaviour.

## MODIFIED Requirements

### Requirement: A snapshot is adopted exactly once, in order

The catalog MUST adopt each snapshot at most once, however many ingresses deliver it — cache load,
manual refresh, and the sync event stream. A manual refresh keeps its existing contract: it runs a
sync regardless of catalog age and returns once the resulting snapshot is queryable. When two
adoptions overlap, the catalog MUST end up serving the newer snapshot; an adoption of an older
snapshot that completes later MUST be discarded rather than installed. Cached results MUST remain
queryable for the whole duration of an adoption.

"Newer" MUST be determined by the snapshot's own revision — the order snapshots were materialized —
and MUST NOT be determined by the order in which adoption was called. An older snapshot whose
adoption is called after a newer snapshot has already been installed MUST therefore be discarded on
exactly the same terms as one whose adoption merely finishes late. The record of which revision has
been adopted MUST NOT regress to an older revision, so a snapshot that was discarded MUST NOT
disarm the deduplication of the newer one that is being served.
(Previously: the requirement ordered adoptions but left "newer" undefined, so it was decided by the
order adoption was called; an older snapshot entering after a newer one had installed could replace
it and could overwrite the adopted-revision record.)

#### Scenario: A manual refresh adopts its snapshot once

- GIVEN a running catalog that is also observing the sync event stream
- WHEN a manual refresh completes a sync that produces snapshot `S`
- THEN the search index is built exactly once for `S`
- AND the served record count and results are `S`'s

#### Scenario: A late adoption of an older snapshot is discarded

- GIVEN the adoption of snapshot `A` is still in progress when newer snapshot `B` is delivered
- WHEN `B` finishes adopting first and `A`'s adoption completes afterwards
- THEN the catalog still serves `B`
- AND the served record count and results are `B`'s, not `A`'s

#### Scenario: An older snapshot arriving after a newer one has installed is discarded

- GIVEN a catalog already serving snapshot `B`, whose revision is newer than snapshot `A`'s
- WHEN adoption is called for `A` only after `B` has been fully installed
- THEN the catalog still serves `B`'s record count and results, and `A` is never installed
- AND the adopted-revision record still names `B`'s revision, so a re-delivery of `B` is still
  deduplicated

#### Scenario: Results never blank while a snapshot is adopted

- GIVEN a catalog serving 15,000 cached records
- WHEN a new snapshot is adopted
- THEN every query issued while that adoption is in progress returns the previous results
- AND no query observes an empty result set caused by the swap
