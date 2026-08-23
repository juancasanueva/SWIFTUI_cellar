# Delta for brewfile-management

Existing capability — `openspec/specs/brewfile-management/spec.md` (**9 requirements / 38 scenarios**,
established by the archived `2026-08-07-m5-brewfile`). This delta is **2 MODIFIED, 0 added, 0 removed,
0 renamed**: **11 scenarios** replace the 9 the two modified blocks carry today, taking the capability
to **9 requirements / 40 scenarios**.

Nothing is removed and no requirement is renamed, so `rules.archive`'s destructive-delta warning does
not fire. Both MODIFIED blocks are whole-block replacements copied from the main spec and then edited.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m7-tap-trust/` + Engram canonical project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

**This delta carries D3 and the D2 rename.** The rename (**D2**: `ConfirmationDisclosure.tapTrust`
→ `.tapAdd`) reaches the two requirements that name the case in prose, plus one restatement each: BF5
says in the new vocabulary what it already said — a `trusted:` option confers nothing, and now that
trust is a real grantable command, "confers nothing" MUST include "submits no trust command"; BF7
restates the batch-disclosure sentence in `package-mutation` PM1's amended wording so the two cannot
drift. Homebrew 6 making trust a genuine capability makes BF5's reasoning **stronger**, not weaker: the
claim is made by the *file's author*, who is exactly the party a trust decision must not be delegated
to. **D3** adds the one new rule this delta carries: a `/`-qualified package entry is applied by its
**bare token**, because Homebrew 6 treats naming a qualified package on the command line as a
per-package grant, so forwarding the file's token verbatim would let its author grant trust on the
importing user's Mac. `BrewfilePlan` still emits a tap add for a tap entry and an install for a package
entry, and nothing else.

## Verification classes — with the runner named per class

Every scenario below declares exactly one verification class.

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable CellarCore behaviour, per `config.yaml` `rules.specs` | `swift test --package-path Packages/CellarCore` by default; `xcodebuild test -project cellar.xcodeproj -scheme cellar -destination 'platform=macOS,arch=arm64' -only-testing:cellarTests` for the app-target composition scenarios, which raise a confirmation from a view model | **11** |

No scenario in this delta needs `manual-evidence`: nothing here depends on a real grant being written by
a real `brew`.

## MODIFIED Requirements

### Requirement: `trusted:` is parsed, surfaced, and confers nothing

`trusted: true` and `trusted: { formula: ..., casks: [...], commands: [...] }` MUST be recognised as
grammar wherever a dump can emit them, so the option can never corrupt the parsing of the line it
appears on and can never be mistaken for a name.

A recognised `trusted:` option MUST be surfaced to the user as a **claim made by whoever authored
the file**, attributed to the file rather than to Homebrew, to the tap, or to Cellar. It MUST NOT be
silently discarded from the presentation, because it is security-relevant content.

It MUST confer nothing. No tap trust MUST be recorded, **no trust command MUST be submitted**, no
confirmation MUST be suppressed or downgraded, no disclosure MUST be shortened, and no argv MUST carry
`trusted`, `--trusted` or any flag or command derived from the option. A tap named by a `trusted:`
option MUST still raise the shipped `ConfirmationDisclosure.tapAdd` when it is applied, on exactly the
same terms as a tap that carried no such option.

A package entry whose name is `/`-qualified MUST still parse as an ordinary entry with no skip counted,
and the command applied for it MUST name the **bare token** brew installs by, with the qualifier
removed. Homebrew 6 treats naming a qualified package on the command line as a per-package grant, so
forwarding the file's qualified token as argv would let the file's author grant trust on the importing
user's Mac — the delegation this requirement already refuses. When that tap is untrusted, brew refuses
and `package-mutation` PM10's typed outcome offers the grant as an explicit answer.

Homebrew 6 turning trust into a genuinely grantable capability strengthens this rule rather than
weakening it: honouring the option would turn a Brewfile import into a way for a file's author to have
arbitrary code trusted on someone else's Mac, and that author is exactly the party a trust decision
must not be delegated to.
(Previously: the rule named `ConfirmationDisclosure.tapTrust`, a case whose name asserted a grant the
tap-add command never made; its prohibition was written over flags only, because no trust command
existed to forbid; and nothing governed the qualified token a package line could carry into argv, which
Homebrew 6 reads as a per-package grant.)

#### Scenario: A trusted tap still raises the tap-add disclosure

- GIVEN an imported Brewfile whose only entry is `tap "acme/tap", trusted: { casks: ["thing"] }`,
  selected for apply
- WHEN the batch reaches the shared confirmation gate
- THEN exactly one confirmation is raised, carrying the `tapAdd` disclosure for `acme/tap`
- AND the disclosure text is identical to the one raised for a tap that carried no `trusted:` option
- Verification: `unit`

#### Scenario: `trusted:` never becomes argv

- GIVEN the same entry, confirmed and submitted
- WHEN the spawned argv is inspected
- THEN it is exactly the shipped tap-add argv for `acme/tap`
- AND it contains no `trusted` token and no flag derived from the option
- Verification: `unit`

#### Scenario: An import submits no trust command

- GIVEN an imported Brewfile carrying `trusted:` options on a tap line, a brew line and a cask line,
  all selected and confirmed
- WHEN every command the batch submits is enumerated
- THEN none of them is a trust command
- AND no tap's trust state was changed by the import
- Verification: `unit`

#### Scenario: The claim is surfaced, attributed to the file

- GIVEN a parsed entry carrying a `trusted:` option
- WHEN the entry is projected for presentation
- THEN the option is present in the projection, attributed to the imported file's author
- AND the projection makes no claim that Homebrew, the tap or Cellar has granted trust
- Verification: `unit`

#### Scenario: `trusted:` on a brew or cask line parses and confers nothing

- GIVEN the lines `brew "acme/tap/thing", trusted: true` and `cask "acme/tap/app", trusted: true`
- WHEN they are parsed
- THEN each produces one ordinary package entry with no skip counted
- AND neither entry records any trust grant
- Verification: `unit`

#### Scenario: A qualified package entry installs the bare token

- GIVEN the selected entry `brew "acme/tap/thing"`
- WHEN the plan builds its command for that entry
- THEN the argv it will spawn names `thing` and never `acme/tap/thing`
- AND the import row shows the bare token it will install, with the file's qualified name as its detail
- Verification: `unit`

### Requirement: A selection becomes existing typed mutations, and nothing else is submitted

Applying a selection MUST expand into one **existing** typed command per selected entry: a tap add
for a tap entry, and an install for a formula or cask entry, each naming exactly one subject with
its explicit kind flag. No generated argv MUST name more than one package. The install MUST name the
entry's bare token; a selected package entry whose qualified name has no constructible bare token MUST
produce no command and MUST NOT be presented as applied. This capability MUST NOT introduce a new
mutating command family, a new case of `package-mutation`'s command type, or a new invalidation domain.

The plan MUST contain a command for every selected entry and for no other line: a deselected entry,
a present entry and a skipped entry MUST never appear in it. Selected taps MUST be ordered before
selected installs, for two independent reasons: a package from a newly added tap must not be
attempted before its tap exists, **and** the shared confirmation gate derives the batch's disclosure
from its first command **that declares one of its own**, so a tap-carrying batch presents the tap-add
disclosure only when a tap leads it. An install declares no disclosure of its own, so an
install-leading batch would present the ordinary package-removal disclosure. The ordering rule is
therefore load-bearing for the disclosure this capability requires, not merely for install sequencing,
and it MUST hold even for a batch whose only tap was selected last.

The batch MUST be submitted through the shared mutation spine, inheriting per-entry queue item,
streamed log, copy-command, cancel, terminal outcome, exactly one history entry per terminal
outcome, and scoped invalidation. A batch containing at least one tap MUST raise exactly **one**
confirmation carrying the `tapAdd` disclosure; confirming it MUST submit the whole batch and
declining it MUST submit none of it. Nothing MUST be submitted without an explicit selection.
(Previously: the rule named the `tapTrust` disclosure — a case whose name asserted a grant the tap-add
command never made — stated the gate's derivation as "the first submitted command's disclosure",
wording `package-mutation` PM1 has since amended, and let an install name whatever token its entry
carried, including a `/`-qualified one.)

#### Scenario: A mixed selection fans out, taps first

- GIVEN a selection of the tap `acme/tap` and the missing formulae `wget` and `git`, in that order
- WHEN the plan is built
- THEN exactly three operations are enqueued, the tap add first, then `install --formula wget` and
  `install --formula git`
- AND no argv names more than one subject
- Verification: `unit`

#### Scenario: Only selected entries are submitted

- GIVEN a projection with two missing entries where one is deselected, one present entry and two
  skipped entries
- WHEN the plan is built and submitted
- THEN exactly one operation is enqueued, for the entry that stayed selected
- AND no operation exists for the deselected, present or skipped entries
- Verification: `unit`

#### Scenario: One confirmation covers the batch, and declining submits nothing

- GIVEN a selection containing one tap and two installs, with the tap selected **last**
- WHEN it is submitted
- THEN exactly one confirmation is requested, carrying the `tapAdd` disclosure, before anything is
  enqueued
- AND the disclosure is the same one an unerased tap-add would have presented
- AND declining it spawns no process and enqueues nothing for any of the three
- Verification: `unit`

#### Scenario: An empty selection submits nothing

- GIVEN a projected diff with every entry deselected
- WHEN apply is requested
- THEN no confirmation is raised, no operation is enqueued and no process is spawned
- Verification: `unit`

#### Scenario: A mid-batch failure attributes to one entry

- GIVEN a confirmed batch of three entries where the second exits non-zero
- WHEN all three reach their terminal outcomes
- THEN the failure is reported against the second entry only
- AND the third still ran, and exactly one history entry exists per terminal outcome
- Verification: `unit`

## Notes for archive

- Both MODIFIED blocks **replace** their same-named blocks in
  `openspec/specs/brewfile-management/spec.md` as whole blocks. The other seven requirements are
  untouched and stay byte-identical.
- **No `## Verification classes` table exists in this spec**, so there is **no class table to
  hand-update at archive**. This delta is the first to annotate `brewfile-management` scenarios with an
  inline `- Verification:` line; the untouched requirements deliberately keep none.
