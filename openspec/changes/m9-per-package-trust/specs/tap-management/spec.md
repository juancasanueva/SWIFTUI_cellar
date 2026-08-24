# Delta for tap-management

Existing capability — `openspec/specs/tap-management/spec.md` (**13 requirements / 55 scenarios**,
established by `2026-08-05-m3-taps` and amended by `2026-08-23-m7-tap-trust`). This delta is
**1 MODIFIED, 0 added, 0 removed, 0 renamed**: **7 scenarios** replace the 5 the modified block
carries today, taking the capability to **13 requirements / 57 scenarios**.

Nothing is removed and no requirement is renamed, so `rules.archive`'s destructive-delta warning does
not fire. The MODIFIED block is a whole-block replacement copied from the main spec and then edited;
it is a strict superset of the text it replaces.

**This delta lands first (proposal risk R1).** TM12's single-source clause reads as absolute today —
"It MUST NOT require a second probe, a second store, a second source of truth, or a new invalidation
domain." Read strictly, "it" is *a tap's* trust state, which still comes from `tap-info`. Read as a
reviewer will read it, it governs the whole trust surface, and every other work unit in this change
contradicts it. Scoping the clause is therefore the first work unit, not a cleanup at the end.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m9-per-package-trust/` + Engram project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

**Binding decisions consumed** (maintainer, 2026-08-24, Engram `sdd/m9-per-package-trust/scope-decisions`
obs `#7759`): the count line lives on the tap **row and the detail header**, both from **one**
projection value; the badge does not change; the surface is read-only.

## Verification classes

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour | `swift test --package-path Packages/CellarCore` | **7** |

## MODIFIED Requirements

### Requirement: Tap trust is read from the tap snapshot and shown as a three-valued state

A tap's **own** trust state MUST be read from the snapshot this capability already acquires — the
per-tap `trusted` boolean carried by `brew tap-info --installed --json`. For that state, it MUST NOT
require a second probe, a second store, a second source of truth, or a new invalidation domain.

That clause is scoped to the **tap's own** trust state and MUST NOT be read as governing per-package
grants. Homebrew grants trust at two independent granularities and publishes the per-package one
through a different command, so a per-package grant is not derivable from `tap-info` at all. The
`package-trust` capability owns that second read with its own payload source and its own store, and
this capability MUST NOT acquire, cache or re-derive it.

Of the four things the clause names, exactly **two** are taken for per-package grants — a second probe
and a second store. **No new invalidation domain is introduced**: no Cellar command can mutate a
per-package grant, so there is nothing for a per-package domain to be declared by, and the grant read
refreshes with the **taps** domain this capability already declares. The tap's own trust state
therefore remains a single source of truth in the sense that matters: it is read from `tap-info`, by
this capability, and by nothing else. The grant ledger's own `taps` namespace MUST NOT be consumed as a
second source for it, MUST NOT feed the badge, and MUST NOT feed any tap-level trust decision.

The state MUST be **three-valued** — `trusted`, `untrusted`, `unreported` — and MUST NOT be reduced to
a boolean. `unreported` is the absent or null field: a Homebrew with no trust concept. Absence MUST NOT
be read as `untrusted`, on exactly the terms `installed-inventory` already applies to a cask's
tri-state `auto_updates`: "not declared" is not "declared false".

Exactly one projection MUST supply the trust presentation consumed by both the tap list row and the tap
detail header, so the two cannot drift. An `untrusted` tap MUST carry the exact badge text “Untrusted”
and MUST offer the **Trust** control. A `trusted` tap MUST carry no badge and MUST offer the
**Untrust** control. An `unreported` tap MUST carry no badge and MUST offer **neither** control, and
neither the **Trust nor the Untrust control** MUST build or spawn a process for it. This governs the
two controls only: TM7's revocation behind a successful removal is unconditional, so untapping an
`unreported` tap MUST still submit `untrust` once Homebrew has accepted the removal, where it MAY fail
— on a Homebrew with no trust verb it always will — and MUST remain visible as its own operation with
its own terminal outcome rather than being suppressed. Only third-party taps MUST expose either control; TM4 keeps official
sources non-mutable.

An **additive per-package count line** MAY accompany the badge on the tap row and the tap detail
header. It MUST be supplied by exactly one projection value read by both surfaces, on the same
one-projection rule the badge follows. It MUST NOT soften, qualify, replace, suppress or restyle the
“Untrusted” badge, and the badge's own text and the condition that produces it MUST remain exactly as
pinned above. The count line MUST be absent — not zero, not a placeholder — whenever there is nothing
positive to state. `package-trust` owns its value, its exact copy and its absence rules.

