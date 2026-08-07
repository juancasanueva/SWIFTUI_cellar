# Delta for brewfile-management

New capability — there is no `openspec/specs/brewfile-management/spec.md` yet, so this delta is
**ADDED-only**: **9 requirements / 38 scenarios**. Nothing is MODIFIED, REMOVED or RENAMED.

**Amended after design** (`design.md`, Engram obs 7523). Design verified the proposal's confirmation
claim against shipped source and found it false: `OperationCenterBulk.swift:141` resolves the
disclosure by downcasting — `(first as? TapCommand)?.disclosure ?? .packageRemoval` — and
`AnyBrewMutation` does not carry `disclosure`, so an **erased** mixed tap+install batch would have
presented the package-removal disclosure and silently defeated the tapTrust requirement below.
Design decision **DD1** repairs the spine; the corresponding rule is specified in this change's
`package-mutation` delta, and the tap-before-install ordering rule below is now load-bearing for
disclosure selection as well as for install sequencing.

This capability owns what Cellar may read out of a Brewfile, what it may never do with one, and what
it may write. Specifically: the accepted grammar and its refusal rules, the typed entry model, the
skip taxonomy and its counting rule, the offline diff projection and its selectability rules, the
selection-to-mutation plan, the dump-to-temp acquisition and its exit/stream contract, atomic
publication to the user's destination, and every security invariant the proposal binds. Every
requirement is behaviour of `CellarCore` values; no SwiftUI view is specified anywhere in this file.
Where the text says "an imported Brewfile", it means one file the user supplied by an explicit
action — the presentation that carries the action is not specified here.

