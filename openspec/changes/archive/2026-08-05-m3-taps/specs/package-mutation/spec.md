# Delta for package-mutation

## MODIFIED Requirements

<!-- PM3 -->
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

The shared confirmation gate MUST additionally carry the typed tap-add trust disclosure and typed
force-untap affected-package disclosure owned by `tap-management` TM6 and TM8. Every tap add and every
force untap MUST be confirmed; plain untap MUST NOT require confirmation or be made forceful
implicitly. The exact command MUST come from the typed mutation request. Warning text, rendered
command text, package disclosure, and persisted history text MUST never be parsed to construct or
modify argv. A stale force disclosure MUST be rejected before process spawn on the freshness terms of
TM8 and MUST require a new confirmation.

(Previously: confirmation covered package uninstall, zap, and bulk uninstall only; the shared gate
had no typed trust or force-untap disclosure and no stale-disclosure rejection rule.)

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

#### Scenario: Every tap add carries typed trust disclosure

- GIVEN a valid tap-add request
- WHEN it reaches the shared confirmation gate
- THEN confirmation carries the typed tap identity, exact command, and third-party code warning
- AND declining submits nothing

#### Scenario: Force untap carries typed complete package disclosure

- GIVEN an eligible force untap affecting formulae and casks
- WHEN it reaches the shared confirmation gate
- THEN every affected package and kind is carried without elision or count-only substitution
- AND plain untap remains a distinct non-force request

#### Scenario: Stale disclosure and display text cannot become argv

- GIVEN a force disclosure whose affected set changes while open or queued
- WHEN confirmation reaches submission
- THEN it is rejected before spawn and requires a refreshed confirmation
- AND neither display text nor stored text is parsed into a replacement argv
