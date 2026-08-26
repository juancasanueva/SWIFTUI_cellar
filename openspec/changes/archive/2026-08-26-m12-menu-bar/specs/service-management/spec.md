# Delta for service-management

Existing capability — `openspec/specs/service-management/spec.md` (**12 requirements / 40 scenarios**,
established by `2026-08-03-m3-services`). This delta is **1 MODIFIED, 0 added, 0 removed, 0 renamed**:
the modified block keeps all **four** scenarios it carries today, **byte-identical**, and adds **one**.
The capability becomes **12 requirements / 41 scenarios**.

Nothing is removed and no requirement is renamed, so `rules.archive`'s destructive-delta warning does
not fire. The MODIFIED block is a whole-block replacement copied from the main spec and then edited.
The **only** textual change is **one added paragraph** licensing a secondary read-only surface, carrying
its own `(Previously: …)` line; the cadence paragraph, the stop-entirely paragraph, the one-loop-per-
launch clause and the mutation-suppression paragraph are reproduced word for word.

**Why this clause is needed.** Today's text describes visibility only as the **services section's own**:
"MUST refresh once when the services surface becomes visible, and MUST then refresh every 5 seconds for
as long as it stays visible". The two halves of the shipped conjunction — the section's `onAppear`/
`onDisappear` and the app's active phase — are reported from two places on purpose, and the coordinator's
own comment records that folding them into one setter would let whichever reported last overrule the
other. A **secondary** surface that shows services state without *being* that section therefore had no
described home: it could only report visibility through that same shared boolean (leaving the poll
running after the section closed — the exact class of bug the conjunction exists to prevent), or show
nothing current at all. m12's menu-bar popover is the first such surface, and the clause is written so
the **next** one is bound too.

The **four shipped scenarios carry no `- Verification:` line today**, and this delta does not add one to
any of them — that is what keeps them byte-identical. Only the added scenario carries one.

Session preflight (cached, forwarded verbatim): `execution_mode=interactive`, `artifact_store=hybrid`
(OpenSpec files under `openspec/changes/m12-menu-bar/` + Engram project `swiftui_cellar`),
`delivery_strategy=single-pr`, `review_budget_lines=5000`, `strict_tdd=true`. RDD disabled.

## Verification classes

| Class | Meaning | Runner | Count |
|---|---|---|---|
| `unit` | RED-first assertion over an observable `CellarCore` behaviour, on the injected clock the requirement already mandates | `swift test --package-path Packages/CellarCore` | **1** |

## MODIFIED Requirements

### Requirement: The services surface polls only while visible, on an injected clock

The services list MUST refresh once when the services surface becomes visible, and MUST then refresh
every 5 seconds for as long as it stays visible. The cadence MUST be driven by an injected clock, so
it is provable without wall-clock sleeps.

Polling MUST stop **entirely** — not slow down — when the surface stops being visible, whether
because the window was hidden or because the section was deselected. No poll MUST run while the
surface is not visible. At most one services poll loop MUST run per app launch, regardless of how
many windows are opened or closed.

Polling MUST be suppressed while a service mutation is in flight, so a restart in progress cannot
produce a flickering status. The refresh owed at a service mutation's terminal outcome is required by
"A service operation invalidates services state only" and MUST NOT be duplicated by the poll.

A **secondary read-only surface** — one that presents services state without being the services section
— MAY perform **exactly one baseline refresh** when it appears. Such a surface MUST NOT report
visibility to the coordinator that owns the poll: the visibility conjunction that gates the poll MUST
keep exactly the halves it has today, so a secondary surface can neither start a poll nor keep one alive
after the section itself stops being visible. It MUST NOT start, extend, restart or reschedule a poll of
any cadence, and MUST schedule nothing on the injected clock. Its one refresh MUST be **skipped
entirely** while a service mutation is in flight, on the same terms as the poll and for the same reason,
and MUST NOT be deferred to run at that mutation's terminal outcome, which already owes its own refresh.
Such a surface presents last-known state; a state it cannot obtain MUST read as ordinary last-known
state rather than as an error.
(Previously: the requirement described visibility solely as the services section's own — one refresh on
becoming visible followed by a 5-second cadence — and named exactly two reasons a surface stops being
visible. A read-only surface that shows services state without being that section had no described home,
so it could only overload the shared visibility boolean and leave the poll running past the section's
own disappearance, or show nothing current at all.)

#### Scenario: The list refreshes on the poll cadence while visible

- GIVEN a visible services surface and an injected clock
- WHEN the clock is advanced by 5 seconds three times
- THEN one baseline refresh plus exactly three further refreshes were performed
- AND no wall-clock sleep was required to observe them

#### Scenario: Hiding the surface stops polling entirely

- GIVEN a visible services surface that has already polled at least once
- WHEN the surface stops being visible and the clock is then advanced by 60 seconds
- THEN no further brew invocation is recorded
- AND polling resumes with a baseline refresh when it becomes visible again

#### Scenario: Only one poll loop runs per launch

- GIVEN the app has launched with the services surface visible
- WHEN a second window is opened, then all windows are closed and a new one is opened
- THEN exactly one services poll loop is running throughout

#### Scenario: Polling is suppressed while a service mutation is in flight

- GIVEN a visible services surface and a service mutation in flight
- WHEN the clock is advanced past several poll intervals before that mutation reaches its terminal
  outcome
- THEN no poll refresh ran while the mutation was in flight
- AND exactly one refresh ran at the mutation's terminal outcome

#### Scenario: A secondary read-only surface refreshes once, reports nothing, and starts no poll

- GIVEN a services section that is not visible, an injected clock, and a secondary read-only surface
- WHEN that surface appears and the clock is then advanced by 60 seconds
- THEN exactly one refresh was performed, at its appearance, and advancing the clock produced no further
  brew invocation
- AND no visibility was reported, so the poll's gating conjunction is unchanged and no poll loop started
- AND when the same surface appears while a service mutation is in flight, no refresh runs at all and
  none is deferred to that mutation's terminal outcome
- Verification: `unit`
