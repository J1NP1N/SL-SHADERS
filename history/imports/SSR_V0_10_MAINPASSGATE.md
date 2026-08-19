# SSR v0.10 MainPassGate — recovered import note

Recovered 2026-08-19 from user-provided artifacts:

- `SL-SHADERS_ssr-v0.10-mainpassgate.patch`
- `SL-SHADERS_ssr-v0.10-mainpassgate.bundle`

Target commit:

`dd7022c80e0acf89295b11bda00ee788ae10d166`

Parent:

`8c3cd8b68ac8fd1acd0fef3f83d77a4284ebda5a`

Subject:

`SSR v0.10 MainPassGate: prove specularRect capture; fix wrong-draw selection`

## What the commit contains

The recovered commit adds the full active source tree under:

`addons/SLProbeLighting/current-ssr-v0.10-mainpassgate/`

Files in that source tree:

- `CMakeLists.txt`
- `README.txt`
- `RUN_AND_INTERPRET.txt`
- `SLProbeLighting.cpp`
- `SL_SSR_v0_1_LegacyFirst.fx`
- `SOURCE_AUDIT.txt`
- `build-msvc.bat`

The commit also updates `README.md` and `docs/HANDOFF.md` for the v0.10 runtime conclusion.

## Root cause recorded by the commit

The previous black `specularRect` results came from latching the wrong deferred draw. Firestorm produces 512x512 probe-space deferred passes and the full-resolution main deferred pass at the same `refmapCount`; the analyzer froze a probe texture before the main pass.

v0.9 ReadProof exposed this by reporting texture dimensions and source-read metadata. v0.10 MainPassGate gates source-proof capture to draws whose height is >=75% of the tallest observed specular draw and fixes snapshot proof reads to use the snapshot's own dimensions.

Runtime on the red-specular legacy test object then selected the full-resolution main attachment (`tex 8, 3840 x 2027` in that run), read clean nonzero RGB, and obtained matching source/snapshot statistics. Material-source capture is therefore considered proven.

## Next runtime question

Report:

```text
Material class: legacy cyan / PBR magenta
Bridge status
```

No further capture fix should be attempted unless those diagnostics contradict the recovered v0.10 conclusion.

## Bundle caveat

`git bundle verify` accepts the artifact and the target commit/tree are readable, but fetching all advertised refs fails because the bundle advertises `origin/main` ancestry that is not fully included. The embedded remote-tracking ref should not be used as a complete repository restore.

Use `dd7022c` plus the patch as the source-recovery target.

## Integrity

Patch:

- bytes: `282690`
- SHA-256: `a855700f61e81fc1323037c370cdaffc29b8d3a78639a6e59b36fdc1c49cff57`

Bundle:

- bytes: `66505`
- SHA-256: `c750b2a7d8306b9067528a095653b273ca1b6f11c9bd3c0875bb94ffad22c217`

## GitHub import state

At the time of this note, the current project-state documentation has been advanced to v0.10, but the 216 KB recovered `SLProbeLighting.cpp` has not yet been transferred as a normal GitHub blob through the connected chat API. Do not claim the source tree is fully backed up on GitHub until that transfer is verified.
