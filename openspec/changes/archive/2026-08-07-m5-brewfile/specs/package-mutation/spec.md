# Delta for package-mutation

**2 MODIFIED** requirements, each replaced as a whole block that is a strict superset of the text it
replaces, adding **5 scenarios** in total. Nothing is ADDED, REMOVED or RENAMED.
9 requirements / 43 scenarios → **9 requirements / 48 scenarios**.

Only PM1 ("Every mutation is a typed command carrying an explicit kind flag") and PM9 ("Every
mutation command is validated at construction, with no bypass") move. The other seven requirements
are untouched and stay byte-identical, and no package rule is loosened: this delta **narrows**
nothing and **widens** nothing.

**PM9 — the provenance premise.** The reasoning block at the head of `MutationCommand.swift` argues
from "names come from brew's own snapshot or from the catalog, never from free text". An imported
Brewfile is a user-supplied file, and it is a name source. That premise therefore stops being true
in this slice, and it is restated deliberately here rather than left stale where a future reader
would trust it. No new construction path is created, no existing gate is relaxed, and the typed
identities (`TapName`, `FormulaID`, `CaskID` through `PackageTarget`) remain the only way a name
becomes a command.

**PM1 — a disclosure that does not survive erasure.** PM1 already requires that everything the spine
needs from a command be readable **through the shared abstraction**, so that no consumer needs to
know which capability a command came from. Design (`design.md`, Engram obs 7523) verified that claim
against shipped source and found one projection outside it: the confirmation disclosure.
`OperationCenterBulk.swift:141` recovers it with a concrete-type downcast —
`(first as? TapCommand)?.disclosure ?? .packageRemoval` — while `AnyBrewMutation`
(`BrewMutating.swift:144-162`) carries only seven projections and `disclosure` is not among them and
is not a `BrewMutating` requirement. Every shipped call site happens to submit an unerased
`TapCommand`, so the gap has never fired; a Brewfile batch is the first mixed tap+install submission
and must be erased to `[AnyBrewMutation]` before `request(_:)`, at which point the downcast fails and
the sheet silently shows the package-removal disclosure instead of the tap-trust warning. That is a
security-relevant downgrade, so it is fixed as a requirement rather than as an implementation
detail. Design decision **DD1** is the mechanism: promote `disclosure` to a `BrewMutating`
requirement with a `.packageRemoval` extension default, carry it on `AnyBrewMutation`, and read
`first.disclosure`.

## MODIFIED Requirements

<!-- PM1 -->
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
supply the ordinary package-removal disclosure by default rather than by a caller's fallback. A
batch's disclosure MUST be derived from the commands themselves — the first submitted command's
disclosure, which is the command the confirmation leads with — so a batch presents the same
disclosure whether its commands were submitted as a concrete type or as erased values. Erasure MUST
NOT change, downgrade or discard a disclosure. This rule governs the **disclosure** only: it does not
disturb the separate typed cleanup evidence a confirmation may additionally carry, and it does not
forbid reading a command's verb for a presentation concern that is not the disclosure, such as the
shipped retitling of a zap confirmation.
(Previously: the enumerated list of projections readable through the shared abstraction omitted the
confirmation disclosure, so the spine recovered it by downcasting to a concrete command type and an
erased batch silently fell back to the package-removal disclosure — defeating a typed warning that
another capability owns.)

#### Scenario: Installing a formula names it as a formula

- GIVEN the formula `wget`
- WHEN an install mutation is built for it
- THEN the argv is exactly `install --formula wget`

#### Scenario: Installing a cask names it as a cask

- GIVEN the cask `iterm2`
- WHEN an install mutation is built for it
- THEN the argv is exactly `install --cask iterm2`

#### Scenario: Uninstalling a cask names it as a cask

- GIVEN the installed cask `iterm2`
- WHEN an uninstall mutation is built for it
- THEN the argv is exactly `uninstall --cask iterm2`

#### Scenario: Reinstall, pin and unpin carry the kind flag too

- GIVEN the installed formula `git`
- WHEN reinstall, pin and unpin mutations are built for it
- THEN their argvs are exactly `reinstall --formula git`, `pin --formula git` and
  `unpin --formula git`

#### Scenario: A token that exists in both namespaces is never ambiguous

- GIVEN `docker` exists as both a formula and a cask
- WHEN an install mutation is built for the cask `docker`
- THEN the argv contains `--cask` and does not contain `--formula`
- AND the spawned command is the cask install, not the formula install

#### Scenario: Another family enters the spine without becoming a case of this type

- GIVEN a command belonging to a different capability, submitted through the shared mutation spine
- WHEN this capability's mutating-command type is enumerated
- THEN it still carries exactly the six package commands, with no case for that other command
- AND the submitted command was still projected with its argv, its verb and its terminal outcome

#### Scenario: An erased mixed batch still discloses tap trust

- GIVEN a batch whose first command is a tap add and whose remaining commands are installs, erased
  to the spine's erased command type before submission
- WHEN it reaches the shared confirmation gate
- THEN the confirmation carries the tap-trust disclosure for that tap
- AND it is identical to the disclosure the same tap add presents when submitted unerased

#### Scenario: An erased install-only batch still discloses package removal

- GIVEN a batch of package mutations only, erased before submission
- WHEN it reaches the shared confirmation gate
- THEN the confirmation carries the ordinary package-removal disclosure
- AND no tap-trust or force-untap disclosure is presented

#### Scenario: No disclosure is recovered by a type test

- GIVEN every consumer of the shared mutation spine that presents a confirmation
- WHEN the path that produces the disclosure is inspected
- THEN the disclosure is read from the command through the shared abstraction
- AND no downcast, type test, case switch or verb-string inspection produces it

<!-- PM9 -->
### Requirement: Every mutation command is validated at construction, with no bypass

A mutation command MUST be constructible only through a path that validates the package identity it
names, so the by-construction validation claim holds at every call site with no exception. A name
that is empty, that is only whitespace, or that begins with `-` — which would otherwise be
interpreted by brew as an option rather than a package — MUST be rejected at construction and MUST
NOT reach the queue or a spawned process. No alternate constructor, initializer or convenience
overload MUST exist that produces a command from an unvalidated identity.

A name that originated in a **file supplied by the user** — an imported Brewfile — is subject to
exactly these rules and to no weaker ones. The premise this requirement was written under, that a
name reaches it from brew's own snapshot or from the catalog and never from free text, no longer
holds once a user-supplied file is a name source; it is restated here rather than left stale. A
file-sourced name MUST become a command only by constructing the same validated typed identity every
other call site constructs. A name that typed identity refuses MUST be reported by its caller as a
typed, counted refusal, and MUST NOT reach the queue, an argv, or a spawned process by any other
path. No file-sourced-name convenience constructor MUST exist, no "already validated" bypass MUST
exist, and no path MUST carry a raw string read out of a file into argv.

(Previously: the requirement governed construction generally while assuming every name arrived from
brew's own snapshot or from the catalog, and said nothing about a name originating in a
user-supplied file.)

#### Scenario: An empty or whitespace name is rejected

- GIVEN package identities whose names are the empty string and a single space
- WHEN a mutation command is constructed for each
- THEN construction fails for both and no operation is enqueued

#### Scenario: A name that looks like an option is rejected

- GIVEN a package identity named `--force`
- WHEN a mutation command is constructed for it
- THEN construction fails
- AND no argv containing `--force` was produced or spawned

#### Scenario: No construction path skips validation

- GIVEN the public construction surface of the mutation command type
- WHEN every way to obtain a command instance is enumerated
- THEN each one applies the same identity validation

#### Scenario: A file-sourced name is validated on exactly the same terms

- GIVEN names read out of an imported Brewfile, including `--force`, `wget; rm -rf /`, the empty
  string and a single space
- WHEN a mutation command is constructed for each
- THEN construction fails for every one of them
- AND none reaches the queue, and no argv containing any of those strings was produced or spawned

#### Scenario: No path carries a raw file-sourced string into argv

- GIVEN the public construction surface and every call site that builds a command from an imported
  Brewfile
- WHEN they are enumerated
- THEN every file-sourced name passes through the same validated typed identity as every other name
- AND no constructor, overload or bypass accepts an unvalidated string read from a file