- **Confirm no other occurrence of `tapTrust` survives — with two known out-of-block hits.** The
  proposal enumerates the case name inside the MODIFIED blocks. Verify (W2) found two further mentions
  that sit **outside** both blocks and therefore survive a *correct* promotion: the main spec's header
  prose (~:7) and the Provenance D4 entry (~:510). `sdd-archive` MUST hand-edit both; after that,
  `rg 'tapTrust'` across `openspec/specs/` MUST return zero hits. A hit at those two places is not a
  partial promotion; a hit anywhere else is.
- Record in the provenance section that the rename is **D2** and that **D3** is the one new rule:
  `trusted:` remains informational, and a `/`-qualified package entry is applied by its bare token so
  the file's author cannot grant per-package trust through argv. **`BrewfilePlan.swift` does change**
  (its install arm) and is **no longer** a 0-line binding; `MutationCommand.swift` is the 0-line
  binding now, because D3 adds no `/` gate to `MutationName.isSafe` or `PackageTarget.init?`. Record
  the rejected alternatives with it: a carve-out for user-authored qualified names, and refusing
  qualified lines as skips.
- Record that BF7's ordering rule is now coupled to `package-mutation` PM1's **amended** derivation
  ("the first command that declares one of its own"). A Brewfile batch is always led by a tap add,
  which declares its own disclosure, so the amendment leaves this capability's behaviour unchanged —
  but the two sentences must be promoted in the same archive so they cannot drift, exactly as
  `m5-brewfile` recorded for their first coupling.
