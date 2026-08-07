# system-health

This capability owns what Cellar may learn about the *state of the Homebrew installation itself*, and
how honestly it may summarise it: how `brew doctor` is acquired and why its payload rule is the exact
inverse of the three shipped JSON payload sources, what the doctor evidence preserves and counts, how
the age of the local Homebrew checkout is read without invoking brew, what a composite 0–100 score
may and may not claim, and which remediations the dashboard may offer.

Every requirement is behaviour of `CellarCore` values. Naming a SwiftUI view is avoided throughout;
"row", "surface" and "copy" name projected values and their text, not view types.

## Requirements

### Requirement: A non-zero doctor exit is an ordinary outcome, and the document arrives on stderr

The doctor acquisition MUST classify a process that exits non-zero as an **ordinary outcome carrying a
document**, never as a failure and never as an empty document. It MUST NOT throw for a non-zero exit,
and MUST NOT report a machine that merely has warnings as a failed command. It MUST produce exactly
one of three typed outcomes — `clean`, `issues`, `unavailable` — where `unavailable` names only the
cases in which no document could be obtained at all (brew absent, the process could not be spawned, or
it was terminated by a signal), and never the case in which brew answered with warnings.

The document MUST be read from **stderr**. Both raw streams MUST be preserved verbatim and separately
— stdout as stdout, stderr as stderr — and MUST NOT be concatenated, interleaved, trimmed or folded
into one another at any point. A stdout carrying only a newline MUST NOT be treated as an empty or
malformed answer.

The reason is recorded here so a later reader does not repair this as an oversight. `brew-execution`
already requires that "a non-zero status MUST NOT be raised as a thrown error, because `brew` uses
exit codes semantically". This capability exercises that licence rather than contradicting it.
`brew doctor` reports warnings by exiting `1` and writing its entire report to stderr — measured
byte-exactly on a real machine, stdout one byte, the whole payload on stderr — so a rule that says
"non-zero is an error" and "stderr never enters the document" would discard the only output that
matters.

#### Scenario: Warnings exit non-zero and still produce a document

- GIVEN a doctor run that exits `1`, writes a single newline to stdout, and writes a warnings report
  to stderr
- WHEN the acquisition reads it
- THEN the outcome is `issues` carrying the evidence
- AND nothing is thrown, and the document is not empty

#### Scenario: A clean run is clean

- GIVEN a doctor run that exits `0` and reports that the system is ready to brew
- WHEN the acquisition reads it
- THEN the outcome is `clean`
- AND the evidence reports zero warning groups and zero unknown lines

#### Scenario: Both raw streams survive verbatim and unconcatenated

- GIVEN a doctor run whose stdout is one byte and whose stderr is the whole report
- WHEN the outcome is inspected
- THEN the preserved stdout is byte-identical to the process's stdout, and the preserved stderr is
  byte-identical to the process's stderr
- AND no value in the result equals the two joined in either order

#### Scenario: Only an absent answer is unavailable

- GIVEN, respectively, brew absent, a process that cannot be spawned, and a process terminated by a
  signal
- WHEN each is read
- THEN each produces `unavailable` naming its own reason
- AND no warning-carrying run produces `unavailable`, and no `unavailable` case is reported as `clean`

#### Scenario: A newline-only stdout is not malformed

- GIVEN a run that exits `1` with stdout `"\n"` and a non-empty stderr report
- WHEN the acquisition reads it
- THEN the outcome is `issues` carrying the report
- AND no "empty or blank document" refusal is raised

### Requirement: The doctor inversion is quarantined to this capability

Both inversions above MUST apply to the doctor document **only**. The three shipped JSON payload
sources — installed inventory, services and taps — MUST continue to refuse a non-zero exit and MUST
continue to admit stdout only. A doctor-shaped relaxation MUST NOT reach them, and the doctor source
MUST NOT be re-derived from their template.

The separation MUST be enforced structurally rather than by convention or by review: a test MUST
assert **both halves** — that the trio still rejects a non-zero exit and still reads only stdout, and
that the doctor source accepts a non-zero exit and reads stderr — so a "simplification" in either
direction fails a test rather than a review.

