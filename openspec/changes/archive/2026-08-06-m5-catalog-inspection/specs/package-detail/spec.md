# Delta for package-detail

Existing capability — `openspec/specs/package-detail/spec.md` (6 requirements / 17 scenarios).

Delta summary: **1 MODIFIED requirement** (reproduced in full so the archive step loses nothing) and
**1 ADDED requirement**. Nothing is REMOVED or RENAMED.

- *Required detail projection* — 10 scenarios (4 carried forward byte-identical, 6 added) — gains the
  cask inspection fields, the projected-stanza set with its counted remainder, the nothing-runnable
  rule, and the uniformity rule.
- **ADDED** *No pre-install signature or notarization verdict* — 3 scenarios — the explicit non-goal,
  stated as a prohibition so it is testable rather than a note.

Traceability: **D2** → the projected stanza set and the counted remainder, **as narrowed by D5**;
**D3** → `conflicts_with` as a projected field; **D4** → the fields the always-visible section
renders (this capability specifies only the CellarCore data that feeds it — no SwiftUI view is
specified here).

**D5 was triggered, and it narrows D2 and D4.** Probe U4 measured the artifacts widening and rejected
carrying the full stanza tree: `zap` alone costs +1.23 MB encoded, +34% over the entire accepted
widening, and is a directive map (`trash`, `rmdir`, `launchctl`, `pkgutil`, `script`, …) rather than a
name list. The projected stanza set is therefore **`app`, `binary`, `pkg`** — 0.15 MB, and exactly the
stanzas that answer the binding success criterion "what gets installed where". `zap`, `uninstall`,
`font` and every unmodelled kind are counted in the remainder and their contents are not
projected (`target` is a companion key attached to the stanza it modifies, not a stanza kind, so it
is neither projected nor counted). D2's five-kind list and D4's "zap and uninstall render faithfully" are superseded by D5
*as triggered*, which is the mechanism D5 exists to provide. This is a narrowing of a narrowing: D5's
own written fallback was to drop `artifacts` entirely.

## MODIFIED Requirements

### Requirement: Required detail projection

A package detail resolved by `(kind, name)` MUST expose: display name, kind, description, homepage,
license, version, caveats, tap of origin, direct build dependencies, direct runtime dependencies,
dependents, deprecation status, disabled status, and install count. Fields the payload publishes as
`null` or omits MUST be exposed as absent, distinct from an empty string. A lookup for a package not
in the snapshot MUST return not-found rather than throwing.

A cask detail MUST additionally expose, when the payload publishes them: the download URL, the
published `sha256` checksum, what the cask installs, the cask's declared dependencies
(`depends_on`), the packages it declares a conflict with (`conflicts_with`), and its auto-updates
flag. A formula detail MUST additionally expose its stable source URL and its head source URL. Each
of these MUST follow the same absence rule as every other optional field: a cask that publishes no
`depends_on` MUST report absence, distinct from an empty list, and a value the payload omits MUST NOT
be substituted with a default.

What a cask installs MUST be exposed as a closed, typed set of artifact stanza kinds — exactly `app`,
`binary` and `pkg` — together with a count of every published stanza the projection does not
represent. The set is deliberately this narrow: these three answer "what gets installed where", and
nothing else is projected. A `zap` stanza, an `uninstall` stanza, and every other published stanza
kind MUST be counted in that remainder rather than projected, and their contents MUST NOT be carried
by this projection at all. The count MUST be a value a consumer can render directly (an "N not shown"
remainder), MUST be `0` rather than absent when every published stanza was represented, and MUST be
distinct from the snapshot's skipped-record count. A published stanza MUST NOT be discarded without
being counted.

Every artifact value this projection exposes MUST be data describing what an installer declares it
will place on the machine, never an instruction this system carries out. Because no `zap`,
`uninstall` or other directive stanza content is projected, the projection MUST carry nothing that
could be executed or acted on: no command, no script, no `launchctl` or `pkgutil` directive, and no
path that a removal would delete. It MUST NOT expose an action that runs any published stanza. The
counted remainder MUST remain a count — it MUST NOT carry the content of the stanzas it counted.

Exposure MUST be uniform across records: a field this projection carries MUST be present for every
package that publishes it and absent for every package that does not. A field MUST NOT appear for one
record and silently vanish for another that published the same key.
(Previously: the projection covered the fourteen fields above with the same absence rule, and carried
no cask inspection field, no artifact stanzas, no counted remainder, no formula source URLs, and no
nothing-runnable or uniformity rule.)

#### Scenario: Formula detail exposes every required field

- GIVEN a snapshot containing formula `wget`
- WHEN its detail is resolved
- THEN it reports description `Internet file retriever`, homepage, license `GPL-3.0-or-later`,
  version, tap `homebrew/core`, kind `formula`, and its dependency, dependent, deprecation, disabled
  and install-count fields

#### Scenario: Cask detail exposes every required field

- GIVEN a snapshot containing cask `iterm2`
- WHEN its detail is resolved
- THEN it reports display name `iTerm2`, kind `cask`, version, homepage and tap `homebrew/cask`

#### Scenario: Absent optional fields are absent, not empty

