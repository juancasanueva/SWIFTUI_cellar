# Delta for brew-detection

Existing capability — `openspec/specs/brew-detection/spec.md` (5 requirements / 12 scenarios).

Delta summary: 1 MODIFIED requirement / 6 scenarios (3 copied unchanged, 3 added). Nothing is
ADDED, REMOVED or RENAMED. The block below is the complete replacement for
"Detection is observable, re-evaluated state": its three existing scenarios are reproduced verbatim
so the archive step does not lose them.

The change is the same single-flight invariant `catalog-sync` states for sync, applied to detection
so that `InstalledStore` (M2 slice 1) has one correct exemplar to copy rather than two defective
ones.

## MODIFIED Requirements

### Requirement: Detection is observable, re-evaluated state

Detection state MUST be observable, evaluated at launch, and re-evaluated on window focus and when
the configured path disappears. Every re-evaluation MUST publish the resulting state so observers
see transitions. Overlapping re-evaluations MUST be coalesced onto the one evaluation genuinely in
flight; a re-evaluation requested after the evaluation in flight has settled, or after its
requesting caller was cancelled or abandoned, MUST run a fresh probe and MUST NOT be answered with
the earlier evaluation's result. A settled or abandoned evaluation MUST NOT leave detection unable
to re-evaluate.
(Previously: the requirement mandated observability and publication on every re-evaluation but said
nothing about coalescing, so a caller arriving after an evaluation settled could be handed that
stale result as if it were fresh.)

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

#### Scenario: A settled evaluation does not answer a later re-evaluation

- GIVEN a locator that answered one evaluation with `absent` and that evaluation has settled
- WHEN a re-evaluation is requested and the locator would now resolve `native`
- THEN the locator is probed a second time
- AND observers receive a transition to `native`

#### Scenario: An abandoned caller does not poison later re-evaluations

- GIVEN a caller whose task is cancelled while it awaits a re-evaluation
- WHEN a later re-evaluation is requested and the locator would now resolve a different state
- THEN a fresh probe runs
- AND observers receive the newest result rather than the abandoned caller's

#### Scenario: Concurrent re-evaluations coalesce onto one probe

- GIVEN a locator that does not answer until it is released
- WHEN two callers request a re-evaluation before the locator is released
- THEN exactly one probe is performed and both callers observe the same resulting state