#### Scenario: The JSON trio still rejects a non-zero exit

- GIVEN each of the three JSON payload sources, and a process that exits non-zero while writing a
  well-formed JSON body
- WHEN each decodes it
- THEN each reports a command failure and none returns a document

#### Scenario: The JSON trio still admits stdout only

- GIVEN each of the three JSON payload sources, and a process that exits `0` with an empty stdout and
  a well-formed JSON body on stderr
- WHEN each decodes it
- THEN each treats the document as absent or malformed
- AND none of them reads the body from stderr

#### Scenario: The guard asserts the quarantine in both directions

- GIVEN the structural guard for this rule
- WHEN it runs
- THEN it asserts the trio's two refusals and the doctor source's two acceptances
- AND it cannot pass if the doctor source is changed to reject a non-zero exit or to read stdout only

### Requirement: Doctor evidence preserves every byte and counts every line it cannot group

The evidence MUST carry the raw stdout and raw stderr bytes verbatim, a counted grouping of the
report's warning blocks with each block's detail lines attached to it, the lines the grouping did not
recognise held as **bytes rather than decoded text**, a set of typed parse issues, a partial flag, and
the provenance of the parser that produced it. Undecodable bytes MUST survive; a line MUST NOT be
dropped, substituted or lossily decoded because it could not be read as text.

Every line of the document MUST be accounted for: a line either belongs to a group or is counted as
unknown. The unknown count MUST be reported as `0` rather than as absent when nothing was unknown, so
"nothing was unknown" and "nothing was measured" remain distinguishable. The grouping MUST be a
projection over the preserved bytes: re-reading the raw stderr MUST always be possible and MUST NOT be
affected by what the grouping recognised.

An unrecognised report MUST NOT fail the acquisition. It MUST yield evidence whose groups are empty,
whose unknown lines are the whole document, and whose partial flag is set.

The evidence MUST be derivable from bytes alone: producing it MUST NOT require a process, a clock or a
store, so every rule above is testable from a fixture.

#### Scenario: A grouped report counts its groups and keeps their details

- GIVEN a stderr report carrying a preamble and two warning blocks, each with indented detail lines
- WHEN the evidence is built
- THEN it reports exactly two groups
- AND each group carries its own detail lines in the order they appeared

#### Scenario: An unrecognised line is counted, never dropped

- GIVEN the same report with one line the grouping does not recognise
- WHEN the evidence is built
- THEN that line is present in the unknown lines, byte-identical to its input
- AND the grouped lines and the unknown lines together account for the whole document

#### Scenario: A clean run reports zero unknown lines, present rather than absent

- GIVEN a clean doctor document
- WHEN the evidence is built
- THEN the unknown-line count is `0` and is present
- AND it is distinguishable from a document that was never parsed

#### Scenario: Undecodable bytes survive

- GIVEN a report containing a line that is not valid UTF-8
- WHEN the evidence is built
- THEN that line is carried as bytes among the unknown lines, with no replacement character
  substituted
- AND the preserved raw stderr is still byte-identical to the input

#### Scenario: A wholly unrecognised report is partial, not a failure

- GIVEN a report whose shape the grouping does not recognise at all, from a run that exited non-zero
- WHEN the acquisition reads it
- THEN it still reports `issues` carrying evidence
- AND the evidence has no groups, carries the whole document among its unknown lines, and is flagged
  partial

#### Scenario: The same bytes always produce the same evidence

- GIVEN two byte-identical doctor captures
- WHEN evidence is built from each, with no process, clock or store available
- THEN the two evidence values are equal, including their groups, their counts and their parser
  provenance

### Requirement: Doctor is a read, and running it fixes nothing

The doctor acquisition MUST be classified as a **read**. It MUST NOT be submitted as a mutation, MUST
NOT write a history entry, MUST NOT invalidate installed state, and MUST NOT trigger an update of
Homebrew itself. Running it MUST leave the Homebrew installation unchanged — in particular the fetch
marker this capability reads for the last-update answer MUST NOT move because doctor ran.

