# SLRB Auxiliary Lifecycle Audit

Date: 2026-08-24
Repository: J1NP1N/SL-SHADERS
Branch: audit/slrb-aux-lifecycle

## Scope

Audit target: auxiliary camera and semantic sidecar lifetime.

Reviewed lifecycle question:
- Can a non-main render pass bind, refresh, publish, or mutate the published main semantic sidecar?

This audit is based on the current investigation record and available repository artifacts. Firestorm remains the integration target; SL-SHADERS owns this audit record.

## Known issue

Before the main-view eligibility gate, auxiliary renders after COMPLETE_PUBLISH could reach semantic bindForDraw() and reuse the armed main-view sidecar.

Reported runtime evidence:
- post-complete family=1 BIND_OK spam disappeared after mainViewEligible() gating.

## Pass audit

### Main view

Status: expected owner.

The main view is the only pass permitted to own the semantic publication lifecycle:
- begin sidecar capture
- refresh semantic resources
- bind for draw
- complete publication
- expose published semantic texture

## Reflection

Status: auxiliary.

Must not:
- begin main semantic publication
- refresh published main semantic resources
- bind an armed main-view sidecar

The eligibility gate is required at the bind boundary.

## HUD

Status: auxiliary.

HUD rendering should consume presentation resources only. It must not participate in semantic sidecar ownership.

## Impostor

Status: auxiliary.

No evidence supports allowing impostor rendering to mutate the main semantic publication.

## Cube / reflection probe

Status: auxiliary.

Probe rendering must not inherit main-view semantic state. Cube cameras are separate render contexts.

## Shadow / other auxiliary passes

Status: auxiliary.

These passes must remain outside the main semantic publication lifecycle.

## Lifecycle ownership map

| Operation | Owner |
|---|---|
| begin | main view only |
| refresh | main view only |
| bindForDraw | main view eligible only |
| complete | main view only |
| publish | main view only |

## Contamination assessment

No source-backed evidence in the available audit snapshot proves a remaining mutation path after the gate.

The remaining risk is incomplete enforcement if any future path calls refresh/publish outside the main-view lifecycle rather than only binding the published result.

## Gate placement recommendation

The mainViewEligible() check belongs in bindForDraw() because that is the resource exposure boundary.

Additional defensive checks are justified at lifecycle mutation points:
- begin
- refresh
- complete/publish

The bind gate alone prevents the observed contamination but does not prevent accidental future writes from a new auxiliary caller.

## Transform/coverage scope

No transform or transparency coverage debugging is reopened by this audit. Current evidence concerns lifecycle ownership only.

## Verdict

Lifecycle status: PARTIALLY VERIFIED.

Verified:
- observed post-complete auxiliary bind contamination was reduced by main-view eligibility gating.

Not yet proven:
- every auxiliary pass is unable to reach sidecar mutation paths.
- published texture storage is immutable after publication.

## Next action

Instrument and assert sidecar owner identity at begin/refresh/complete/publish boundaries for all render families.
