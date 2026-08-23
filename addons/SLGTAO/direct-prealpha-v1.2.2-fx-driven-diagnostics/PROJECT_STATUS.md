# SL Direct GTAO — v1.2.2 FX-driven diagnostics

Date: 2026-08-23
Branch: `agent/direct-gtao-integration`

## Runtime observation
The v1.2.1 UI still had two independent diagnostic selectors: the add-on chose what to generate while `SL_DirectGTAO_Debug.fx` chose what to display. A mismatch could leave the selected semantic unbound, which looked like a dead or black diagnostic even when the add-on itself was otherwise functioning.

## v1.2.2 correction
- `GTAO Diagnostics / Generate Only` now treats the FX `DIRECT GTAO - Debug View` selector as the request for what private resource to generate.
- Raw AO / Denoised AO request the core AO workload.
- D0 / N0 request inputs-only export and zero GTAO fullscreen passes.
- N dot V requests only the N·V validation pass.
- Unoccluded slice baseline requests only the baseline validation pass.
- The add-on overlay is status-only for diagnostic workload; there is no second diagnostic generation selector to get out of sync.
- `GTAO Active` no longer exposes duplicate scene-target diagnostic outputs. It always performs the production final GTAO composite.
- Missing/unbound FX semantics render a magenta checker rather than ambiguous black.
- Diagnostic selection does not change the operating mode; Baseline remains inert and Active remains the production path.

## Static verification
- `tests/validate_source.py`: PASS
- `cmake/ValidateSource.cmake`: PASS
- generated shader synchronization check: PASS
- C++ brace/parenthesis balance checks: PASS

## Handoff artifact
`SL_GTAO_Direct_v1_2_2_FXDrivenDiagnostics.zip`
SHA-256: `26ded5570d03ea460229bf2498d0ff0ef7cab7d169b8194d9bebc25f6ffcdf67`

The installable artifact was handed off in chat. It has not yet been mirrored as a binary under `packages/latest/` in this commit.

## Runtime test
1. Install/build with Firestorm closed.
2. Set `Operating mode = GTAO Diagnostics / Generate Only`.
3. Enable `SL_DirectGTAO_Debug.fx`.
4. Change only the FX `DIRECT GTAO - Debug View` selector.
5. D0/N0 should report `Generation workload: Inputs only (D0/N0)`.
6. N dot V should report `Generation workload: N dot V` after one frame.
7. Unoccluded slice baseline should report the matching baseline workload after one frame.
8. Raw/Denoised should report `Generation workload: Core AO (raw + denoised)`.
9. A magenta checker means the selected semantic is not available yet; it should not be interpreted as valid diagnostic data.