Any surface that offers to run doctor MUST say that it **re-measures**, and MUST NOT claim, imply or
promise that it repairs anything. `brew doctor` has no fix mode, and Homebrew's own manual
de-emphasises the output — the warnings exist to help Homebrew's maintainers debug a reported issue —
so copy that presents them as defects the user must fix overstates them.

#### Scenario: Doctor is classified as a read

- GIVEN the doctor acquisition's declared classification
- WHEN it is inspected
- THEN it is a read
- AND no path submits it as a mutation

#### Scenario: Running doctor writes no history and invalidates nothing

- GIVEN a recording operation queue and a recording history store
- WHEN doctor is run twice
- THEN no operation was submitted and no history entry was written
- AND no installed-state invalidation was raised

#### Scenario: Running doctor does not move the last-update reading

- GIVEN the last-update reading taken before a doctor run
- WHEN doctor runs and the reading is taken again
- THEN it is unchanged

#### Scenario: The run-doctor copy claims no repair

- GIVEN the copy offered for the run-doctor remediation
- WHEN it is read
- THEN it states that the action re-measures
- AND it contains no claim that it fixes, repairs or resolves anything

### Requirement: The last-update reading costs no brew invocation

The age of the local Homebrew checkout MUST be read from the checkout's own fetch marker, and the
checkout MUST be located by probing the filesystem, **never** by invoking brew. Resolution MUST try
`<prefix>/Homebrew/.git` first and `<prefix>/.git` second, in that order, so both supported
installation shapes resolve — the shape where the repository is nested under the prefix, and the shape
where the repository is the prefix. The first probe that resolves MUST win, and a probe that does not
resolve MUST NOT be reported as an error.

Taking the reading MUST spawn no process of any kind, MUST issue no network request, and MUST NOT
trigger, schedule or permit an update of Homebrew as a side effect of asking how old it is. The
filesystem access MUST go through a narrow seam, so every rule here is testable without a real
Homebrew installation.

#### Scenario: The nested-repository shape resolves

- GIVEN a prefix under which `Homebrew/.git` exists
- WHEN the checkout is resolved
- THEN it resolves to that path

#### Scenario: The repository-equals-prefix shape resolves

- GIVEN a prefix under which `Homebrew` does not exist and `.git` does
- WHEN the checkout is resolved
- THEN it resolves to `<prefix>/.git`

#### Scenario: The first probe wins

- GIVEN a prefix under which both candidate paths exist
- WHEN the checkout is resolved
- THEN it resolves to `<prefix>/Homebrew/.git`
- AND the second candidate is not read

#### Scenario: Resolution and reading spawn nothing

- GIVEN a recording process launcher and a recording network seam
- WHEN the checkout is resolved and the reading taken on both installation shapes
- THEN no process was spawned and no network request was issued
- AND no Homebrew update was triggered or scheduled

### Requirement: The last-update reading is a typed answer and never an invented date

The reading MUST answer with one of four typed cases: **read**, carrying the fetch marker's
modification date; **absent**, when no checkout or no marker could be found; **unreadable**, when it
exists but its metadata could not be read; and **future-dated**, when the marker's date is later than
the moment the reading was taken. It MUST NOT substitute a placeholder date, a distant-past date, a
zero date or a negative age for any non-answer, and MUST NOT throw.

An age MUST be derived only from a `read` value. Absent, unreadable and future-dated MUST reach every
consumer as themselves — including the score, which MUST treat each as unanswered rather than as fresh
or as stale. A future-dated marker MUST be its own case rather than clamped to zero, because clamping
would render a wrong clock as a perfectly fresh installation.

#### Scenario: A present marker reads its date

- GIVEN a resolved checkout whose fetch marker carries a known modification date
- WHEN the reading is taken
- THEN it reports `read` carrying exactly that date

#### Scenario: A missing marker is absent, not old

- GIVEN a resolved checkout whose fetch marker does not exist
- WHEN the reading is taken
- THEN it reports `absent`
- AND no date and no age is produced

#### Scenario: An unreadable marker is its own case

