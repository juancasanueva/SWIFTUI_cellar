# Delta for catalog-sync

Existing capability — `openspec/specs/catalog-sync/spec.md` (13 requirements / 40 scenarios).

Delta summary: **2 MODIFIED requirements** (reproduced in full so the archive step loses nothing) and
**1 ADDED requirement**. Nothing is REMOVED or RENAMED.

- *Tolerant decoding of the published payload shapes* — 10 scenarios (5 carried forward byte-identical,
  5 added) — gains the five widened cask keys, the two widened formula keys, and the rule that an
  artifact stanza the projection cannot represent is **counted**, never dropped and never fatal.
- *Slim persisted projection with a state sidecar* — 6 scenarios (2 carried forward byte-identical,
  4 added) — gains the `schemaVersion` 1 → 2 transition rule applied to **both** persisted files in
  both directions, and a measured footprint bound with the fields that survive any narrowing.
- **ADDED** *Inspection data costs no new acquisition* — 2 scenarios — the promise that outranks
  stanza coverage (D5): no new brew invocation, no new remote resource, no per-package request.

Traceability: **D1** → "Slim persisted projection with a state sidecar"; **D2** → "Tolerant decoding"
(counted remainder at decode) and `package-detail` (its projected shape); **D3** → `conflicts_with`
in the widened key list; **D5** → the footprint bound and its retained-field floor.

**D5 was triggered by probe U4.** The representable stanza set narrows to `app`, `binary` and `pkg`;
`zap`, `uninstall`, `font` and every unmodelled kind are counted, never projected (`target` is not a
stanza kind — it is a companion key attached to the stanza it modifies, so it is neither projected
nor counted). The
requirement text below is deliberately kind-agnostic — it rules that a representable stanza decodes
into its kind and every other stanza is counted — so the narrowing changes which kinds are
representable without changing this capability's decoding contract. The projected set itself is
specified in the `package-detail` delta.

Fixture note: `Tests/CatalogTests/Fixtures/cask-iterm2.json` already publishes `url`, `sha256`,
`depends_on`, `conflicts_with` and an `artifacts` list — but only `app` and `zap.trash` stanzas. No
fixture exercises `binary` or `pkg`, a stanza of an unrepresented kind (`uninstall` and `zap` are now
two such kinds), a cask publishing only unrepresented stanzas, or a `depends_on` form other than
`macos`. The scenarios below name those shapes so the gap is closed by a fixture rather than by an
assumption.

## MODIFIED Requirements

### Requirement: Tolerant decoding of the published payload shapes

Decoding MUST tolerate the shapes the published API actually emits: a cask `name` that is an array
of strings, a `null` `desc`, a `null` `caveats`, `uses_from_macos` elements that are either a string
or an object, and keys the decoder does not know. Unknown keys MUST be ignored rather than failing.
An individual record that cannot be decoded MUST be skipped without failing the sync, and the number
of skipped records MUST be recorded on the resulting snapshot.

Decoding MUST additionally read the cask keys `url`, `sha256`, `artifacts`, `depends_on` and
`conflicts_with`, and the formula keys `urls.stable` and `urls.head`. Each of these MUST be optional
in exactly the sense the already-decoded keys are: a record that omits the key, or publishes it as
`null`, MUST decode successfully with that value exposed as typed absence — never as an empty value
substituted for a missing one, and never as a decode failure. The widening MUST NOT change which
records decode: a payload that decoded before this change MUST yield the same record count and the
same skipped-record count afterwards.

`artifacts` MUST decode as a heterogeneous list. A stanza whose kind the projection represents MUST
decode into that kind. A stanza of any other kind — including a kind that did not exist when the
running build shipped — MUST be counted rather than dropped silently, and MUST NOT cause the record
to be skipped. A cask whose `artifacts` list contains no representable stanza at all MUST still
decode as a record, carrying its count of unrepresented stanzas.
(Previously: the tolerated shapes and the skipped-record count were identical, but decoding read
neither the five widened cask keys nor the two widened formula keys, so `artifacts` had no
representable/unrepresentable distinction and no counted remainder.)

#### Scenario: Cask name array yields a single display name

- GIVEN a cask record whose `name` is `["iTerm2"]`
- WHEN it is decoded
- THEN its display name is `iTerm2`

#### Scenario: Null description and caveats decode as absent

- GIVEN a record with `"desc": null` and `"caveats": null`
- WHEN it is decoded
- THEN its description and caveats are absent, distinct from empty strings

#### Scenario: Mixed uses_from_macos elements decode

- GIVEN a formula whose `uses_from_macos` is `["curl", {"llvm": ["build"]}]`
- WHEN it is decoded
- THEN both elements decode and the record is retained

#### Scenario: Unknown keys are ignored

- GIVEN a record carrying keys the decoder does not model
- WHEN it is decoded
- THEN it decodes successfully and the unknown keys are discarded

#### Scenario: One malformed record does not kill the payload

- GIVEN a payload of 100 records where 3 have a malformed shape
- WHEN it is decoded
- THEN the snapshot contains 97 records and reports 3 skipped records

#### Scenario: The five widened cask keys decode from a published record

- GIVEN a cask record publishing `url`, `sha256`, an `artifacts` list, `depends_on` and
  `conflicts_with`
- WHEN it is decoded
- THEN all five values are present on the decoded record and match the published payload

#### Scenario: A cask omitting every widened key still decodes

- GIVEN a cask record that publishes none of `url`, `sha256`, `artifacts`, `depends_on` or
  `conflicts_with`, and a second record publishing each of them as `null`
- WHEN both are decoded
- THEN both decode successfully, neither is counted as skipped, and each of the five values is absent
  rather than an empty string, an empty list or a zero

#### Scenario: Formula stable and head source URLs decode

