# Delta for brew-execution

Existing capability — `openspec/specs/brew-execution/spec.md` (**6 requirements / 22 scenarios**).
This delta is **1 ADDED, 0 modified, 0 removed, 0 renamed**; every shipped requirement is byte-identical.
The capability becomes **7 requirements / 25 scenarios**.

"Normalized brew environment" binds every **brew** invocation and stays true: the npm runner never
composes a brew environment. Cross-source serialization is stated by `package-mutation`, which owns the
spine; this capability keeps its per-runner FIFO unchanged.

## ADDED Requirements

### Requirement: The runner is generalised over an executable and an environment composer

The runner MUST be constructible from an executable path, an environment composer and a process
launcher, with the existing brew-installation initializer preserved as a convenience over that form.
The runner MUST read the executable and compose the environment only through those injected values; it
MUST NOT reach a brew-specific environment type directly. A runner composed for npm MUST spawn the npm
executable under the `npm-source` environment, and a runner composed for brew MUST behave byte-identically
to the shipped runner: same pins, same FIFO, same SIGINT→SIGTERM escalation, same retention. A brew
runner MUST NOT be able to spawn npm and vice versa; source-keyed runners MUST be distinct instances.

#### Scenario: The brew convenience initializer is unchanged in behaviour

- GIVEN a runner built from a brew installation and a recording launcher
- WHEN any command runs
- THEN the recorded executable is the installation's and the environment is the pinned brew environment
- AND every shipped runner test passes unchanged
- Verification: `unit`

#### Scenario: An npm runner spawns npm under the npm environment

- GIVEN a runner built from `/opt/homebrew/bin/npm`, the npm composer and a recording launcher
- WHEN `ls -g --json --depth=0` runs
- THEN the recorded executable is `/opt/homebrew/bin/npm`
- AND the recorded environment contains `npm_config_progress=false` and no `HOMEBREW_*` key
- Verification: `unit`

#### Scenario: The runner reaches no brew environment type directly

- GIVEN the runner's source
- WHEN it is scanned for a direct reference to the brew environment composer
- THEN none exists outside the brew convenience initializer
- Verification: `unit`
