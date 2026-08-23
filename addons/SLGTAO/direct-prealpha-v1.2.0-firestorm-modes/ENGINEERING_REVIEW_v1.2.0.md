# Direct GTAO v1.2.0 corrective engineering report

Target: Firestorm / Second Life + ReShade OpenGL  
Date: 2026-08-23

This pass addresses the external review of the v1.1f passthrough lineage while preserving the runtime-proven Firestorm pre-alpha boundary and GTAO algorithm. The current source is v1.2.0.

## Files changed

- `SLAlphaGTAOHook.cpp`
- `SLDirectGTAO.cpp`
- `SLDirectGTAO.hpp`
- `SL_DirectGTAO_Debug.fx`
- `shaders/sl_gtao_basis_probe.frag.glsl`
- `shaders/sl_gtao_composite.frag.glsl`
- `CMakeLists.txt`
- `cmake/GenerateShaderHeader.cmake`
- `cmake/VerifyShaderHeader.cmake`
- `cmake/ValidateSource.cmake`
- `tests/validate_source.py`
- `README.txt`
- `PROJECT_STATUS.md`
- `GTAO_AGENT_CONTRACT.txt`

`SLDirectGTAOShaders.hpp` is intentionally no longer a source file. It is generated into the build tree from the GLSL files.

## Review issues

### 1. Passthrough was not a trustworthy Firestorm baseline

Root cause: v1.1f still used a private scene copy plus fullscreen copyback, so visually identical pixels did not imply untouched Firestorm rendering.

Fix: replaced passthrough with `operation_mode`:
- `firestorm_baseline`
- `gtao_diagnostics`
- `gtao_active`

Baseline never arms or executes direct GTAO and performs no scene copy/write. Diagnostics can arm/generate private resources but does not copy or write Firestorm scene color. Only Active receives the Firestorm scene RTV and is permitted to copy/composite it.

### 2. Debug FX default defeated passthrough

Root cause: diagnostic view could default/persist to a non-backbuffer buffer.

Fix: `SLDirectGTAODebugView` defaults to 0. A separate `SLDirectGTAOOperationMode` uniform is driven by the add-on; Baseline forces the FX to return `ReShade::BackBuffer` regardless of a persisted diagnostic selection.

### 3. Contradictory UI controls

Root cause: passthrough and boundary diagnostic controls described overlapping rendering behavior.

Fix: the overlay now exposes one operating-mode selector. Diagnostic generation workload is shown only in Diagnostics mode. Legacy alpha replay diagnostics are shown only in Active and remain off by default. ReShade visualization remains a separate FX control.

### 4. Validation-only passes ran during ordinary generation

Root cause: N dot V and unoccluded-baseline probes shared the generic generation path.

Fix: resource arming and execution use an explicit workload plan. Active allocates/runs only edge, raw, bilateral H/V and composite. N dot V and baseline targets/passes are created and executed only for the corresponding Diagnostics workload.

### 5. Alpha replay ignored operating mode

Root cause: legacy alpha replay was coupled to boundary interception rather than a mode contract.

Fix: alpha replay is disabled in Baseline and Diagnostics. It is Active-only and opt-in through `legacy_alpha_diagnostics`. Direct GTAO itself does not require replay: Active composites opaque AO immediately before Firestorm's real forward-alpha draws, which then continue normally.

### 6. Pipeline restoration was nondeterministic

Root cause: overlapping stage masks stored in an unordered map could restore in an order different from Firestorm's effective state.

Fix: track the effective pipeline for the five canonical stages actually modified by direct GTAO: vertex shader, pixel shader, rasterizer, depth-stencil and output-merger. A later stage-specific Firestorm bind overwrites that stage's effective entry. Restore is a fixed-order per-stage loop, independent of hash iteration.

### 7. Alpha blend restoration used assumed values

Root cause: replay restoration could infer/hardcode alpha factors instead of restoring the exact application values.

