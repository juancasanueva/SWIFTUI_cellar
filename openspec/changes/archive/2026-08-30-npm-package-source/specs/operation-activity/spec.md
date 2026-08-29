# Delta for operation-activity

Existing capability — `openspec/specs/operation-activity/spec.md` (**6 requirements / 24 scenarios**).
This delta is **1 ADDED, 0 modified, 0 removed, 0 renamed**; every shipped requirement is byte-identical.
The capability becomes **7 requirements / 27 scenarios**.

"Copy command yields exactly the command that runs" stays true for brew; its `brew ` prefix is now a
derivation from the source projection, and the requirement below states the npm half.

## ADDED Requirements

### Requirement: Activity items carry their source, and their command prefix derives from it

Every enumerated item MUST carry the source of its command. The display command and the copy-command
text MUST be the source's executable name (`brew` or `npm`) followed by the exact argv, in every state,
identical between pending and terminal. The idle summary copy MUST NOT name packages of one source only.
Cancel, log streaming and terminal enumeration MUST be offered on identical terms for both sources.

#### Scenario: An npm item copies and displays as an npm command

- GIVEN a submitted npm upgrade of `typescript`
- WHEN its display command and copy text are read while pending and once terminal
- THEN both are exactly `npm install -g typescript@latest` in both states
- AND the item's source reports npm
- Verification: `unit`

#### Scenario: A brew item is unchanged

- GIVEN a submitted install for the cask `iterm2`
- WHEN its copy text is read
- THEN it is exactly `brew install --cask iterm2`
- Verification: `unit`

#### Scenario: An erased npm item never renders as brew

- GIVEN an npm uninstall erased to the spine's erased type before submission
- WHEN its item is enumerated
- THEN the display command begins with `npm ` and not with `brew `
- Verification: `unit`
