# Delta for package-mutation

Existing capability — `openspec/specs/package-mutation/spec.md` (**9 requirements / 48 scenarios**,
established by the archived `2026-08-02-m2-mutations-activity` and amended by `m2-local-metadata-history`,
`m3-services`, `m3-taps` and `m5-brewfile`). This delta is **2 MODIFIED / 1 ADDED, 0 removed,
0 renamed**: **22 scenarios** replace the 18 the two modified blocks carry today, and **8 scenarios**
are added, taking the capability to **10 requirements / 60 scenarios**.

Nothing is removed and no requirement is renamed, so `rules.archive`'s destructive-delta warning does
not fire. Both MODIFIED blocks are whole-block replacements copied from the main spec and then edited;
each is a strict superset of the text it replaces, and no package rule is loosened.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m7-tap-trust/` + Engram canonical project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

**The batch-disclosure rule is the one shipped security invariant this change touches.** Proposal open
question 1 resolves to its default (maintainer, 2026-08-23): PM1 is MODIFIED so a batch takes the
disclosure of the first submitted command that declares one **of its own**, skipping commands that rely
on the protocol default. This is required because `tap-management` TM7/TM8 now lead every removal batch
with a revocation, which declares no disclosure — under the shipped rule that batch would silently fall
back to the package-removal disclosure and defeat the force-untap warning PM1 exists to protect. The
resolution *strengthens* the anti-downgrade rule, adds no disclosure case, and leaves
`brewfile-management` BF7's ordering rule intact.

## Verification classes — with the runner named per class

Every scenario below declares exactly one verification class.

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour, per `config.yaml` `rules.specs` | `swift test --package-path Packages/CellarCore` by default; `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests` for the app-target composition scenarios | **28** |
| `manual-evidence` | no harness can exist — the exact stderr bytes belong to a real `brew` refusing a real load, and one of them has never been observed | the maintainer, on a real Mac running Homebrew 6.0.18; transcript captured in the verify report. **Binding: never run `brew upgrade` without `--dry-run` on that Mac** | **2** |

What stays **design-owned and is deliberately absent here**: the classifier's literal match strings and
their case handling, the size of the shipped stderr tail window, which type holds the new outcome, and
how the recovery affordance is placed.

## MODIFIED Requirements

### Requirement: Every mutation is a typed command carrying an explicit kind flag

The capability MUST expose exactly six mutating commands — install, uninstall, reinstall, upgrade,
pin and unpin — each built from the `(kind, name)` package identity already used by the catalog and
the inventory. Every generated argv MUST pass the kind explicitly as `--formula` or `--cask` and
MUST NOT rely on brew's token disambiguation, because a token such as `docker` exists in both
namespaces. A single invocation MUST NOT carry both kind flags. The argv MUST be inspectable before
the operation is submitted, and the argv actually spawned MUST be identical to the inspected one.

This capability's mutating-command type MUST continue to carry exactly those six commands and no
others. The shared mutation spine MAY carry commands belonging to other capabilities, and every such
command MUST enter it through a shared abstraction rather than as an additional case of this
capability's command type. Adding a non-package verb as a seventh case is forbidden, because that
type's identity, verb and argv are package-shaped by construction. Everything the spine needs from a
command — its argv, its verb, the package identity it acts on **when it has one**, its display
command, whether it requires confirmation, the state domains it invalidates, and **the confirmation
disclosure it carries** — MUST be readable through that shared abstraction, so no consumer of the
spine needs to know which capability a command came from.

The disclosure MUST be part of that abstraction rather than recovered from a concrete command type.
No consumer of the spine MUST derive a disclosure by downcasting, type-testing, switching on a
command case, or inspecting a verb string; a command that declares no disclosure of its own MUST
supply the ordinary package-removal disclosure by default rather than by a caller's fallback.

A batch's disclosure MUST be derived from the commands themselves — **the first submitted command that
declares a disclosure of its own**, skipping any command that supplies only the protocol default — so a
batch presents the same disclosure whether its commands were submitted as a concrete type or as erased
values. Skipping MUST be a property of the derivation itself, not a caller's fallback, and MUST NOT
re-rank the candidates: the first *declaring* command in submission order wins, never the strongest or
most alarming disclosure available in the batch. When no submitted command declares one, the ordinary
package-removal disclosure applies by protocol default. Erasure MUST NOT change, downgrade or discard a
disclosure, and neither MUST the skipping rule: a batch's presented disclosure MUST be identical to the
one its first declaring command presents when submitted alone.

This rule governs the **disclosure** only: it does not disturb the separate typed cleanup evidence a
confirmation may additionally carry, and it does not forbid reading a command's verb for a presentation
concern that is not the disclosure, such as the shipped retitling of a zap confirmation.
(Previously: a batch took the disclosure of its **first submitted command** unconditionally, so a batch
led by a command that declares none — such as the revocation `tap-management` now prepends to every
removal — silently fell back to the package-removal disclosure and downgraded the force-untap warning,
which is the exact defect class this rule was written to prevent.)

#### Scenario: Installing a formula names it as a formula

- GIVEN the formula `wget`
- WHEN an install mutation is built for it
- THEN the argv is exactly `install --formula wget`
- Verification: `unit`

#### Scenario: Installing a cask names it as a cask

- GIVEN the cask `iterm2`
- WHEN an install mutation is built for it
- THEN the argv is exactly `install --cask iterm2`
- Verification: `unit`

#### Scenario: Uninstalling a cask names it as a cask

- GIVEN the installed cask `iterm2`
- WHEN an uninstall mutation is built for it
- THEN the argv is exactly `uninstall --cask iterm2`
- Verification: `unit`

#### Scenario: Reinstall, pin and unpin carry the kind flag too

- GIVEN the installed formula `git`
- WHEN reinstall, pin and unpin mutations are built for it
- THEN their argvs are exactly `reinstall --formula git`, `pin --formula git` and
  `unpin --formula git`
- Verification: `unit`

#### Scenario: A token that exists in both namespaces is never ambiguous

- GIVEN `docker` exists as both a formula and a cask
- WHEN an install mutation is built for the cask `docker`
- THEN the argv contains `--cask` and does not contain `--formula`
- AND the spawned command is the cask install, not the formula install
- Verification: `unit`

#### Scenario: Another family enters the spine without becoming a case of this type

- GIVEN a command belonging to a different capability, submitted through the shared mutation spine
- WHEN this capability's mutating-command type is enumerated
- THEN it still carries exactly the six package commands, with no case for that other command
- AND the submitted command was still projected with its argv, its verb and its terminal outcome
- Verification: `unit`

#### Scenario: An erased mixed batch still discloses the tap add

- GIVEN a batch whose first command is a tap add and whose remaining commands are installs, erased
  to the spine's erased command type before submission
- WHEN it reaches the shared confirmation gate
- THEN the confirmation carries the tap-add disclosure for that tap
- AND it is identical to the disclosure the same tap add presents when submitted unerased
- Verification: `unit`

#### Scenario: An erased install-only batch still discloses package removal

- GIVEN a batch of package mutations only, erased before submission
- WHEN it reaches the shared confirmation gate
- THEN the confirmation carries the ordinary package-removal disclosure
- AND no tap-add, tap-trust-grant or force-untap disclosure is presented
- Verification: `unit`

#### Scenario: A batch led by a non-declaring command still presents the real disclosure

- GIVEN a batch whose first command declares no disclosure of its own and whose second is a force
  untap, submitted both unerased and erased
- WHEN it reaches the shared confirmation gate
- THEN both submissions carry the force-untap affected-package disclosure
- AND neither falls back to the ordinary package-removal disclosure
- Verification: `unit`

#### Scenario: Skipping picks the first declaring command, not the strongest

- GIVEN a batch whose first command declares none, whose second declares the tap-add disclosure, and
  whose third declares the force-untap disclosure
- WHEN it reaches the shared confirmation gate
- THEN the confirmation carries the tap-add disclosure
- AND the derivation did not re-rank the candidates by severity
- Verification: `unit`

#### Scenario: No disclosure is recovered by a type test

- GIVEN every consumer of the shared mutation spine that presents a confirmation
- WHEN the path that produces the disclosure is inspected
- THEN the disclosure is read from the command through the shared abstraction
- AND no downcast, type test, case switch or verb-string inspection produces it
- Verification: `unit`

### Requirement: Uninstall and zap are the only mutations behind a confirmation gate

Within this capability's six package mutations, uninstall and uninstall with `--zap` MUST require an
explicit confirmation before anything is submitted to the queue. The confirmation MUST display the
exact command that will run, matching the operation's argv character for character. Zap MUST be a
separate, separately-confirmed choice and MUST NOT be implied by an ordinary uninstall. Install,
reinstall, upgrade, pin and unpin MUST NOT require confirmation. Declining a confirmation MUST spawn
no process, submit nothing to the queue, and leave the inventory untouched.

A bulk uninstall MUST be confirmed once for the whole selection, and that single confirmation MUST
name every package it will remove — not a count alone and not an elided subset. Confirming it MUST
submit the whole selection; declining it MUST submit none of it, never a partial subset.

The shared confirmation gate MUST additionally carry three typed disclosures owned by `tap-management`:
the **tap-add** disclosure (TM6), the **tap-trust-grant** disclosure (TM13) and the **force-untap**
affected-package disclosure (TM8). Every tap add and every trust grant MUST be confirmed. Plain untap
MUST NOT require confirmation or be made forceful implicitly, and **untrust MUST NOT require
confirmation** — a revocation only reduces authority, so it MUST pass the gate directly and MUST NOT be
presented as a destructive action.

The exact command MUST come from the typed mutation request. Warning text, rendered command text,
package disclosure, and persisted history text MUST never be parsed to construct or modify argv. A
stale force disclosure MUST be rejected before process spawn on the freshness terms of TM8 and MUST
require a new confirmation.
(Previously: the shared gate carried a tap-**trust** disclosure on the tap-add command and a
force-untap disclosure, and named no disclosure for an actual capability grant — because on the shipped
copy, adding a tap was wrongly described as granting trust and no trust command existed.)

#### Scenario: Uninstall asks first and shows the exact command

- GIVEN the installed formula `wget`
- WHEN an uninstall is requested
- THEN a confirmation is requested before anything is submitted
- AND the text it presents contains exactly `brew uninstall --formula wget`
- Verification: `unit`

#### Scenario: Declining spawns nothing

- GIVEN a pending uninstall confirmation
- WHEN it is declined
- THEN no process is spawned and no operation is enqueued
- Verification: `unit`

#### Scenario: Zap is confirmed separately and shows its own command

- GIVEN the installed cask `iterm2`
- WHEN a zap is requested
- THEN a confirmation distinct from the plain uninstall is requested
- AND the command it presents contains `--zap`
- Verification: `unit`

#### Scenario: Non-destructive mutations run without confirmation

- GIVEN the formula `wget`
- WHEN install, upgrade, pin and unpin mutations are requested for it
- THEN no confirmation is requested for any of them
- AND each is submitted to the queue directly
- Verification: `unit`

#### Scenario: A bulk uninstall confirmation names every selected package

- GIVEN a selection of the formulae `wget` and `git` and the cask `iterm2`
- WHEN a bulk uninstall is requested
- THEN exactly one confirmation is requested before anything is submitted
- AND the text it presents names all three packages
- Verification: `unit`

#### Scenario: Declining a bulk uninstall submits none of it

- GIVEN a pending bulk uninstall confirmation over three packages
- WHEN it is declined
- THEN no process is spawned and no operation is enqueued for any of the three
- Verification: `unit`

#### Scenario: Every tap add carries its typed add disclosure

- GIVEN a valid tap-add request
- WHEN it reaches the shared confirmation gate
- THEN confirmation carries the typed tap identity, exact command, and the tap-add disclosure
- AND declining submits nothing
- Verification: `unit`

#### Scenario: Every trust grant is confirmed and carries the grant disclosure

- GIVEN a trust request for the third-party tap `acme/tools`
- WHEN it reaches the shared confirmation gate
- THEN exactly one confirmation is requested before anything is submitted, carrying the tap-trust-grant
  disclosure and the exact command `brew trust acme/tools`
- AND declining spawns no process and enqueues nothing
- Verification: `unit`

#### Scenario: Untrust passes the gate without a confirmation

- GIVEN an untrust request for the third-party tap `acme/tools`
- WHEN it reaches the shared confirmation gate
- THEN no confirmation is requested and it is submitted directly
- AND it is not presented as a destructive action
- Verification: `unit`

#### Scenario: Force untap carries typed complete package disclosure

- GIVEN an eligible force untap affecting formulae and casks
- WHEN it reaches the shared confirmation gate
- THEN every affected package and kind is carried without elision or count-only substitution
- AND plain untap remains a distinct non-force request
- Verification: `unit`

#### Scenario: Stale disclosure and display text cannot become argv

- GIVEN a force disclosure whose affected set changes while open or queued
- WHEN confirmation reaches submission
- THEN it is rejected before spawn and requires a refreshed confirmation
- AND neither display text nor stored text is parsed into a replacement argv
- Verification: `unit`

## ADDED Requirements

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

The refusal MUST NOT be converted into a pre-launch gate. This capability MUST NOT block a mutation
because the package's tap is untrusted: with the tap withheld the inventory cannot prove the origin
tap, and a per-package grant can make brew allow exactly what a tap-state gate would refuse. Only brew
sees both grant kinds, so only brew decides.

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

- Both MODIFIED blocks **replace** their same-named blocks in
  `openspec/specs/package-mutation/spec.md` as whole blocks. PM2, PM4, PM5, PM6, PM7, PM8 and PM9 are
  untouched and stay byte-identical. The ADDED block is appended after PM9.
- **No `## Verification classes` table exists in this spec**, so there is **no class table to
  hand-update at archive**. This delta is the first to annotate `package-mutation` scenarios with an
  inline `- Verification:` line; the annotation travels into the main spec with the promoted blocks,
  and the untouched requirements deliberately keep none.
