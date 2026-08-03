# Delta for package-mutation

Existing capability — `openspec/specs/package-mutation/spec.md` (7 requirements / 25 scenarios).

Delta summary: **1 MODIFIED requirement / 2 ADDED requirements — 13 scenarios**. The MODIFIED
requirement is reproduced in full so the archive step loses nothing. Nothing is REMOVED or RENAMED.

What changes here:

1. **Bulk uninstall fans out into one invocation per selected package**, the same rule the M2-2
   upgrade-selected ruling (Engram `#7101`) already established for a selected upgrade: per-package
   attribution, log, copy-command, cancel and terminal outcome. Upgrade and uninstall are the only
   bulk-eligible verbs (settled 2026-08-02).
2. **A bulk uninstall confirmation names every package it will remove**, so an all-or-nothing
   destructive action can never be confirmed blind.
3. **Command construction is validated at the type boundary with no bypass** — M2-2 follow-up 3: two
   call sites built commands from a raw, unvalidated package identity, which made
   `MutationCommand`'s by-construction validation claim untrue at exactly those sites.

The selection model itself — its order, its reconciliation against the inventory, and which verbs
offer a bulk affordance — is owned by `installed-inventory`. The durable record each terminal outcome
writes is owned by `installation-history`.

## MODIFIED Requirements

### Requirement: Uninstall and zap are the only mutations behind a confirmation gate

Uninstall, and uninstall with `--zap`, MUST require an explicit confirmation before anything is
submitted to the queue. The confirmation MUST display the exact command that will run, matching the
operation's argv character for character. Zap MUST be a separate, separately-confirmed choice and
MUST NOT be implied by an ordinary uninstall. Install, reinstall, upgrade, pin and unpin MUST NOT
require confirmation. Declining a confirmation MUST spawn no process, submit nothing to the queue,
and leave the inventory untouched.

A bulk uninstall MUST be confirmed once for the whole selection, and that single confirmation MUST
name every package it will remove — not a count alone and not an elided subset. Confirming it MUST
submit the whole selection; declining it MUST submit none of it, never a partial subset.
(Previously: the requirement governed single-package uninstall and zap only, and said nothing about
what a confirmation covering several packages must disclose or submit.)

#### Scenario: Uninstall asks first and shows the exact command

- GIVEN the installed formula `wget`
- WHEN an uninstall is requested
- THEN a confirmation is requested before anything is submitted
- AND the text it presents contains exactly `brew uninstall --formula wget`

#### Scenario: Declining spawns nothing

- GIVEN a pending uninstall confirmation
- WHEN it is declined
- THEN no process is spawned and no operation is enqueued

#### Scenario: Zap is confirmed separately and shows its own command

- GIVEN the installed cask `iterm2`
- WHEN a zap is requested
- THEN a confirmation distinct from the plain uninstall is requested
- AND the command it presents contains `--zap`

#### Scenario: Non-destructive mutations run without confirmation

- GIVEN the formula `wget`
- WHEN install, upgrade, pin and unpin mutations are requested for it
- THEN no confirmation is requested for any of them
- AND each is submitted to the queue directly

#### Scenario: A bulk uninstall confirmation names every selected package

- GIVEN a selection of the formulae `wget` and `git` and the cask `iterm2`
- WHEN a bulk uninstall is requested
- THEN exactly one confirmation is requested before anything is submitted
- AND the text it presents names all three packages

#### Scenario: Declining a bulk uninstall submits none of it

- GIVEN a pending bulk uninstall confirmation over three packages
- WHEN it is declined
- THEN no process is spawned and no operation is enqueued for any of the three

## ADDED Requirements

### Requirement: A bulk selection expands to one invocation per selected package

A bulk upgrade or bulk uninstall over a selection MUST expand into one operation per selected
package, each naming exactly that one package with its own kind flag, enqueued in selection order and
serialized through the existing mutation gate. No generated argv MUST name more than one package, so
kind mixing is structurally impossible and every selected package gets its own queue item, log,
copy-command, cancel and terminal outcome. A failure or cancellation of one operation MUST NOT cancel
or suppress the remaining operations in the batch, and MUST attribute to exactly one package. Bulk
expansion MUST be offered for upgrade and uninstall only; no other verb MUST accept a selection.

#### Scenario: A bulk uninstall expands to one invocation per package

- GIVEN a confirmed bulk uninstall over the formulae `wget` and `git` and the cask `iterm2`, in that
  order
- WHEN the mutations are built
- THEN exactly three operations are enqueued, with the argvs `uninstall --formula wget`,
  `uninstall --formula git` and `uninstall --cask iterm2`, in that order
- AND no argv names more than one package

#### Scenario: A mid-batch failure attributes to one package and does not stop the batch

- GIVEN a bulk action over three packages where the second operation exits non-zero
- WHEN all three reach their terminal outcomes
- THEN the failure is reported against the second package only
- AND the third operation still ran

#### Scenario: Cancelling one operation of a batch leaves the rest queued

- GIVEN a bulk action over three packages with the first running and the other two pending
- WHEN the second is cancelled
- THEN the second is reported cancelled and spawned no process
- AND the third still runs after the first completes

#### Scenario: No other verb accepts a selection

- GIVEN a non-empty selection
- WHEN the mutation surface is asked to build pin, unpin or reinstall mutations for it
- THEN no such bulk mutation is available

### Requirement: Every mutation command is validated at construction, with no bypass

A mutation command MUST be constructible only through a path that validates the package identity it
names, so the by-construction validation claim holds at every call site with no exception. A name
that is empty, that is only whitespace, or that begins with `-` — which would otherwise be
interpreted by brew as an option rather than a package — MUST be rejected at construction and MUST
NOT reach the queue or a spawned process. No alternate constructor, initializer or convenience
overload MUST exist that produces a command from an unvalidated identity.

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
