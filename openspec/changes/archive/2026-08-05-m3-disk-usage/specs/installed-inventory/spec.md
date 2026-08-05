# Delta for installed-inventory

Existing capability — `openspec/specs/installed-inventory/spec.md` (14 requirements / 57 scenarios).
Owned by `Packages/CellarCore` target `BrewClient`.

Delta summary: **1 MODIFIED requirement — 5 scenarios (4 carried forward, 1 added)**. Nothing is
ADDED, REMOVED, or RENAMED. The full replacement block is reproduced below.

## MODIFIED Requirements

### Requirement: Asymmetric formula and cask installation shapes both decode

Decoding MUST accept the payload's asymmetric shapes: a formula's installed data is an array of keg
records, and a cask's installed data is a plain version string. A formula with more than one
installed keg MUST be represented with all of its kegs, never truncated to one and never dropped. A
cask's `auto_updates` field is tri-state (`true`, `null`, absent, never `false` in observed
payloads) and MUST be preserved as "declared" versus "not declared" at decode time rather than
folded into a plain boolean. A formula's optional linked-keg value MUST be preserved exactly: a
present value identifies the linked version, while absence means unlinked and MUST NOT be replaced
with the newest installed keg. This observable state MUST remain available for disk attribution.
(Previously: decoding preserved every installed keg but collapsed an absent linked-keg value to the
newest keg, losing the distinction between linked and unlinked formulae.)

#### Scenario: A single-keg formula decodes

- GIVEN a formula record whose installed array holds one keg
- WHEN the payload is decoded
- THEN the formula appears in the inventory with that keg's version and install time

#### Scenario: A multi-keg formula keeps every keg

- GIVEN a formula record whose installed array holds two kegs with different versions
- WHEN the payload is decoded
- THEN the formula appears once with both installed versions represented
- AND neither keg is dropped

#### Scenario: A cask's string installed version decodes

- GIVEN a cask record whose installed field is the string `1.2.3`
- WHEN the payload is decoded
- THEN the cask appears in the inventory with installed version `1.2.3`

#### Scenario: An undeclared auto-update flag is distinguishable from a declared one

- GIVEN one cask record with `auto_updates` true and one with `auto_updates` null
- WHEN both are decoded
- THEN the first is classified as self-updating and the second is not
- AND the null value is recorded as "not declared", not as an explicit false

#### Scenario: Linked-keg absence remains unlinked

- GIVEN a multi-keg formula with no linked-keg value, and another naming its older keg
- WHEN both are decoded for disk attribution
- THEN the first is unlinked and the second names that older keg as linked
- AND neither is inferred from the newest installed keg
