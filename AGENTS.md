# AGENTS.md — SL-SHADERS Implementation Contract

This file defines implementation rules for coding agents working in this repository.

The repository, its committed documentation, runtime evidence, and verified packages are the project source of truth. Chat history is not authoritative unless its conclusions are written back into the repository.

These rules supplement, and do not replace:

- `README.md`
- `docs/HANDOFF.md`
- `docs/DEBUG_PROTOCOL.md`
- `docs/UPSTREAM_RENDERER_NOTES.md`
- `packages/RECOVERY_STATUS.md`
- subsystem-local `PROJECT_STATUS.md` / agent contracts where present

If two instructions conflict, prefer the instruction that is more specific to the subsystem and more recently backed by runtime proof. Do not silently resolve a conflict: document it in the change report.

---

## 1. Core engineering philosophy

### 1.1 Runtime proof outranks source inspection

Source review, successful compilation, shader compilation, or a plausible screenshot is not proof that a renderer change works in Firestorm.

The normal loop is:

1. Form one explicit hypothesis.
2. Implement the smallest change that tests or corrects it.
3. Build/package a uniquely identifiable version.
4. Run it in real Firestorm.
5. Collect the requested diagnostic evidence.
6. Update repository state from that evidence.
7. Only then classify the issue as proven, disproven, fixed, or unresolved.

Never mark a rendering issue `FIXED` solely because the code compiles.

Use statuses such as:

- `IMPLEMENTED — AWAITING RUNTIME PROOF`
- `RUNTIME PROVEN`
- `DISPROVEN`
- `REGRESSED`
- `SUPERSEDED`

### 1.2 Firestorm is the implementation target

Firestorm is the renderer being patched.

Black Dragon, stock ReShade behavior, generic OpenGL conventions, academic reference implementations, and other viewers may be useful evidence, but they do not override measured Firestorm behavior.

Do not generalize away a Firestorm-specific invariant merely to make code look architecturally generic.

### 1.3 Preserve known-good behavior

Do not rewrite unrelated renderer paths while correcting a focused issue.

When a known-good checkpoint exists, change the minimum surface required to test the current hypothesis.

If a cleanup or refactor is desirable but not required for the active correction, record it as follow-up work instead of combining it with the experiment.

### 1.4 One experiment must answer one useful question

Avoid packages that simultaneously change:

- capture selection,
- shader math,
- blend/composite behavior,
- alpha handling,
- resource lifetime,
- UI defaults,
- and diagnostic presentation.

A runtime result from such a package is difficult to interpret.

Prefer revisions whose result can clearly discriminate between competing causes.

---

## 2. Source-of-truth and branch discipline

Before editing:

1. Read `README.md`.
2. Read `docs/HANDOFF.md`.
3. Read the relevant subsystem status/contract.
4. Check the currently active branch and newest subsystem checkpoint.
5. Inspect newer experimental directories before modifying an older package.

Do not assume `main` contains the newest implementation of every subsystem.

Do not merge concepts from experimental/reference branches unless explicitly required.

For GTAO work, treat distinct architectures such as direct pre-alpha GTAO, alpha-recomposition experiments, and reference implementations as separate design lines unless the current handoff explicitly merges them.

When an architecture is historical, label it as such instead of deleting evidence needed to understand prior conclusions.

---

## 3. Mandatory renderer invariants

### 3.1 Do not modify Firestorm state without restoring it

Any injected operation that modifies Firestorm GPU state must restore the exact effective state that existed immediately before injection.

This includes, where applicable:

- graphics pipeline stages,
- shaders,
- blend state and blend factors,
- color write masks,
- depth/stencil state,
- render targets and depth/stencil views,
- viewports,
- scissors,
- descriptor/resource bindings,
- samplers,
- uniform/constant bindings,
- topology,
- framebuffer state,
- sRGB-relevant state,
- other state modified by the add-on.

Restore captured state. Do not restore assumed defaults unless a Firestorm invariant has been runtime/source proven and documented.

Do not rely on unordered container iteration to reconstruct overlapping state.

### 3.2 Never silently truncate application state

If the implementation only supports a limited number of render targets, bindings, resources, or stages, it must:

- prove that the intercepted Firestorm path never exceeds the limit, or
- skip injection safely when the limit is exceeded.

Never restore only a subset while claiming exact restoration.

### 3.3 Treat Firestorm resource handles as lifetime-bound

Cached Firestorm resources are not permanent identities.

Any cached native resource, view, depth surface, normal surface, scene-color target, or derived SRV must be invalidated when the underlying resource is destroyed or recreated.

Account for:

- resize,
- graphics-setting changes,
- render-target recreation,
- renderer reset/reinitialization,
- viewer transitions that rebuild buffers.

