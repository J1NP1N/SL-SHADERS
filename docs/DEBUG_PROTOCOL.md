# Runtime debug protocol

The project uses a build -> run in Firestorm -> report back loop. Diagnostics are part of the implementation, not optional polish.

## Required diagnostic layers

Each experimental renderer feature should expose enough views/readouts to isolate the stage that failed. As applicable, include:

1. **Bridge / registration status**
   - required semantic registration
   - matrices / viewport registration
   - source availability
   - source identity where ambiguity is possible

2. **Raw native inputs**
   - depth
   - normals
   - scene-linear / pre-tonemap color
   - diffuse/material buffers
   - specular/roughness/metallic/AO channels
   - shadow/probe inputs where used

3. **Intermediate algorithm state**
   - ray-hit / visibility mask
   - raw hit color or raw gathered irradiance
   - AO/GI/SSR unweighted contribution
   - temporal history validity/confidence
   - rejection/disocclusion mask when temporal accumulation exists

4. **Final contribution / composite**
   - real-scale contribution before debug amplification
   - debug-amplified contribution when the real signal is subtle
   - final composite

5. **Numeric source proof when a native buffer is suspect**
   - texture/source identifier where available
   - dimensions and format
   - channel min/max/average or another explicit nonzero test
   - capture stage/frame/lifetime information

## Diagnostic design rules

- Do not gate geometry/ray diagnostics on unrelated material validity. If material data fails, the geometry tracer should still be testable when technically possible.
- Status colors must have a documented channel meaning. Prefer direct named readouts when the state is too complex for a color code.
- A semantic being bound proves only that *something* is bound; it does not prove the payload is correct. Provide raw-channel or numeric proof for ambiguous native buffers.
- When sampling only part of a frame for numeric analysis, document the sample pattern and require the test target to occupy those regions.
- Keep diagnostic technique names/version identifiers unambiguous so ReShade cannot silently leave an older technique active.
- Any build sent for runtime testing should state exactly which diagnostic views the tester should return.

## Report-back format

A useful runtime report contains, as applicable:

```text
Viewer / build label:
ReShade effect/add-on label:
Bridge status:
Raw source status:
Requested diagnostic view(s):
Numeric readout(s):
Compile/runtime errors:
Screenshot(s):
Observed behavior while static / moving camera / moving avatar:
```

The exact requested fields may be shorter for a narrowly scoped test. The goal is to remove interpretation ambiguity before changing the algorithm.