- GIVEN a fetch marker that exists but whose metadata cannot be read
- WHEN the reading is taken
- THEN it reports `unreadable`, distinguishable from `absent`
- AND nothing is thrown

#### Scenario: A future-dated marker is not clamped

- GIVEN a fetch marker dated after the moment the reading is taken
- WHEN the reading is taken
- THEN it reports `future-dated` carrying the offending date
- AND no zero age and no "just updated" reading is produced

#### Scenario: Non-answers never become fresh

- GIVEN each of `absent`, `unreadable` and `future-dated`
- WHEN each reaches the score
- THEN each is recorded as an unanswered input
- AND none contributes a fresh or a stale value to the number

### Requirement: Health is a projection over resident state and acquires nothing to render

The health view MUST be a pure projection over values the app already holds — the installed inventory
and its snooze-narrowed outdated set, security coverage, cleanup orphans, disk usage — plus this
capability's two own readings. Building it MUST NOT issue a brew invocation, MUST NOT spawn any
process, MUST NOT trigger a catalog sync, a security scan, a disk-usage measurement or an inventory
refresh, and MUST NOT start a polling loop or a timer.

This capability MUST own exactly two acquisitions — the doctor run and the last-update reading — and
the doctor run MUST be user-initiated rather than performed because the section was rendered.

A signal that has not been measured yet MUST be projected as unmeasured. It MUST NOT be substituted
with a computed default, and it MUST NOT be obtained by triggering the measurement that would answer
it.

The projection MUST be computable off the main actor from its inputs alone, so it is testable with no
store, no clock and no process.

#### Scenario: Building the projection issues no request

- GIVEN a recording process launcher, recording refresh seams, and resident values for every signal
- WHEN the health projection is built
- THEN no process was spawned, and no sync, scan, measurement or inventory refresh was triggered
- AND no timer or polling loop was started

#### Scenario: An unmeasured signal stays unmeasured

- GIVEN resident state in which disk usage has never been measured
- WHEN the projection is built
- THEN the disk row reports unmeasured
- AND no disk-usage measurement was started

#### Scenario: Doctor runs only when asked

- GIVEN resident state carrying no doctor evidence
- WHEN the projection is built and read
- THEN the doctor row reports that doctor has not been run, and no doctor process was spawned
- AND a doctor process is spawned only when the run action is invoked

#### Scenario: The projection is a function of its inputs

- GIVEN two identical input sets
- WHEN the projection is built from each with no store and no clock available
- THEN the two projections are equal

### Requirement: Every row states what it does not know

The dashboard MUST project seven rows — outdated packages, vulnerable packages, orphaned dependencies,
duplicate installed versions, cache size, Homebrew's own staleness, and the doctor result — and every
row MUST be able to report an unknown, unmeasured, partial or unavailable state **as itself**.

A row MUST NOT render a count of zero for a signal nobody could answer for. Specifically: security
coverage that is not covered, unavailable or partial MUST NOT render as "0 vulnerable"; unknown
orphans MUST NOT render as "0 orphans"; an incomplete disk measurement or a failed disk root MUST NOT
render as a complete size; and an absent, unreadable or future-dated last-update reading MUST NOT
render as an age. Each such row MUST name the reason it cannot answer.

A row whose signal is partially answered MUST report both what it answered and what it could not,
rather than reporting only the answered part.

#### Scenario: An uncovered inventory is not zero vulnerabilities

- GIVEN coverage in which no package is covered and none is known vulnerable
- WHEN the vulnerability row is projected
- THEN it reports that the inventory is not covered, naming that as the reason
- AND it does not report "0 vulnerable"

#### Scenario: Unknown orphans are not zero orphans

- GIVEN cleanup orphans in the unknown state
- WHEN the orphan row is projected
- THEN it reports that orphans could not be determined
- AND it does not report a count of zero

#### Scenario: An incomplete disk measurement names its gap

- GIVEN a disk snapshot that is not complete and that carries one failed area
- WHEN the duplicate-versions and cache rows are projected
- THEN each reports the measurement as incomplete and names the failed area
- AND no total is presented as complete

