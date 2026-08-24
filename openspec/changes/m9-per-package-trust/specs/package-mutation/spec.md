# Delta for package-mutation

Existing capability — `openspec/specs/package-mutation/spec.md` (**10 requirements / 60 scenarios**,
established by `2026-08-02-m2-mutations-activity` and amended by later changes, most recently
`2026-08-23-m7-tap-trust`). This delta is **1 MODIFIED, 0 added, 0 removed, 0 renamed**: **10
scenarios** replace the 7 the modified block (PM10) carries today, taking the capability to
**10 requirements / 63 scenarios**.

Nothing is removed and no requirement is renamed, so `rules.archive`'s destructive-delta warning does
not fire. The MODIFIED block is a whole-block replacement copied from the main spec and then edited;
it is a strict superset of the text it replaces — **zero lines deleted**, and all seven existing
scenarios survive byte-identical.

**What this delta does not do, stated first.** It does **not** relax the argv prohibition. PM10's
absence — no argv on the shared mutation spine carries a `/`-qualified package token — is reaffirmed,
not narrowed, and the shipped assertion that proves it (`MutationCommandTests ·
noPackagePositionEverCarriesAQualifiedToken`) MUST remain **byte-identical**. The change is on the
other side of the requirement: the no-pre-launch-gate rule currently names only the *tap's* trust
state, so a gate could be reintroduced through a per-package grant store the rule never mentions, and
the source-scanning absence that enforces it lists only the tap-trust type names.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`,
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

## Verification classes

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour | `swift test --package-path Packages/CellarCore` | **8** |
| `manual-evidence` | no harness can exist — a real refusal from a real `brew` on a real Mac | the maintainer; transcript captured in the verify report. **Binding: never run `brew upgrade` without `--dry-run` on that Mac** | **2** |

## MODIFIED Requirements

### Requirement: A refusal to load from an untrusted tap is a typed outcome, and no argv ever becomes the grant

A mutation that **fails** with Homebrew's untrusted-tap refusal signature on **stderr** MUST be reported
as a distinct typed outcome, a sibling of the typed sudo failure and the typed busy failure and bound by
exactly the same discipline: stderr only, bounded to the shipped classification tail window, structural
facts first, and **nothing extracted from the payload**. No tap name, package name, qualified token or
suggested command MUST be parsed out of the message. Output on stdout MUST NOT classify, and a
successful terminal outcome MUST NOT classify however the output reads.

The measured signature is Homebrew 6.0.18's **cask** refusal — ``Error: Refusing to load cask
<qualified> from untrusted tap <tap>. Run `brew trust --cask <qualified>` or `brew trust <tap>` to
trust it.`` Matching MUST rest on **one** structural phrase about the tap, read from the shipped
stderr tail window, so a reworded prefix or suffix cannot silently disable classification and no phrase
broad enough to catch an unrelated refusal can offer a trust affordance for it. A refusal to load that
names no untrusted tap MUST NOT classify, because Homebrew refuses to load for reasons a trust grant
would not fix and offering Trust for one of them is a misdirection, not merely a wrong sentence. The
literal string is design-owned (:35-36). **The formula refusal wording has never been observed**, and this requirement MUST NOT be read as claiming coverage of it: the exact formula stderr
MUST be captured as manual evidence before the classifier is asserted to cover the formula form, and
until it is, a formula refusal degrades to the ordinary generic failure with its verbatim log — the
fallback the outcome type already documents. Widening the match later MUST require no structural change.

The typed outcome MUST offer a path to grant the tap's trust, and its message MUST be scoped to the
**tap**: exactly “Homebrew refused to load this package because its tap is not trusted. Trust the tap in
Taps, then try again.” It MUST NOT state or imply that the package is untrusted, because a per-package
grant is independent of a tap grant. The verbatim log MUST remain visible beside it, since it already
carries brew's own exact `brew trust …` line. The outcome MUST NOT be retried automatically, MUST NOT
suppress the refreshes the command declared, and MUST NOT be presented as a Cellar defect.

**The prohibition.** No argv this capability or any command on the shared mutation spine spawns MUST
contain a `/`-qualified package token — on any path, including the recovery offered after this refusal
and any retry. Homebrew treats *naming* a qualified package to its trust machinery **as the grant**, so
a requalified retry would convert a refusal into silent execution of code the user never consented to
run, while looking exactly like a bug fix. The shipped name-safety gate permits `/`, so this MUST be
asserted as an **absence over the whole mutation surface** by a test, never left to review.

This prohibition MUST NOT be weakened by the existence of a capability that *reads* per-package grants.
`package-trust` acquires the report with compile-time-constant argv carrying no package identity, and
that read is not a command on the shared mutation spine: it MUST NOT be added to the spine's argv
enumeration, and the assertion proving the absence MUST remain unchanged by it.

The refusal MUST NOT be converted into a pre-launch gate. This capability MUST NOT block a mutation
because the package's tap is untrusted: with the tap withheld the inventory cannot prove the origin
tap, and a per-package grant can make brew allow exactly what a tap-state gate would refuse. Only brew
sees both grant kinds, so only brew decides.

**The same prohibition MUST hold for per-package grant state.** This capability MUST NOT block,
disable, hide, delay or pre-qualify a mutation, an affordance or a request because a package has, or
lacks, an individual grant — and MUST NOT read the per-package trust report, store or projection to
decide anything before launch. A `noGrantRecorded` state is not a prediction of refusal: a package
under a trusted tap needs no individual grant, and an `unreported` report is not evidence of anything
at all. Gating on it would refuse exactly what brew allows, which is the defect the tap-state gate was
prohibited for.

Because both prohibitions are absences, they MUST be enforced **structurally**: the shipped
source-scanning assertion that fails when a trust type name appears in the mutation command surface
MUST name the per-package trust types as well as the tap-trust ones. Keeping a new store out of that
surface by accident MUST NOT be relied on; a type this capability must never consult MUST be on that
list.
(Previously: the no-pre-launch-gate rule named only the tap's trust state, and the source-scanning
absence that enforces it listed only the tap-trust type names — so once a per-package grant store
existed, a pre-launch gate could be reintroduced through a store the rule never mentioned, and the
guard would not fire.)

#### Scenario: A stderr refusal on a failed mutation is the typed outcome

- GIVEN a mutation that exits non-zero and emits on stderr ``Error: Refusing to load cask acme/tools/widget from untrusted tap acme/tools. Run `brew trust --cask acme/tools/widget` or `brew trust acme/tools` to trust it.``
- WHEN the operation reaches its terminal outcome
- THEN it is reported as the typed untrusted-tap refusal, not as a generic failure
- Verification: `unit`

#### Scenario: The same prose on stdout, on a success, or without the tap phrase does not classify

- GIVEN the same refusal prose emitted on stdout with a non-zero exit, separately on stderr with exit status 0, and separately a failing stderr line that refuses to load but names no untrusted tap
- WHEN each reaches its terminal outcome
- THEN the first and third are generic failures with their verbatim logs, and the second is a success
- AND none of the three is reported as the typed untrusted-tap refusal
- Verification: `unit`

#### Scenario: Nothing is extracted from the refusal

- GIVEN a classified untrusted-tap refusal
- WHEN its typed value and user-facing message are inspected
- THEN neither carries a tap name, package name, qualified token or command parsed out of the message
- AND the classification read no more than the shipped stderr tail window
- Verification: `unit`

#### Scenario: The outcome offers Trust and is worded about the tap

- GIVEN a classified untrusted-tap refusal
- WHEN its message and affordances are read
- THEN the message is exactly “Homebrew refused to load this package because its tap is not trusted. Trust the tap in Taps, then try again.”
- AND a path to trusting the tap is offered, the verbatim log remains visible, and nothing is retried automatically
- Verification: `unit`

#### Scenario: No mutation argv anywhere carries a qualified package token

- GIVEN every path that builds a command on the shared mutation spine, including the recovery offered after an untrusted-tap refusal and any retry of a failed mutation
- WHEN every argv element each path can produce is enumerated
- THEN none contains a `/`-qualified package token
- AND the enumeration is non-vacuous: it covers every command family on the spine
- Verification: `unit`

#### Scenario: An untrusted tap never pre-blocks a mutation

- GIVEN an installed package whose tap is withheld and whose tap's trust state is `untrusted`
- WHEN a mutation is requested for it
- THEN it is built and submitted normally
- AND no affordance was disabled and no request was refused on the basis of tap trust state
- Verification: `unit`

#### Scenario: A per-package grant state never pre-blocks a mutation

- GIVEN the same package with its per-package state in turn `granted`, `noGrantRecorded` and `unreported`, and separately a machine whose per-package report failed to load
- WHEN a mutation is requested in each case
- THEN it is built and submitted normally in every case
- AND no affordance was disabled, no request was refused, and no warning was attached on the basis of per-package grant state
- Verification: `unit`

#### Scenario: The source-scanning absence names the per-package trust types

- GIVEN the shipped assertion that scans the mutation command surface for trust type names
- WHEN the names it scans for are enumerated
- THEN every per-package trust wire, store and projection type name is covered by them — whether as a full name or as a shared prefix — alongside the tap-trust names already listed
- AND introducing any of those names into that surface makes the assertion fail
- Verification: `unit`

#### Scenario: The per-package read is not a command on the mutation spine

- GIVEN the per-package trust read and every command family on the shared mutation spine
- WHEN the spine's families are enumerated and the read is submitted
- THEN the read is not one of those families, enqueues nothing, and produces no activity item
- AND it declares no invalidation domain of its own, and no new invalidation domain value exists for the spine to declare
- AND the spine's qualified-token enumeration covers exactly the families it covered before
- Verification: `unit`

#### Scenario: The formula refusal wording is captured before the classifier claims it

- GIVEN a formula published by an untrusted tap on a Mac running Homebrew 6.0.18
- WHEN a bare-token mutation for it is refused and its exact stderr is recorded
- THEN those bytes are captured verbatim in the verify report
- AND the classifier is asserted to cover the formula form only after that capture
- Verification: `manual-evidence`

#### Scenario: A real refusal renders the typed outcome with brew's own trust line

- GIVEN a package installed from an untrusted tap
- WHEN a bare-token upgrade is launched from inside Cellar, using `--dry-run` or a self-updating cask so that no unguarded `brew upgrade` runs
- THEN the operation renders the typed untrusted-tap refusal
- AND brew's own `brew trust …` line is visible in the verbatim log
- Verification: `manual-evidence`

## Notes for archive

- The MODIFIED block **replaces** its same-named block (PM10) in
  `openspec/specs/package-mutation/spec.md` as a whole block. PM1–PM9 are untouched.
- Record in provenance that the argv prohibition was **reaffirmed, not relaxed**: this change adds a
  per-package trust *read* and no per-package trust *command*, and the assertion
  `noPackagePositionEverCarriesAQualifiedToken` is unchanged. The C1 source-scanning ban list is
  **extended** with the per-package trust type names — the one deliberate edit to a shipped guard.
- Record what this deferred and why: per-package grant/revoke controls remain out of scope until the
  `brew untrust --formula|--cask <qualified>` probe answers whether the revocation itself registers a
  grant through `explicitly_allowed?` before removing it.