- GIVEN a record whose payload had `"desc": null`, `"caveats": null` and no license
- WHEN its detail is resolved
- THEN description, caveats and license are absent and are not empty strings

#### Scenario: Unknown package is not-found, not an error

- GIVEN a snapshot without `nosuchpackage`
- WHEN a detail lookup for `(formula, nosuchpackage)` runs
- THEN it returns not-found and nothing is thrown

#### Scenario: Cask detail exposes its inspection fields

- GIVEN a snapshot containing cask `iterm2`, whose published record carries a download URL, a
  `sha256`, an `app` stanza targeting `/Applications/iTerm.app`, a `zap` stanza listing paths, a
  `depends_on` entry and a `conflicts_with` list naming `iterm2@beta` and `iterm2@nightly`
- WHEN its detail is resolved
- THEN the download URL, the checksum, the `app` stanza, the dependency and both conflict entries are
  exposed, each matching the published payload
- AND the `zap` stanza is not exposed — it appears only as `1` in the count of unrepresented stanzas
- AND the auto-updates flag is exposed

#### Scenario: Every projected stanza kind is exposed

- GIVEN a cask whose `artifacts` list publishes an `app`, a `binary` and a `pkg` stanza and nothing
  else
- WHEN its detail is resolved
- THEN all three stanzas are exposed under their own kinds, each carrying the name it was published
  with and its destination where one was published
- AND the count of unrepresented stanzas is `0` and is not absent

#### Scenario: Every unprojected stanza kind is counted, never silently dropped

- GIVEN a cask whose `artifacts` list publishes an `app` stanza plus a `zap`, an `uninstall` and a
  stanza of a kind that did not exist when this build shipped
- WHEN its detail is resolved
- THEN the `app` stanza is exposed and the count of unrepresented stanzas is `3`
- AND that count is reported separately from the snapshot's skipped-record count
- AND a second cask publishing only unprojected stanzas resolves with no exposed stanza and a
  non-zero count

#### Scenario: A cask publishing no dependencies reports absence, not emptiness

- GIVEN a cask publishing neither `depends_on` nor `conflicts_with`, and no `artifacts`
- WHEN its detail is resolved
- THEN all three are absent and are distinguishable from an empty list
- AND the detail resolves successfully with every other required field intact

#### Scenario: Formula source URLs are exposed

- GIVEN a snapshot containing formula `git`, whose payload publishes `urls.stable.url` and
  `urls.head.url`
- WHEN its detail is resolved
- THEN both source URLs are exposed
- AND a formula publishing no `urls.head` reports an absent head URL

#### Scenario: Nothing the projection exposes is runnable

- GIVEN a cask publishing an `app` stanza, a `zap` stanza listing paths and `launchctl` directives,
  and an `uninstall` stanza carrying a script
- WHEN its detail is resolved and every exposed value is enumerated
- THEN the only artifact values exposed are the `app` stanza's name and destination, plus an
  unrepresented-stanza count of `2`
- AND no exposed value carries a path, command, script or directive drawn from the `zap` or
  `uninstall` stanza
- AND the projection offers no operation that executes any published stanza, deletes any listed path,
  or mutates the machine

## ADDED Requirements

### Requirement: No pre-install signature or notarization verdict

Catalog data supports no claim about a package's code signature or notarization status, so this
projection MUST NOT derive, expose, or make expressible any such claim. It MUST NOT carry a
signature status, a notarization status, a signing identity, a team identifier, a trust verdict, or
any value whose meaning is "this download is verified". The published `sha256` MUST be exposed only
as the checksum the cask declares for its download — an expectation stated by the published record,
not the result of any check this system performed, and not evidence about the origin's identity. A
cask that publishes `no_check` in place of a digest MUST be exposed as declaring no checksum,
distinguishably from a cask that declares one; that literal MUST NOT be exposed as though it were a
digest, and MUST NOT be silently dropped.

Post-install signature and notarization inspection remains the property of the capabilities that own
it; this projection MUST NOT accept, reuse, or forward a verdict from them for a package that is not
installed. A field that would tempt a consumer to render a verdict MUST NOT exist, so the prohibition
is enforced by the projection's shape rather than by a consumer's discipline.

#### Scenario: A fully populated cask detail yields no signature claim

- GIVEN a cask whose payload publishes every widened key, including `url` and `sha256`
- WHEN its detail is resolved and every exposed field is enumerated
- THEN no field reports a signature status, a notarization status, a signing identity, a team
  identifier, or a verification verdict

#### Scenario: The checksum is a published expectation, not a verification result

- GIVEN a cask detail exposing a `sha256`, and a second cask whose payload publishes `"sha256":
  "no_check"`
- WHEN each value's semantics are inspected
- THEN the first is identified as the checksum the published record declares for the download
- AND the second is identified as declaring no checksum, and its literal is not exposed as a digest
- AND no field states or implies that either download was fetched, hashed, or verified

#### Scenario: No post-install verdict reaches an uninstalled package

- GIVEN a machine holding post-install integrity results for an installed cask, and a second cask
  that is not installed
- WHEN the second cask's detail is resolved
- THEN it carries no integrity, signature or notarization value of any kind
- AND the projection declares no dependency on the capability that produces those results