#### Scenario: An absent last-update reading is not an age

- GIVEN a last-update reading of `absent`
- WHEN the staleness row is projected
- THEN it reports that the checkout's age could not be read
- AND it presents no age, no date and no freshness verdict

#### Scenario: A partially answered scan reports both halves

- GIVEN a security scan that answered part of the inventory and left the rest unanswered
- WHEN the vulnerability row is projected
- THEN it reports the answered result and the unanswered remainder
- AND it does not present the answered result as covering the whole inventory

### Requirement: The score is computed over answered inputs only, and its unknowns are inseparable from it

The composite score MUST be a **pure function** of a single inputs value. Its signature MUST NOT
accept, and its implementation MUST NOT reach, a store, a clock, the filesystem, the network or a
subprocess. The same inputs MUST always produce the same score.

The score MUST be computed over **answered inputs only**. An input that is not covered, unavailable,
unknown, partial, unmeasured or otherwise unanswered MUST NOT contribute to the number in either
direction: it MUST NOT be scored as clean, and it MUST NOT be scored as a penalty. Every such input
MUST instead be recorded in the score's set of unknown inputs, naming which input was unanswered.

That set MUST be **structurally inseparable** from the number: the score value MUST be unrepresentable
without it, so no surface can render the number while dropping the caveat. A score computed over any
unanswered input MUST NOT be reported as clean or complete, however few the unknowns — including a
number of 100.

The number MUST be a value from 0 to 100 inclusive. Inputs in which nothing at all was answered MUST
report that nothing could be scored, rather than presenting `0` or `100` as a verdict.

#### Scenario: Every unknown state is unanswered, never clean

- GIVEN inputs whose security coverage is, in turn, not covered, unavailable and partial; whose
  orphans are unknown; whose disk measurement is incomplete; and whose last-update reading is absent
- WHEN the score is computed for each
- THEN each result names that input in its unknown set
- AND in no case does that input contribute a clean value to the number

#### Scenario: An unknown penalises nothing either

- GIVEN two input sets identical except that one signal is answered clean in the first and unanswered
  in the second
- WHEN both are scored
- THEN the unanswered signal contributes neither a penalty nor a credit, and the number is derived
  over the answered inputs only
- AND the two results differ in their unknown sets rather than by an invented deduction

#### Scenario: The number cannot be obtained without its unknowns

- GIVEN the score value type
- WHEN every way to construct the value and every way to read the number is enumerated
- THEN each one carries the unknown-input set with it
- AND no constructor, projection or accessor yields the number alone

#### Scenario: A perfect number over incomplete inputs is not clean

- GIVEN inputs in which every answered signal is clean and one signal is unanswered
- WHEN the score is computed
- THEN the number may be 100
- AND the result is not reported as clean or complete, and it names the unanswered input

#### Scenario: Nothing answered is not a verdict

- GIVEN inputs in which no signal is answered
- WHEN the score is computed
- THEN the result reports that nothing could be scored and names every input as unknown
- AND it does not present `0` or `100` as a health verdict

#### Scenario: The score function reaches no I/O

- GIVEN the score function's signature and its declared dependencies
- WHEN they are enumerated
- THEN none is a store, a clock, a filesystem, a network or a process seam
- AND the function is computable in a test with none of them available

#### Scenario: The number is bounded

- GIVEN any inputs value that answers at least one signal
- WHEN it is scored
- THEN the number is between 0 and 100 inclusive

### Requirement: Every weight is visible in the breakdown

The score MUST carry a breakdown of contributions. Each contribution MUST name the input it came from,
the weight applied to it, and the penalty or credit that resulted. The weights MUST be readable from
the value itself rather than being implicit in the arithmetic, so the number is arguable and
falsifiable rather than authoritative. The contributions MUST account for the reported number by the
stated rule, so a breakdown that does not explain its number is detectable.

Doctor MUST be weighted lightly relative to the signals that describe the user's own packages, because
Homebrew's own manual states that its warnings exist to help Homebrew's maintainers debug a reported
issue. That weight MUST be visible like every other, not hidden in the rule.