Opaque handle equality alone is not sufficient lifetime proof.

Where practical, track a resource generation/epoch.

### 3.4 Prefer scoped/RAII guards

Injection/recursion guards should be scoped so early returns cannot leave the system permanently suppressed.

Prefer command-list-scoped or thread-local recursion state where appropriate.

Retain process-global guards only when ReShade/Firestorm serialization makes them correct, and document that assumption.

### 3.5 Shared settings must be synchronized

Do not let ImGui or another UI callback mutate render-thread state through an unsynchronized pointer.

Use local UI values and synchronized commits, atomics where appropriate, or another explicit ownership mechanism.

---

## 4. Diagnostic design rules

`docs/DEBUG_PROTOCOL.md` is authoritative for renderer diagnostics.

Diagnostics must separate:

1. native inputs,
2. intermediate algorithm state,
3. final contribution/composite,
4. numeric/source proof.

A semantic being bound is not evidence that its contents are correct.

For captured Firestorm resources, diagnostics should expose enough identity to detect selection of the wrong renderer pass. Where relevant include:

- resource/texture identity,
- dimensions,
- format,
- selected FBO/draw/pass identity,
- frame or resource generation,
- read/copy status,
- representative numeric samples.

Reject implausible candidates rather than accepting the first resource that superficially matches.

Examples of resources that must not be confused with the main view include probe-space buffers, shadow maps, reflection targets, and other auxiliary passes.

A black final output is never the only diagnostic supplied for experimental renderer work.

---

## 5. GTAO operating-mode contract

For direct Firestorm GTAO work, the implementation must expose three conceptually distinct operating states.

Names may differ in UI/code, but their invariants may not.

### 5.1 Native Firestorm

Purpose: establish the trusted control image.

Required behavior:

- GTAO algorithm does not execute.
- No GTAO fullscreen passes.
- No validation-only GTAO passes.
- No alpha replay.
- No scene-color copy needed for GTAO.
- No GTAO composite.
- No fullscreen "copy the original image back" pass.
- No Firestorm scene-color writes by the GTAO add-on.
- Diagnostic FX defaults to showing the ordinary backbuffer/native Firestorm image.
- Switching into this mode must not require a viewer restart.

Core invariant:

> Native Firestorm mode performs zero GTAO-owned writes to Firestorm scene color.

This mode is the control case for determining whether the loaded add-on itself contaminates rendering.

### 5.2 Generate Only / GTAO Diagnostics

Purpose: generate inspectable GTAO data without applying GTAO to Firestorm.

Required behavior:

- Native Firestorm D0/N0 may be captured.
- GTAO passes required for requested diagnostics may run.
- Private diagnostic resources/semantics may be published.
- Alpha replay may run only when it is required to generate the requested diagnostic.
- Validation-only passes run only when their outputs are requested.
- No GTAO result is composited into Firestorm.
- The GTAO add-on performs zero writes to Firestorm scene color.

Core invariant:

> Generate Only may produce private GTAO resources, but it never modifies Firestorm scene color.

Do not implement Generate Only by drawing a saved scene texture back into Firestorm. The correct behavior is to avoid the Firestorm scene write.

### 5.3 Apply GTAO

Purpose: production direct pre-alpha GTAO.

Required behavior:

- Capture the proven Firestorm inputs.
- Execute only passes required for production GTAO.
- Perform required alpha-boundary integration.
- Composite GTAO at the proven direct pre-alpha boundary.
- Restore exact Firestorm GPU state afterward.

Core invariant:

> Apply GTAO modifies Firestorm only at explicitly documented injection points.

### 5.4 Terminology

Avoid using `passthrough` as an overloaded term.

Historically it can mean:

- do not apply AO,
- copy the original scene through a shader,
- show the backbuffer,
- generate diagnostics without compositing.

Prefer explicit names such as:

- `Native Firestorm`
- `Generate Only`
- `Apply GTAO`

Diagnostic-view selection is independent from operating mode.

---

## 6. GTAO input-selection rules

The GTAO algorithm must use the authoritative Firestorm main-view depth and normal inputs proven for the targeted render path.

Do not replace native Firestorm D0/N0 with generic ReShade depth or reconstructed normals without explicit architectural approval and runtime proof.

Selection must guard against auxiliary Firestorm passes.

At minimum, verify that selected D0/N0:

- have mutually compatible dimensions,
- correspond to the active/main viewport,
- are not known probe-space dimensions,
- are not shadow-map resources,
- belong to the relevant deferred/main-pass epoch,
- remain valid for the frame in which GTAO consumes them.

Where a heuristic threshold is used, document its origin and make it observable in diagnostics.

Do not copy an unrelated subsystem's threshold merely because it worked there.

---

## 7. Alpha integration rules