Every user-facing string **this capability** presents about trust MUST be scoped to the **tap**. None
MUST state or imply that a package is untrusted, because a per-package grant is independent of a tap
grant and can make a package loadable while its tap is not trusted. The per-package strings
`package-trust` contributes to this surface are positive-only by that capability's own rule, and MUST
NOT be used to qualify a tap-scoped string.
(Previously: the single-source clause was unqualified, so it read as forbidding any second trust read
anywhere in the app rather than a second source for the tap's own state; and no rule permitted, or
constrained, an additive per-package line beside the badge.)

#### Scenario: Trust decodes into three distinct states

- GIVEN tap records whose `trusted` field is in turn `true`, `false`, `null`, and absent
- WHEN the snapshot is decoded
- THEN the states are `trusted`, `untrusted`, `unreported` and `unreported`, respectively
- AND no absent field is reported as `untrusted`
- Verification: `unit`

#### Scenario: An unreported tap's controls show nothing and spawn nothing

- GIVEN a tap whose snapshot record carries no `trusted` field
- WHEN it is projected, its controls are enumerated and invoked, and it is separately untapped
- THEN it carries no badge and offers neither Trust nor Untrust
- AND neither control builds or spawns a process, and no trust command is submitted except the revocation TM7 pins behind that removal once Homebrew accepts it
- Verification: `unit`

#### Scenario: The badge and controls follow the state exactly

- GIVEN one `untrusted` tap and one `trusted` tap
- WHEN each is projected
- THEN the first carries the exact badge text “Untrusted” and offers Trust but not Untrust
- AND the second carries no badge and offers Untrust but not Trust
- Verification: `unit`

#### Scenario: List row and detail header read one projection

- GIVEN a tap in each of the three states
- WHEN the trust presentation consumed by the list row and by the detail header is compared
- THEN both come from the same projection and are identical for every state
- Verification: `unit`

#### Scenario: Trust copy is about the tap, never about a package

- GIVEN every user-facing string this capability presents about trust
- WHEN they are enumerated
- THEN each is scoped to the tap
- AND none states or implies that a package is untrusted
- Verification: `unit`

#### Scenario: The tap's own state still comes from one source

- GIVEN a tap whose trust state is in turn `trusted`, `untrusted` and `unreported`
- WHEN every acquisition this capability performs to produce that state is enumerated, with the
  per-package grant report in turn present, absent and failed
- THEN the tap's state comes only from the tap snapshot in every case
- AND it is unchanged by the presence, absence or failure of the per-package report
- AND the report's own `taps` namespace feeds neither the state nor the badge, even when it names that exact tap
- Verification: `unit`

#### Scenario: The count line is additive and never touches the badge

- GIVEN an `untrusted` tap with individually trusted packages, and the same tap with none
- WHEN the row and the detail header are projected
- THEN both carry the exact badge text “Untrusted” in both cases, from the same projection as before
- AND the count line is present in the first case and absent in the second, and in neither case does it
  alter, replace or qualify the badge
- Verification: `unit`

## Notes for archive

- The MODIFIED block **replaces** its same-named block (TM12) in
  `openspec/specs/tap-management/spec.md` as a whole block. TM1–TM11 and TM13 are untouched.
- **TM9 needs no delta, verified against its text — and this is now a stronger claim than it was.**
  No new invalidation domain exists: the grant read refreshes with the **taps** domain, so every count
  TM9 pins (taps exactly once per terminal; installed inventory exactly once for force untap, trust and
  untrust; the catalog never) is arithmetically unchanged, and no command's `invalidates` declaration
  is touched. `package-trust` PT2 owns the rule that the grant read rides that domain and that a
  failing grant read never changes a tap refresh's outcome or its refresh count.
- **TM11 needs no delta, verified against its text.** Its enumerated action set — refresh, filter,
  Installed handoff, canonical add, plain untap, eligible force untap, trust, untrust — is unchanged by
  this change, which adds **no action**: the per-package surface is read-only display. Its second
  scenario ("Trust is a reported state and a grant, never a verdict") is reinforced rather than
  contradicted; `package-trust` PT6 restates the same rule for per-package copy.
- **TM1 needs no delta, verified.** Its middle state's copy is already scoped to the tap and already
  states the reason a per-package grant exists ("a per-package grant can make a package loadable while
  its tap is not trusted"). The per-package marker `package-trust` PT5 adds to tap-detail package rows
  is additive beside that copy and replaces none of the three install states.
- Extend the provenance section with this change's binding decisions: the single-source clause is
  **scoped to the tap's own trust state**; a per-package grant is a second read the `package-trust`
  capability owns; and of the clause's four prohibitions **only two are taken** — a second probe and a
  second store — because design decision **DD-3** (2026-08-24) adds **no new invalidation domain**.
  Record what was rejected: extending `tap-info` to carry per-package grants (it does not publish
  them); a dedicated per-package invalidation domain (dead declaration surface across every command
  family, since no Cellar command can mutate a per-package grant); consuming the grant ledger's `taps`
  namespace as a second source for a tap's own state; and changing or softening the “Untrusted” badge.