An input recorded as unknown MUST NOT appear in the breakdown as a weighted contribution; it belongs
to the unknown set.

#### Scenario: Each contribution names its input, weight and effect

- GIVEN a score computed over several answered inputs
- WHEN the breakdown is read
- THEN each entry names its input, the weight applied and the resulting penalty or credit

#### Scenario: The breakdown accounts for the number

- GIVEN a score with two or more contributions
- WHEN the contributions are recombined by the stated rule
- THEN the result equals the reported number

#### Scenario: Unknown inputs are not contributions

- GIVEN inputs with one unanswered signal
- WHEN the breakdown and the unknown set are read
- THEN no contribution names that signal
- AND the unknown set does

#### Scenario: The doctor weight is visible and light

- GIVEN inputs carrying both doctor warnings and outdated packages
- WHEN the breakdown is read
- THEN the doctor contribution's weight is readable
- AND it is lower than the weight applied to the user's own outdated packages

### Requirement: Remediation offers only verbs the app already ships

A row that has a remediation MUST offer it from the row that motivated it, and MUST offer only verbs
already shipped by other capabilities: upgrade-all for outdated packages, autoremove for orphaned
dependencies, cleanup for reclaimable disk, and a re-run of the doctor measurement. This capability
MUST NOT introduce a new mutating verb, MUST NOT introduce an update of Homebrew itself as a
remediation, and MUST NOT offer a repair for a doctor warning.

A remediation MUST travel the same spine, the same confirmation rules and the same activity reporting
as the surface that already owns it; a remediation offered here MUST NOT bypass a confirmation the
owning capability requires, nor present a weaker disclosure. A row with no remediation MUST offer
none, rather than an inert control.

#### Scenario: Each remediation submits the verb its owner already ships

- GIVEN the outdated, orphan and disk rows
- WHEN each remediation is invoked
- THEN the submitted operations are exactly the shipped upgrade-all, autoremove and cleanup commands
- AND no new command type was constructed for this capability

#### Scenario: No new verb and no Homebrew update

- GIVEN this capability's remediation vocabulary
- WHEN it is enumerated
- THEN every entry names a verb another capability already owns
- AND none of them updates Homebrew itself, and none of them claims to fix a doctor warning

#### Scenario: A remediation keeps its owner's confirmation

- GIVEN a remediation whose owning capability requires a confirmation
- WHEN it is invoked from a health row
- THEN the same confirmation is presented, carrying the same disclosure it presents on its own surface

#### Scenario: A row without a remediation offers no control

- GIVEN the vulnerability row and the staleness row
- WHEN their controls are enumerated
- THEN neither offers a remediation control
- AND no disabled or inert control is presented in its place

## Provenance

- **The doctor exit-code rule is licensed by `brew-execution`, not a contradiction of it.**
  `openspec/specs/brew-execution/spec.md`, *Terminal result and exit handling*, already requires: "A
  process that exits — successfully or not — MUST be reported as a `BrewExit` **value** carrying the
  exit status and a reason of `exited`; **a non-zero status MUST NOT be raised as a thrown error,
  because `brew` uses exit codes semantically.**" The "non-zero is a failure" rule lives one layer
  above, in the three JSON payload sources, each of which adopted it for its own document reasons.
  `brew-execution` is therefore **not modified** by this change (decision **D7**), and this
  capability records the licence instead of editing a shipped main spec unnecessarily.
- **Probe measurements this capability is written against** (Engram `#7531`, 2026-08-07, this
  machine, Homebrew 6.0.x):
  - **U10** — `brew doctor` with real warnings present: exit `1` on both runs; **stdout one byte (a
    bare newline), the entire 622-byte payload on stderr**; byte-identical across two consecutive
    runs; 2–3 s elapsed. The byte-stability is what makes the counted grouping sufficient and makes
    per-check attribution via `--list-checks` unnecessary. The **clean-case fixture cannot be
    captured on this machine** and MUST be hand-authored and visibly marked as authored rather than
    captured, per the fixtures standard.
  - **U11** — probe-order resolution validated on both installation shapes; `brew --repository`
    equals the prefix on Apple Silicon; resolution is invocation-free.
  - **U12** — the fetch marker moved with a real auto-update in the same session, alongside the API
    cache: it is the authoritative last-update artefact, not a heuristic Cellar invented. Homebrew's
    own `auto-update.sh` stats the same file.
  - **U14** — the fetch marker's modification date was identical before and after two doctor runs
    under Cellar's pinned no-auto-update environment, which is why doctor is classified as a read.