For the direct pre-alpha GTAO architecture, preserve the current architecture contract unless a new architecture is explicitly authorized.

Do not silently reintroduce alpha-recomposition dependencies from a different experimental branch.

Alpha replay behavior follows operating mode:

- Native Firestorm: never.
- Generate Only: only when a requested output requires it.
- Apply GTAO: when required by the active direct-prealpha algorithm.

Any state modified during replay must be captured and exactly restored.

---

## 8. Shader source rules

There must be one authoritative source for each shader.

Do not manually maintain behaviorally divergent copies in both standalone `.glsl`/`.hlsl`/`.fx` files and embedded C++ strings.

Preferred flow:

```text
authoritative shader source
        ↓
build/generation step
        ↓
generated embedded representation
```

Generated files must be reproducible.

If generated embedded shader content is committed, add a verification step that detects drift from the authoritative source.

Never patch only the generated copy.

---

## 9. Performance rules

Do not execute diagnostic or validation passes in the normal production path unless their output is required by the production algorithm.

Every fullscreen pass should be classifiable as:

- production-required,
- diagnostic-only,
- validation/development-only.

Native Firestorm mode executes no GTAO passes.

Generate Only executes only the passes needed for the selected diagnostic set.

Apply GTAO executes production-required passes plus explicitly enabled diagnostics.

When adding a pass, document why it must execute and in which modes.

---

## 10. Versioning and package identity

Every runtime-testable revision must have an unambiguous visible identity.

Update all relevant:

- overlay/version text,
- technique/debug labels,
- package/directory names,
- README/status metadata.

Do not allow an older technique or binary to be mistaken for the new test.

Installable archives follow the repository package contract:

- filename begins with `SL_`,
- filename ends with `.zip`,
- package has one top-level project directory.

A successful archive creation/upload is not proof that the package is valid.

Record byte/checksum evidence where the repository's recovery/package process requires it.

---

## 11. Required change report from coding agents

Every nontrivial corrective implementation must report:

### Scope

- branch/checkpoint used as the base,
- files changed,
- explicitly excluded areas.

### Cause

For each issue:

- observed problem,
- root cause,
- correction made.

### Invariants

State which renderer invariants the change relies on or establishes.

### Proof status

For each claimed fix, classify it as:

- source-reviewed only,
- compiled,
- packaged,
- runtime-proven.

Do not collapse these states.

### Remaining risks

List any assumptions not yet proven in Firestorm.

### Runtime test

Provide exact steps for the next Firestorm test, including:

- operating mode,
- diagnostic view,
- scene/test condition,
- expected visual result,
- expected counters/readouts,
- exact information the user should report back.

---

## 12. GTAO release gate

A GTAO corrective release must not be promoted to a known-good checkpoint until the following mode transitions are runtime tested:

```text
Native Firestorm
      ↓
Generate Only
      ↓
Apply GTAO
      ↓
Native Firestorm
```

Minimum acceptance evidence:

### Native Firestorm

- visually matches the native viewer baseline,
- zero GTAO scene-color writes,
- zero GTAO fullscreen passes,
- zero alpha replay.

### Generate Only

- requested GTAO resources are produced,
- diagnostics are inspectable,
- zero GTAO writes to Firestorm scene color.

### Apply GTAO

- GTAO appears at the intended boundary,
- expected alpha behavior is preserved,
- no persistent Firestorm state corruption is visible,
- switching back to Native Firestorm restores the control view without restart.

Compilation alone does not satisfy this release gate.

---

## 13. Project-state updates

When runtime evidence changes the current conclusion:

- update the relevant subsystem `PROJECT_STATUS.md` or equivalent,
- update `docs/HANDOFF.md` when the repository-wide current state changes,
- update reusable renderer findings in `docs/UPSTREAM_RENDERER_NOTES.md`,
- update package/recovery records when a verified package changes.

Do not leave the latest conclusion only in a chat transcript or agent response.

---

## 14. Things agents must not do

Do not:

- declare success because the project compiles;
- invent runtime results;
- invent recovered history or Git provenance;
- overwrite a known-good checkpoint without preserving its identity;
- combine unrelated renderer hypotheses in one corrective revision without justification;
- treat diagnostic visualization as proof of correct source selection without numeric/identity evidence;
- restore guessed GPU defaults when exact captured state is available;
- silently swallow unsupported Firestorm state;
- maintain two hand-edited copies of a shader;
- call a generate-and-restore render path `Native Firestorm`;
- change GTAO quality/tuning while debugging injection correctness unless tuning itself is the explicit experiment.

---

## 15. Decision rule

When uncertain, choose the implementation that makes the next Firestorm runtime result easier to interpret.

The project optimizes for **provable renderer behavior**, not for the smallest source diff, the most generic abstraction, or the fastest claim of completion.