Fix: capture `source_alpha_blend_factor`, `dest_alpha_blend_factor` and `depth_write_mask` from Firestorm dynamic-state callbacks. Replay fails closed unless all three are valid and restores the captured values after the replay draw. Color blend factors are not substituted for alpha factors.

### 8. MRT state was truncated

Root cause: earlier tracking retained at most four RTVs.

Fix: `current_rtvs` and owning `current_rtv_resources` are dynamic vectors populated from the complete ReShade callback. Restore uses the full retained count. No <=4 Firestorm assumption remains.

### 9. Cached Firestorm resource lifetime was insufficiently tracked

Root cause: opaque resource/view handles could survive Firestorm target recreation.

Fix: register `destroy_resource`, `destroy_resource_view` and `destroy_pipeline` callbacks. Destroyed D0/N0/candidate/scene-color handles are cleared, direct D0/N0 derived SRVs are invalidated under the GTAO resource mutex, and application RT/pipeline snapshots are marked invalid until a fresh Firestorm bind is observed. The destruction callback does not call effect-runtime texture binding APIs; the next begin-effects pass unbinds/rebinds semantics from current valid resources.

### 10. Global recursion guards were too broad

Root cause: process-global booleans could suppress unrelated callback activity and could remain set after early returns.

Fix: direct GTAO and alpha replay use thread-local recursion depths with RAII scopes. The ReShade begin/finish-effects guard remains a paired thread-local depth because the protected phase spans two separate callbacks; it is incremented only after validation and self-heals/logs if an unmatched prior depth is detected.

### 11. Settings synchronization/data race

Root cause: ImGui could mutate shared settings while render callbacks read them.

Fix: overlay reads a settings snapshot under `device_state->mutex`, edits only the local copy, then commits the whole copy under the same mutex. Render callbacks also snapshot settings under that mutex before using them. The UI never receives a pointer to shared mutable settings.

### 12. Embedded and standalone shaders drifted

Root cause: hand-maintained `SLDirectGTAOShaders.hpp` duplicated GLSL and had already diverged.

Fix: `shaders/*.glsl` are authoritative. CMake generates `SLDirectGTAOShaders.hpp` into the build directory. `VerifyShaderHeader.cmake` independently regenerates a verification copy and compares it byte-for-byte. Source validation fails if a source-tree generated header reappears.

### 13. Version/documentation drift

Root cause: package, README, overlay and shader lineage described different versions/behavior.

Fix: project metadata, overlay/name strings and documentation are v1.2.0 and document the three operating modes plus the separate ReShade debug-view selector.

### 14. Critical-invariant validation was missing

Fix: added source/build checks plus runtime telemetry. `execution_stats` records fullscreen passes, scene copies/writes and generated outputs. The hook validates requested-mode output sets, counts invariant violations, counts state-restore callbacks and resource invalidations, and surfaces those values in the overlay. `tests/validate_source.py` and `cmake/ValidateSource.cmake` catch structural regressions before build.

## Deliberately unchanged Firestorm-specific behavior

- The proven Firestorm straight-alpha transition remains the injection boundary.
- D0 and N0 discovery/semantics are preserved.
- Firestorm's stereographic normal decode is preserved.
- GTAO horizon math, radius/strength/falloff and bilateral algorithm are not retuned in this pass.
- Direct GTAO still relies on the proven Firestorm pre-alpha draw context for triangle-list/VAO input-assembler state; the injected pipeline does not alter IA. This avoids extra Firestorm state mutation and therefore no IA restore is required.
- Alpha replay remains available as a legacy Active-only diagnostic, but it is not part of the direct GTAO production path.

## Assumptions

- Target API is ReShade OpenGL in Firestorm; non-OpenGL devices are not supported by this add-on.
- ReShade begin/finish-effects callbacks are paired on the submitting thread. A thread-local depth and mismatch self-healing are used for that cross-callback interval.
- The five pipeline stages restored are exactly the stages modified by `direct_gtao::bind_private_target`; input assembler, geometry/tessellation stages, stream output and scissor box are not changed by direct GTAO.
- Firestorm's alpha path exposes the dynamic alpha blend factors/depth-write state through the existing ReShade callbacks before replay; if not, legacy replay skips instead of guessing.