- **Binding decisions** (maintainer, Engram `#7532`): **D3** the score is answered-inputs-only with
  structurally inseparable unknowns — a weighted deduction over unknowns was rejected because an
  unknown would then either flatter or punish the user, and both are lies; a graded status with no
  number was rejected because PRD §3.4 states 0–100 explicitly. **D4** health is a tenth section
  between services and security and Home stays — carried by `tasks.md`, not by a requirement here,
  per the recorded precedent for app-side placement decisions. **D5/D6** doctor is raw **and**
  grouped. Score weights are proposed by design and reviewed with the design summary; the
  transparency rules above are what keep them arguable.
- **`CoverageTotals`' own doc comment is the reason for the no-unknown-counts-as-clean rule**: it
  exists because "the summary can still read '0 vulnerabilities' over an inventory nobody could
  answer for". A single number is the one surface where a user cannot see that substitution, which is
  why the rule is a requirement here rather than a convention.
- Established by change `m5-health` (archived `2026-08-07`, PRD milestone **M5** "Pro-parity flows",
  slice 5 of 5 — the slice that **closed M5**), ADDED-only delta — **11 requirements / 51
  scenarios**, promoted from
  `openspec/changes/archive/2026-08-07-m5-health/specs/system-health/spec.md`. This is the first main
  spec for the capability; nothing was modified, removed or renamed *here*. The same change did
  modify two other main specs — `installed-inventory` (II13/II14, **destructive**) and
  `local-package-metadata` (LPM4/LPM5, strict supersets) — each recorded in its own Provenance. This
  file adds the header, the `## Requirements` wrapper and this entry; the requirement and scenario
  bodies, and every Provenance entry above this one, are byte-identical to the delta's.
- Traceability to the change's binding decisions, relocated verbatim from the delta's header so it
  survives the promotion: **D1/D2** are `installed-inventory` and `local-package-metadata` deltas,
  not this file. **D3** → "The score is computed over answered inputs only, and its unknowns are
  inseparable from it" and "Every weight is visible in the breakdown". **D4** — the tenth
  `AppSection` case and the resolution of the deferred question at `cellar/Shell/AppSection.swift`
  — is an **app-side placement decision with no `CellarCore` behaviour**, so it is carried by that
  change's `tasks.md` and deliberately **not** by a requirement here, exactly as
  `brewfile-management` carried its own D3 and `release-notes` its D4. Recorded so a later reader
  does not read its absence as a gap. **D5/D6** → "A non-zero doctor exit is an ordinary outcome,
  and the document arrives on stderr" and "Doctor evidence preserves every byte and counts every
  line it cannot group" — raw **and** grouped, the only reading that satisfies both PRD §3.4 and
  §9 Q5. **D7** → "The doctor inversion is quarantined to this capability", plus the licence entry
  above; `openspec/specs/brew-execution/spec.md` was deliberately **not** modified and measured a
  0-line diff at delivery.
- **Correction to D4, ruled by the maintainer during apply (finding F13, Engram `#7532`).** Both the
  delta header and the "Binding decisions" entry above say Home "stays"; that is true and remains
  true — Home is still a section. What was **never** true is the accompanying claim that Home is the
  *landing* section. **`Browse` has been the landing section since M1**, and the shipped tests pin
  `.browse` literally. The corrected record is: Home remains a section, Browse remains the landing,
  and `.health` did not take the landing spot. The stale comment that asserted otherwise in
  `cellar/Shell/AppSection.swift` was corrected under a real RED→GREEN cycle. Read every "Home
  stays" above with this correction applied.
