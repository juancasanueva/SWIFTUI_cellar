# Delta for brew-detection

Editorial reconciliation only — no behavioural change. One requirement is modified; only the THEN
block of its last scenario changes, and its other scenarios are carried over verbatim.

## MODIFIED Requirements

### Requirement: Detection is observable, re-evaluated state

Detection state MUST be observable, evaluated at launch, and re-evaluated on window focus and when
the configured path disappears. Every re-evaluation MUST publish the resulting state so observers
see transitions.
(Previously: identical requirement text; the "Disappearing configured path" scenario asserted a
three-way outcome enumeration alongside the rule that disambiguates it.)

#### Scenario: Evaluated at launch

- GIVEN a fresh detection service
- WHEN the launch evaluation runs
- THEN observers receive exactly one state for that evaluation

#### Scenario: Focus re-evaluation observes a newly installed brew

- GIVEN the current state is `absent`
- WHEN brew appears at `/opt/homebrew/bin/brew` and a focus event occurs
- THEN a re-evaluation runs and observers receive a transition to `native`

#### Scenario: Disappearing configured path transitions away

- GIVEN the current state is `custom` at a configured path
- WHEN that path no longer exists and detection re-evaluates
- THEN observers receive a transition off `custom` to `configuredPathMissing`
- AND a path that still exists but is not executable is instead reported as
  `invalid(notExecutable)`, distinct from `configuredPathMissing`