**Why the security invariants are requirements and not comments.** Probe U8 (2026-08-07, Homebrew
6.x on the maintainer's machine) established as fact, not inference, that
`brew bundle check --file <path>` **evaluates** the Brewfile's Ruby: a Brewfile whose only content
was `File.write(".../marker.txt", ...)` left the marker on disk after what the PRD calls a
"read-only diff preview", exiting 1 with "brew bundle can't satisfy your Brewfile's dependencies".
A preview implemented that way runs a stranger's code. The invariants below are therefore written
as testable requirements so a future "simplification" fails a test rather than a review.

Traceability: **D1** → "brew is never pointed at a file Cellar did not write", "An imported Brewfile
is bytes, and nothing in it is ever evaluated", "The diff is a pure offline projection and costs no
new acquisition"; **D2** → "Export dumps to a Cellar-owned temporary path…" and "Publication is
Cellar's atomic write…"; **D3** is an app-side placement decision with no `CellarCore` behaviour and
is carried by `tasks`, not by a requirement here; **D4** → "`trusted:` is parsed, surfaced, and
confers nothing"; **D5** → "Every unaccepted construct is a counted skip with a named reason…";
**D6** → the conditional clauses of "An imported Brewfile is bytes…" and of the skip requirement.
The three confirmed assumptions (obs 7520) land as: save panel per export → the destination clause
of the publication requirement; missing pre-selected and present-but-unselectable → the
selectability clauses of the diff requirement; skips never block an import → the final clause of the
skip requirement.

## ADDED Requirements

### Requirement: brew is never pointed at a file Cellar did not write

Every `brew` invocation this capability can produce MUST name, as its `--file` value, a path this
capability itself created under a Cellar-owned temporary location. A path obtained from the user —
by a file picker, a drag, a bookmark, a recent-documents entry, an environment variable, or any
other means — MUST NOT appear in any `brew` argv at any stage, including preview, parsing, diffing,
validation and apply.

`dump` MUST be the only `bundle` subcommand this capability invokes. `brew bundle install`,
`upgrade`, `check`, `cleanup`, `list`, `exec`, `sh`, `env`, `add`, `remove` and `edit` MUST NOT be
invoked at all, with or without `--file`, and `--global` MUST NOT be passed. This rule MUST be
enforceable structurally — verifiable by inspecting the argv the capability can construct, without
running a process — rather than by convention.

#### Scenario: An import spawns no process at all

- GIVEN a recording process seam and a Brewfile carrying taps, formulae and casks
- WHEN it is read, parsed, diffed and projected for presentation
- THEN the recorder saw no process spawned
- AND no argv referencing the imported file's path exists

#### Scenario: A hostile Brewfile executes nothing

- GIVEN a Brewfile whose lines include a `File.write` side effect, a `postinstall:` option, a
  backtick command and a `$(...)` substitution
- WHEN it is imported and previewed
- THEN no marker file, directory or other side effect exists afterwards
- AND the recording process seam saw no process spawned

#### Scenario: Only dump reaches brew, and only on a Cellar path

- GIVEN every argv this capability can construct
- WHEN they are enumerated
- THEN the only `bundle` subcommand present is `dump`
- AND every `--file` value is a Cellar-owned temporary path, and none is a user-supplied path

### Requirement: An imported Brewfile is bytes, and nothing in it is ever evaluated

Import MUST read the user's file as bytes and derive every entry from those bytes. No Ruby MUST be
evaluated, by Cellar or by any subprocess: no interpreter is embedded, and no condition, string
interpolation, method call, constant reference or arithmetic expression appearing in the file MUST
be evaluated. A value MUST be admitted only when it is a literal the grammar accepts.

Parsing MUST be a pure function of those bytes. It MUST NOT read the process environment, MUST NOT
read the filesystem beyond the file itself, MUST NOT issue a network request, and MUST NOT depend on
the host machine, so the same bytes MUST parse identically on any Mac. Parsing MUST mutate nothing:
no install, no tap add, no cache write, no inventory refresh, no history entry.

Every failure to read MUST be a typed outcome rather than a crash or a silent empty result. Bytes
that are not valid UTF-8 MUST be tolerated at line granularity rather than failing the whole file.
A file with no entries MUST parse to a typed empty result that is distinct from a read failure.

#### Scenario: A conditional line is skipped identically on any machine

- GIVEN the line `brew "gnupg" if OS.mac?`
- WHEN it is parsed
- THEN no entry is produced and one skip is counted with the conditional reason
- AND the result is identical whether or not the host is macOS, because the condition was never
  evaluated

#### Scenario: Interpolation and method calls are never evaluated

- GIVEN lines containing `brew "#{ENV['HOME']}/x"` and `brew Foo.bar`
- WHEN they are parsed
- THEN neither produces an entry, each is a counted skip with a named reason
- AND no environment variable was read and no side effect occurred

#### Scenario: Undecodable bytes are tolerated, not fatal

- GIVEN a file whose second line is invalid UTF-8 and whose other lines are well-formed `brew` lines
- WHEN it is parsed
- THEN the well-formed lines still produce entries
- AND the undecodable line is a counted skip, and nothing is thrown

#### Scenario: An empty file is an empty parse, not a failure

- GIVEN a file containing only blank lines and `#` comments
- WHEN it is parsed
- THEN the result is the typed empty parse, carrying zero entries and a skip count of `0`
- AND it is distinguishable from a read failure

### Requirement: The accepted grammar is exactly tap, brew and cask, with their pinned serialisations

The parser MUST accept `tap "name"`, `tap "name", "url"`, either optionally followed by
`, trusted: true` or `, trusted: { ... }` — the optional URL second positional is pinned by probe U9
against a real dump on this machine. It MUST accept `brew "name"` and `cask "name"`, each optionally
followed by an options hash. It MUST accept double- and single-quoted string literals, leading and
trailing whitespace, a trailing comma, full-line `#` comments and trailing `#` comments, and blank
lines. A `brew` or `cask` name MAY carry a tap prefix of the form `user/repo/token`.

A comment line and a blank line carry no entry and MUST NOT be counted as skips, because probe U6
pinned that this Homebrew version emits `#` description comments in a dump **without** `--describe`;
counting them would make every round-trip look lossy.

Every accepted name MUST then be admitted only by constructing the shipped typed identity —
`TapName` for a tap, and `FormulaID` or `CaskID` through `PackageTarget` for a package. A name the
typed identity refuses MUST become a counted skip. No raw string read from the file MUST be carried
forward as a name by any other path.

A tap-prefixed package name MUST be admitted as an ordinary entry. The shipped safety rule
(`MutationName.isSafe`, `MutationCommand.swift:104-108`) rejects only an empty name, a name
beginning with `-`, and a name containing whitespace, so `/` is representable and a third-party
dump's `brew "user/repo/token"` lines MUST NOT degrade into skips.

#### Scenario: A trusted tap with a URL positional parses as one tap entry

- GIVEN the line
  `tap "gentleman-programming/tap", "https://github.com/Gentleman-Programming/homebrew-tap", trusted: { casks: ["engram"] }`
- WHEN it is parsed
- THEN exactly one tap entry is produced, carrying the tap name and the URL
- AND no skip is counted for that line

#### Scenario: A description comment above an entry is not a skip

- GIVEN a dump-shaped file where each `brew` line is preceded by a `# ...` description comment
- WHEN it is parsed
- THEN one entry is produced per `brew` line
- AND the skip count is `0`

#### Scenario: Quoting variants parse to the same entry

- GIVEN the lines `brew "wget"`, `brew 'wget'`, `  brew "wget"  ` and `brew "wget",`
- WHEN each is parsed
- THEN each produces one formula entry naming `wget`
- AND no skip is counted for any of them

#### Scenario: A tap-prefixed name is an entry, not a skip

- GIVEN the lines `brew "acme/tap/thing"` and `cask "acme/tap/app"`
- WHEN they are parsed
- THEN each produces one ordinary package entry naming the tap-prefixed token
- AND neither is counted as a skip, because the shipped safety rule accepts `/`

#### Scenario: A name the typed identity refuses is a skip, never a string

- GIVEN the lines `brew "--force"`, `brew "wget; rm -rf /"`, `brew ""` and `brew "   "`
- WHEN they are parsed
- THEN no entry is produced for any of them and each is a counted skip with the unrepresentable-name
  reason
- AND no argv containing any of those strings was produced or spawned

### Requirement: Every unaccepted construct is a counted skip with a named reason, and the count is zero, not absent

Every line the grammar does not accept as an entry MUST produce a typed skip carrying a **named
reason** and enough of its source — its line number and its raw line, preserved as read — to
identify it. The reason set MUST at minimum distinguish: an unsupported entry kind (`mas`, `vscode`,
`whalebrew`, `go`, `cargo`, `uv`, `npm`, `krew`, `flatpak`, `winget`), an unrecognised directive, a
Ruby conditional, an unrepresentable name, an unrecognised option hash, and a malformed or
undecodable line. Reasons MUST be distinguishable by a consumer without inspecting free text. A
skipped line MUST NOT be silently dropped, and MUST NOT be reported only as a total.

A clean file MUST report a skip count of `0` rather than an absent, `nil` or omitted count, so
"nothing was skipped" and "skips were not tracked" are never the same value.

No skip class MUST block an import. A file that produced skips MUST remain importable: its accepted
entries MUST still be diffed, still be selectable, and still be appliable on exactly the same terms
as a file that produced none.

#### Scenario: Unsupported kinds are counted and named, and the file still imports

- GIVEN a Brewfile carrying `mas "Xcode", id: 497799835`, `vscode "ms-python.python"`,
  `cargo "ripgrep"` and `brew "wget"`
- WHEN it is parsed and diffed
- THEN three skips are counted, each carrying its own named reason and its raw line
- AND `wget` is still projected as an ordinary entry, selectable on the usual terms

#### Scenario: A clean file reports zero, not absence

- GIVEN a Brewfile of only well-formed `tap`, `brew` and `cask` lines
- WHEN it is parsed
- THEN the skip count is `0`
- AND the count is present rather than absent or `nil`

#### Scenario: A wholly unsupported file still parses successfully

- GIVEN a Brewfile containing only `mas` and `vscode` entries
- WHEN it is parsed and diffed
- THEN parsing succeeds with zero applicable entries and every line accounted for as a named skip
- AND the import is not refused, and the empty selection is a legitimate state rather than an error

#### Scenario: A skip keeps its raw line

- GIVEN a Brewfile whose fourth line is `whalebrew "whalebrew/wget"`
- WHEN it is parsed
- THEN the skip for that line reports line number 4 and the raw line exactly as read
- AND no truncation, re-encoding or normalisation was applied to it

### Requirement: `trusted:` is parsed, surfaced, and confers nothing

`trusted: true` and `trusted: { formula: ..., casks: [...], commands: [...] }` MUST be recognised as
grammar wherever a dump can emit them, so the option can never corrupt the parsing of the line it
appears on and can never be mistaken for a name.

A recognised `trusted:` option MUST be surfaced to the user as a **claim made by whoever authored
the file**, attributed to the file rather than to Homebrew, to the tap, or to Cellar. It MUST NOT be
silently discarded from the presentation, because it is security-relevant content.

It MUST confer nothing. No tap trust MUST be recorded, no confirmation MUST be suppressed or
downgraded, no disclosure MUST be shortened, and no argv MUST carry `trusted`, `--trusted` or any
flag derived from the option. A tap named by a `trusted:` option MUST still raise the shipped
`ConfirmationDisclosure.tapTrust` when it is applied, on exactly the same terms as a tap that
carried no such option.

#### Scenario: A trusted tap still raises the trust disclosure

- GIVEN an imported Brewfile whose only entry is `tap "acme/tap", trusted: { casks: ["thing"] }`,
  selected for apply
- WHEN the batch reaches the shared confirmation gate
- THEN exactly one confirmation is raised, carrying the `tapTrust` disclosure for `acme/tap`
- AND the disclosure text is identical to the one raised for a tap that carried no `trusted:` option

#### Scenario: `trusted:` never becomes argv

- GIVEN the same entry, confirmed and submitted
- WHEN the spawned argv is inspected
- THEN it is exactly the shipped tap-add argv for `acme/tap`
- AND it contains no `trusted` token and no flag derived from the option

#### Scenario: The claim is surfaced, attributed to the file

- GIVEN a parsed entry carrying a `trusted:` option
- WHEN the entry is projected for presentation
- THEN the option is present in the projection, attributed to the imported file's author
- AND the projection makes no claim that Homebrew, the tap or Cellar has granted trust

#### Scenario: `trusted:` on a brew or cask line parses and confers nothing

- GIVEN the lines `brew "acme/tap/thing", trusted: true` and `cask "acme/tap/app", trusted: true`
- WHEN they are parsed
- THEN each produces one ordinary package entry with no skip counted
- AND neither entry records any trust grant

### Requirement: The diff is a pure offline projection, and costs no new acquisition

The diff MUST be computed against the resident `InstalledInventory` and `TapInventory`. It MUST
spawn no process, issue no network request, and MUST NOT force a refresh or re-snapshot of any state
domain — the preview costs zero new acquisition, exactly as `installed-inventory` and
`package-discovery` already require of their own projections.

Every parsed line MUST project into exactly one of three typed states: **already present**,
**missing**, or **skipped with a named reason**. A missing entry MUST default to **selected**. A
present entry MUST be visible and MUST NOT be selectable. A skipped entry MUST be visible with its
reason and MUST NOT be selectable. No projection MUST be able to move a present or skipped entry
into the selection.

A file with no entries, a file whose entries are all already present, and a file whose lines are all
skipped MUST be three distinct typed states, never collapsed into one "nothing to do". The
projection MUST be presentable as **Cellar's** reading of the file, and MUST NOT claim to be brew's
own answer.

#### Scenario: Diffing a file acquires nothing

- GIVEN a recording process seam, a resident inventory and a Brewfile of thirty entries
- WHEN the diff is computed
- THEN the recorder saw no process spawned
- AND no inventory or tap re-snapshot was forced

#### Scenario: Missing entries arrive selected and present entries do not

- GIVEN an inventory holding `wget` and a Brewfile naming `wget`, `git` and `ripgrep`
- WHEN the diff is projected
- THEN `git` and `ripgrep` are missing and both default to selected
- AND `wget` is present, visible, and not selectable

#### Scenario: A present or skipped entry cannot enter the selection

- GIVEN a projection carrying one present entry and one skipped entry
- WHEN the selection is asked to include each of them
- THEN neither becomes selected
- AND the selection still contains only missing entries

#### Scenario: Three empties stay distinct

- GIVEN a file with no entries, a file whose every entry is already installed, and a file whose every
  line is a counted skip
- WHEN each is projected
- THEN each reports its own typed state
- AND no two of them are represented by the same value

### Requirement: A selection becomes existing typed mutations, and nothing else is submitted

Applying a selection MUST expand into one **existing** typed command per selected entry: a tap add
for a tap entry, and an install for a formula or cask entry, each naming exactly one subject with
its explicit kind flag. No generated argv MUST name more than one package. This capability MUST NOT
introduce a new mutating command family, a new case of `package-mutation`'s command type, or a new
invalidation domain.

The plan MUST contain a command for every selected entry and for no other line: a deselected entry,
a present entry and a skipped entry MUST never appear in it. Selected taps MUST be ordered before
selected installs, for two independent reasons: a package from a newly added tap must not be
attempted before its tap exists, **and** the shared confirmation gate derives the batch's disclosure
from its **first** command, so a tap-carrying batch presents the tapTrust disclosure only when a tap
leads it. The ordering rule is therefore load-bearing for the disclosure this capability requires,
not merely for install sequencing, and it MUST hold even for a batch whose only tap was selected
last.

The batch MUST be submitted through the shared mutation spine, inheriting per-entry queue item,
streamed log, copy-command, cancel, terminal outcome, exactly one history entry per terminal
outcome, and scoped invalidation. A batch containing at least one tap MUST raise exactly **one**
confirmation carrying the `tapTrust` disclosure; confirming it MUST submit the whole batch and
declining it MUST submit none of it. Nothing MUST be submitted without an explicit selection.

#### Scenario: A mixed selection fans out, taps first

- GIVEN a selection of the tap `acme/tap` and the missing formulae `wget` and `git`, in that order
- WHEN the plan is built
- THEN exactly three operations are enqueued, the tap add first, then `install --formula wget` and
  `install --formula git`
- AND no argv names more than one subject

#### Scenario: Only selected entries are submitted

- GIVEN a projection with two missing entries where one is deselected, one present entry and two
  skipped entries
- WHEN the plan is built and submitted
- THEN exactly one operation is enqueued, for the entry that stayed selected
- AND no operation exists for the deselected, present or skipped entries

#### Scenario: One confirmation covers the batch, and declining submits nothing

- GIVEN a selection containing one tap and two installs, with the tap selected **last**
- WHEN it is submitted
- THEN exactly one confirmation is requested, carrying the `tapTrust` disclosure, before anything is
  enqueued
- AND the disclosure is the same one an unerased tap-add would have presented
- AND declining it spawns no process and enqueues nothing for any of the three

#### Scenario: An empty selection submits nothing

- GIVEN a projected diff with every entry deselected
- WHEN apply is requested
- THEN no confirmation is raised, no operation is enqueued and no process is spawned

#### Scenario: A mid-batch failure attributes to one entry

- GIVEN a confirmed batch of three entries where the second exits non-zero
- WHEN all three reach their terminal outcomes
- THEN the failure is reported against the second entry only
- AND the third still ran, and exactly one history entry exists per terminal outcome

### Requirement: Export dumps to a Cellar-owned temporary path, and the subprocess never touches the user's disk

The export acquisition MUST be exactly `bundle dump --file <path> --force --formula --cask --tap`,
the argv pinned by probe U6; the positive type filters are what exclude `mas` and `vscode` entries.
`<path>` MUST be a **fresh** Cellar-owned temporary path created for that export, so `--force` can
never overwrite a file the user owns, and MUST NOT be a user-chosen destination.

Exit `0` MUST mean the document is the bytes written to that path. Diagnostics belong to stderr and
MUST NOT enter the document at any position, matching the rule the shipped installed, services and
tap payload sources already encode. An exit-`0` run whose stderr is non-empty MUST still be reported
as a success — U6 observed an unrelated warning on stderr at exit 0. A non-zero exit MUST be a typed
failure preserving both raw streams, and MUST NOT be reported as a successful empty document.

The temporary file MUST be removed on success, on every failure, and on cancellation. Export MUST
force no inventory, tap or disk re-snapshot, MUST submit no package mutation, and MUST write no
installation-history entry, because it changes nothing installed.

#### Scenario: The dump argv is pinned

- GIVEN an export request and a recording process seam
- WHEN the acquisition runs
- THEN the recorded argv is exactly `bundle dump --file <path> --force --formula --cask --tap`
- AND `<path>` is a Cellar-owned temporary path that did not exist before this export

#### Scenario: A warning on stderr at exit zero is still a success

- GIVEN a dump exiting `0` with a document on the file and an unrelated warning on stderr
- WHEN the outcome settles
- THEN it is reported as a success carrying the document
- AND no byte of stderr appears anywhere in the document

#### Scenario: A non-zero exit is a typed failure that keeps both streams

- GIVEN a dump exiting non-zero
- WHEN the outcome settles
- THEN it is the typed acquisition failure, carrying the raw stdout and the raw stderr
- AND no file was written at any user destination

#### Scenario: The temporary file never survives the attempt

- GIVEN an export run to success, one run to a non-zero exit, and one cancelled mid-run
- WHEN each attempt ends
- THEN no temporary dump file remains in any of the three cases

#### Scenario: Export acquires nothing else and records nothing

- GIVEN a recording process seam and a recording history seam
- WHEN an export completes successfully
- THEN the only process recorded is the dump itself, with no
  `info --installed --json=v2` invocation
- AND no installation-history entry was written

### Requirement: Publication is Cellar's atomic write to a destination chosen for that export

The bytes shown to the user and the bytes published MUST be **byte-identical** to the dump's
document: no reformatting, re-encoding, line-ending change, reordering, filtering or appended
provenance MUST be applied between acquisition and publication.

The destination MUST be supplied per export by an explicit user choice. The capability MUST NOT
remember, persist or reuse a previously chosen destination, and MUST NOT write to any default or
well-known Brewfile location — `~/.Brewfile`, `~/.homebrew/Brewfile`, an XDG config path, or
`$HOMEBREW_BUNDLE_FILE_GLOBAL` — unless the user chose exactly that path for this export.

The write MUST go through the existing file-system seam atomically. A failed publication MUST leave
any pre-existing file at the destination unchanged and MUST NOT leave a partial or truncated file.
Failure MUST be typed rather than silent. Cancelling the destination choice MUST publish nothing and
MUST still remove the temporary file.

#### Scenario: Published bytes equal the dump's bytes

- GIVEN a successful dump whose document is known byte-for-byte
- WHEN it is published to a chosen destination
- THEN the destination's bytes equal the document exactly, including its trailing newline
- AND no line was added, removed, reordered or re-encoded

#### Scenario: A failed publication preserves the existing file

- GIVEN a destination holding a pre-existing Brewfile and a write that fails
- WHEN the outcome settles
- THEN the failure is typed
- AND the destination's bytes are unchanged, with no partial or temporary artefact left beside it

#### Scenario: No destination is remembered between exports

- GIVEN one completed export published to a chosen destination
- WHEN a second export is requested and the persisted state is inspected
- THEN the second export requires its own explicit destination choice
- AND no stored path, bookmark or defaults key records the first destination

#### Scenario: Cancelling publication writes nothing

- GIVEN a successful dump whose destination choice is then cancelled
- WHEN the attempt ends
- THEN no file was created or modified anywhere outside the Cellar temporary location
- AND the temporary dump file was removed