- GIVEN a formula record whose `urls.stable` publishes a `url` and whose `urls.head` publishes a `url`
- WHEN it is decoded
- THEN both source URLs are present on the decoded record
- AND a formula publishing `urls.stable` but no `urls.head` decodes with the head URL absent

#### Scenario: An unrepresented artifact stanza is counted, not fatal

- GIVEN a cask whose `artifacts` list holds one `app` stanza and two stanzas of kinds the projection
  does not represent, and a second cask whose `artifacts` list holds only unrepresented stanzas
- WHEN both are decoded
- THEN the first decodes with its `app` stanza and a count of `2` unrepresented stanzas
- AND the second decodes as a record with no representable stanza and a count of `1` or more
- AND neither record is reported as skipped

#### Scenario: The widening does not change which records decode

- GIVEN the full published cask and formula payloads
- WHEN they are decoded by a build carrying the widened keys
- THEN the record count and the skipped-record count are the same values the previous build produced

### Requirement: Slim persisted projection with a state sidecar

A successful sync MUST persist a slim projection containing only the fields the search and detail
capabilities require, plus a state sidecar recording, per source, `schemaVersion`, the validators
(`etag` and/or `lastModified`), `downloadedAt`, and `recordCount`. A persisted file whose
`schemaVersion` does not match the one the running build expects MUST be treated as no cache — the
system MUST re-sync from scratch and MUST NOT fail or crash on it.

The version check MUST apply independently to **both** persisted files — the snapshot and the state
sidecar — so neither can be adopted on the strength of the other's version. The check MUST be exact
inequality in both directions: a version older than the running build's and a version newer than it
are the same answer, "no cache". Adding a field to the persisted projection MUST therefore be
accompanied by a `schemaVersion` increment, and reverting that increment MUST leave the newer file
classified as no cache rather than decoded with missing fields. Classification MUST NOT throw, MUST
NOT be reported through a failure status, and MUST NOT mutate or delete the file it rejected.

The persisted projection MUST stay within a recorded footprint bound, measured over a full-scale
catalog, covering the persisted snapshot's size on disk, the resident memory of a loaded snapshot,
and the time to load it. That bound MUST be asserted by an automated test rather than stated as a
comment, so a later widening that breaks it fails a test instead of a user's machine. If the
measurement shows the bound cannot be held with the full projection, the projection MUST be narrowed;
under any such narrowing the cask `url`, `sha256`, `depends_on` and `conflicts_with` values MUST be
retained.
(Previously: the requirement mandated the slim projection and the sidecar's `schemaVersion` handling,
but named only the sidecar, did not state that the check is exact in both directions, and set no
footprint bound.)

#### Scenario: State sidecar round-trips

- GIVEN a completed sync of 7,000 formulae and 8,500 casks
- WHEN the persisted state is read back
- THEN it reports `recordCount` 7,000 and 8,500 for the respective sources, a `downloadedAt`, the
  current `schemaVersion`, and the validators returned by the source

#### Scenario: Unknown schema version is treated as no cache

- GIVEN a persisted sidecar whose `schemaVersion` is greater than the one this build expects
- WHEN the catalog loads
- THEN it reports no usable cache, no error is thrown, and a full sync is scheduled

#### Scenario: A snapshot written by the previous schema is a cold start

- GIVEN a persisted snapshot whose `schemaVersion` is `1`, holding 15,000 readable records, beside a
  sidecar recording validators for both sources
- WHEN a build expecting `schemaVersion` 2 loads the catalog
- THEN it reports no usable cache, nothing is thrown, and the ordinary cold-launch progression runs
- AND the next sync re-downloads both payloads rather than revalidating into the rejected snapshot

#### Scenario: A sidecar written by the previous schema is rejected independently

- GIVEN a persisted snapshot at the current `schemaVersion` beside a sidecar whose `schemaVersion` is
  `1`
- WHEN the catalog loads
- THEN the sidecar is classified as no state, nothing is thrown, and no validator from it is replayed

#### Scenario: Rollback is symmetric

- GIVEN a persisted snapshot and sidecar written at `schemaVersion` 2
- WHEN a build that expects `schemaVersion` 1 loads the catalog
- THEN both files are classified as no cache, nothing is thrown, and one full sync restores service
- AND neither file was rewritten or deleted by the read

#### Scenario: The full-catalog footprint stays within its recorded bound

- GIVEN the full published catalog decoded with the widened projection
- WHEN the persisted snapshot size, the resident memory of the loaded snapshot, and the load time are
  measured
- THEN each is within the recorded bound, and the assertion fails if any of the three exceeds it

## ADDED Requirements

### Requirement: Inspection data costs no new acquisition

Every inspection field MUST be derived from the payload resources the catalog already acquires. This
capability MUST NOT gain a new brew invocation, a new remote resource, a per-package request, or any
request issued as a consequence of a package's detail being resolved. Resolving detail MUST remain
answerable from the persisted snapshot alone, with the network unreachable and no `brew` binary
present. Retaining a raw payload on disk beyond the sync that produced it is likewise excluded: the
persisted artefacts remain exactly the snapshot and its state sidecar.

#### Scenario: Inspection fields resolve offline and without brew

- GIVEN a persisted snapshot containing a cask with inspection fields, brew detection reporting
  `absent`, and a source that fails every request
- WHEN that cask's detail is resolved
- THEN every inspection field is served from the snapshot
- AND no brew process was spawned and no request was issued

#### Scenario: The widened sync issues no additional request

- GIVEN a fake `CatalogSource` that records each request
- WHEN a sync runs on a build carrying the widened projection
- THEN the recorded requests are exactly the payload and analytics resources the previous build
  requested — no additional resource and no per-package request
- AND no file other than the snapshot and its state sidecar remains in the catalog directory
