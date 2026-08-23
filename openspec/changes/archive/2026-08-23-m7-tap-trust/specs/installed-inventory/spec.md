# Delta for installed-inventory

Existing capability — `openspec/specs/installed-inventory/spec.md` (**14 requirements / 64
scenarios**). This delta is **1 MODIFIED, 0 added, 0 removed, 0 renamed**: **8 scenarios** replace the
5 the modified block carries today, taking the capability to **14 requirements / 67 scenarios**.

Nothing is removed and no requirement is renamed, so `rules.archive`'s destructive-delta warning does
not fire. The MODIFIED block is a whole-block replacement copied from the main spec and then edited,
and is a strict superset of the text it replaces.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m7-tap-trust/` + Engram canonical project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

**One fact, one value.** `brew info --installed --json=v2` reports `tap: null` for a package whose tap
Homebrew withholds — the tap exists and is untrusted, so brew declines to name it (obs `#7721`). The
shipped decoder collapses that null into the empty string, which makes "brew did not report a tap"
indistinguishable from "the tap is empty" and makes every such package read “Not installed.” in the tap
inventory. This delta makes the absence representable on **exactly the terms this requirement already
states for a cask's tri-state `auto_updates`**: not reported is not reported-as-something-else.

## Verification classes — with the runner named per class

Every scenario below declares exactly one verification class.

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour, per `config.yaml` `rules.specs` | `swift test --package-path Packages/CellarCore` | **8** |

No scenario in this delta needs `manual-evidence`: the payload shape is already measured and the
behaviour is entirely decode-side.

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

A record's **tap is optional on exactly the same terms**. Homebrew reports `tap: null` for a package
whose tap it withholds — the tap exists but is untrusted, so brew declines to name it. That absence
MUST be preserved as absence: it MUST NOT be collapsed into the empty string, into a placeholder, or
into any other sentinel value, because "brew reported no tap" and "the tap is the empty string" are two
different facts and no single value may stand for both. A record whose tap is absent MUST still decode
and MUST still appear in the inventory; only the tap is unknown, and no other field is affected.

An absent tap MUST NOT compare equal to any tap name. Every consumer that matches a package against a
selected tap MUST treat absence as "no answer" rather than as a match or as an empty-string match, so a
withheld tap can never be silently attributed to a tap that did not publish it. What a consumer *shows*
for an absent tap belongs to that consumer — `tap-management` TM5 owns the tap-inventory reading — but
this capability MUST make the distinction available rather than resolving it at decode time.
(Previously: decoding preserved every installed keg but collapsed an absent linked-keg value to the
newest keg, losing the distinction between linked and unlinked formulae; and a null `tap` was collapsed
into the empty string, losing the distinction between a withheld tap and an unset one.)

#### Scenario: A single-keg formula decodes

- GIVEN a formula record whose installed array holds one keg
- WHEN the payload is decoded
- THEN the formula appears in the inventory with that keg's version and install time
- Verification: `unit`

#### Scenario: A multi-keg formula keeps every keg

- GIVEN a formula record whose installed array holds two kegs with different versions
- WHEN the payload is decoded
- THEN the formula appears once with both installed versions represented
- AND neither keg is dropped
- Verification: `unit`

#### Scenario: A cask's string installed version decodes

- GIVEN a cask record whose installed field is the string `1.2.3`
- WHEN the payload is decoded
- THEN the cask appears in the inventory with installed version `1.2.3`
- Verification: `unit`

#### Scenario: An undeclared auto-update flag is distinguishable from a declared one

- GIVEN one cask record with `auto_updates` true and one with `auto_updates` null
- WHEN both are decoded
- THEN the first is classified as self-updating and the second is not
- AND the null value is recorded as "not declared", not as an explicit false
- Verification: `unit`

#### Scenario: Linked-keg absence remains unlinked

- GIVEN a multi-keg formula with no linked-keg value, and another naming its older keg
- WHEN both are decoded for disk attribution
- THEN the first is unlinked and the second names that older keg as linked
- AND neither is inferred from the newest installed keg
- Verification: `unit`

#### Scenario: A withheld tap decodes as absent, not as empty

- GIVEN formula and cask records whose `tap` is in turn `null`, absent, and `"acme/tools"`
- WHEN each is decoded
- THEN the first two report no tap and the third reports `acme/tools`
- AND neither of the first two reports the empty string or any other placeholder
- Verification: `unit`

#### Scenario: A record with a withheld tap still enters the inventory

- GIVEN an installed cask record with a valid version and `tap: null`
- WHEN the payload is decoded
- THEN that cask appears in the inventory with its version, kind and install data intact
- AND only its tap is unknown
- Verification: `unit`

#### Scenario: An absent tap never matches a selected tap

- GIVEN an inventory holding one package with no tap and one with tap `acme/tools`
- WHEN each is matched against the selected tap `acme/tools`, and separately against the empty string
- THEN only the second matches `acme/tools`
- AND the first matches neither
- Verification: `unit`

## Notes for archive

- The MODIFIED block **replaces** its same-named block in
  `openspec/specs/installed-inventory/spec.md` as a whole block. The other thirteen requirements are
  untouched and stay byte-identical.
- **No `## Verification classes` table exists in this spec**, so there is **no class table to
  hand-update at archive**. This delta is the first to annotate `installed-inventory` scenarios with an
  inline `- Verification:` line; the untouched requirements deliberately keep none.
- **The `(Previously:)` annotation is extended, not replaced.** The `m5`-era linked-keg note stays and
  the tap clause is appended to it, because both describe the same block's history and neither has been
  superseded by the other. If the repository's one-rolling-note-per-block convention is read strictly
  at archive, keep the combined sentence rather than dropping the linked-keg half.
- Record in provenance that the optional tap is **not** a compile-error migration: Swift promotes the
  non-optional operand of `==`, so all three shipped readers keep compiling and stay semantically
  correct (`nil` equals nothing). Only the declaration and the two decoder sites change, and the
  readers are pinned by `InstalledDeriveTests · everyTapReaderTreatsAbsenceAsNoMatch` rather than by
  the compiler. Record too that `CatalogPackage.tap` is a **different, unchanged** property that
  happens to share the name (risk R8).
- Record that this requirement is independent of the trust surface: it is a strict honesty improvement
  and the proposal's rollback plan lets it stay even if every other piece of `m7-tap-trust` is reverted.