## Remaining risks

- v1.2.0 has not yet been compiled with the user's Windows/MSVC/ReShade checkout.
- Runtime equality of Firestorm Baseline must still be proven on the target viewer/GPU. The code path is inert with respect to Firestorm render targets, but only target runtime testing can confirm external interactions.
- ReShade/OpenGL driver behavior around resource-destruction callback timing remains implementation-sensitive; the design now fails closed and avoids effect-runtime rebinding from destruction callbacks.
- The existing GTAO raw visibility field is still known to be overwhelmingly dark. This corrective pass isolates state/mode/lifecycle behavior; it does not claim to fix GTAO math.

## Manual Firestorm verification

Use the same scene/camera for all comparisons and keep unrelated ReShade effects disabled except `SL_DirectGTAO_Debug.fx` when requested.

1. Native Firestorm reference
   - Run without `SLAlphaGTAOHook.addon` loaded.
   - Capture a reference screenshot/frame and note UI/alpha appearance.

2. Add-on loaded — Firestorm Baseline
   - Install v1.2.0, launch Firestorm, leave `Operating mode = Firestorm Baseline`.
   - Enable `SL_DirectGTAO_Debug.fx`; deliberately leave its Debug View on Raw AO or N dot V.
   - Expected: visible frame remains native backbuffer; add-on fullscreen passes = 0, scene copies = 0, scene writes = 0, alpha replay draws = 0; GTAO semantics unbound.
   - Compare against step 1.

3. GTAO Diagnostics / Generate Only
   - Select `Inputs only`; verify D0 and N0 views.
   - Select `N dot V only`; view N dot V.
   - Select `Unoccluded baseline only`; view baseline.
   - Select `Core AO`; view Raw AO and Denoised AO.
   - Expected for every diagnostics workload: Firestorm scene-color copies = 0 and writes = 0. Generated-output counters must match only the selected workload.

4. GTAO Active
   - Select `GTAO Active`, leave legacy alpha replay diagnostics off.
   - Expected successful run: 5 add-on fullscreen passes, 1 scene-color copy, 1 scene-color write, raw + denoised generated, N dot V/baseline not generated, 1 state-restore callback.
   - Inspect intended opaque AO before Firestorm's normal alpha layers.

5. GTAO Active + legacy alpha integration diagnostic
   - Enable `Legacy alpha replay diagnostics` only for this test.
   - Verify replay counts and PRE/POST/mask diagnostics if needed.
   - Confirm replay skips safely if captured alpha factors/depth-write state are unavailable.

6. Return to Firestorm Baseline
   - Switch operating mode back to Baseline without restarting Firestorm.
   - Expected next rendered frame: native backbuffer, no new direct GTAO passes/copies/writes/replay, debug FX forced to backbuffer.

7. Lifetime/state stress
   - Resize the viewer window, change a graphics setting that recreates G-buffer targets, and teleport/change scenes.
   - Expected: resource invalidation counter may increase; no stale-handle crash; injection may skip until fresh D0/N0/RT/pipeline state is observed, then resume in non-baseline modes.

## Operating-mode invariant status

- Firestorm Baseline: **satisfied by code path and static validation; target runtime proof pending.** No direct GTAO arm/execute, no scene copy/write, no alpha replay, FX forced to backbuffer.
- GTAO Diagnostics: **satisfied by code path and static validation; target runtime proof pending.** Only requested private resources/passes are generated and Firestorm scene color is never copied/written.
- GTAO Active: **satisfied by code path and static validation; target runtime proof pending.** Core GTAO plus one scene copy/composite, validation probes off, state restore callback mandatory after injected GPU work.