- **PM1's rolling `(Previously:)` annotation is replaced, not lost**, following the
  one-rolling-note-per-block convention this spec's provenance already records. The `m5-brewfile` note
  it supersedes (the disclosure was recovered by downcast and an erased batch fell back) is preserved
  in the provenance entry for that change; record the new note's substance in this change's entry.
  PM3's annotation is replaced on the same terms.
- Verify the strict-superset claim at archive **by byte-slicing the replaced ranges**, as `m5-brewfile`
  did, rather than by assertion: all nine of PM1's original scenarios and all nine of PM3's are carried
  through with only the tap-trust → tap-add rename and the added `- Verification:` lines.
- Extend the provenance section with: the batch-disclosure resolution (open question 1, default taken
  2026-08-23) and the three alternatives it rejected — reordering the batch (rejected: revocation must
  precede removal), submitting the revocation outside the confirmed batch (rejected: it would run a
  command the sheet never listed), and giving the revocation its own disclosure (rejected: the force
  batch would then lead with revoke copy on a removal confirmation).
- Record that **PM10's prohibition is a rule with a test, not an accident of validation**: the shipped
  `MutationName.isSafe` gate permits `/` and was deliberately **not** widened or narrowed by this change.
  Narrowing it would make every `TapName` unconstructible, because `TapName.init?` is expressed over
  the same gate and a tap name *is* `owner/repo`. The prohibition is therefore an absence assertion
  over the argv surface, together with **D3**'s bare-token strip on the Brewfile path.
- Record the measured facts this requirement consumes so they are not re-derived: the cask refusal's
  exact stderr (obs `#7721`), that a per-package grant restores the `tap` field and unblocks bare-token
  argv (obs `#7724`), and the formula refusal wording, **measured 2026-08-23** (obs `#7738`): `Error: Refusing to load formula agavra/tap/tuicr from untrusted tap agavra/tap.` — it carries the same structural phrase, so the classifier covers formulae and risk R6 is closed.
