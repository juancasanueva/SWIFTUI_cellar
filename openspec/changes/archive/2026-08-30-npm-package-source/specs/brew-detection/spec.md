# Delta for brew-detection

Existing capability — `openspec/specs/brew-detection/spec.md` (**5 requirements / 17 scenarios**). This
delta is **1 ADDED, 0 modified, 0 removed, 0 renamed**; every shipped requirement is byte-identical. The
capability becomes **6 requirements / 19 scenarios**. npm's own detection rules live in `npm-source`; this
delta binds only the boundary between the two.

## ADDED Requirements

### Requirement: npm detection is a sibling state model and widens nothing in brew's

Brew detection's state, prefix and invalidity vocabularies MUST remain exactly as shipped: no npm case,
no npm reason and no npm prefix MUST be added to them. npm detection MUST be a separate observable state
with its own store, sharing only the `ExecutableProbing` seam and the request-keyed coalescing idiom.
Brew detection MUST NOT probe, wait on or be republished because of an npm evaluation, and vice versa.

#### Scenario: Brew's vocabularies are unchanged

- GIVEN the brew detection state, prefix and invalidity types
- WHEN their cases are enumerated
- THEN the case lists are exactly the shipped ones, with no npm-named case
- Verification: `unit`

#### Scenario: The two evaluations do not couple

- GIVEN an npm evaluation that does not answer until released and a brew re-evaluation requested
  meanwhile
- WHEN the brew evaluation completes
- THEN brew observers receive their transition before the npm evaluation is released
- AND releasing npm republishes no brew state
- Verification: `unit`
