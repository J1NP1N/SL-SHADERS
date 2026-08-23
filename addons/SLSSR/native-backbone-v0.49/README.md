# Native SSR backbone for v0.49

This directory archives the exact native source/tooling used by the validated v0.49 runtime backbone.

Because the GitHub connector used for this checkpoint cannot directly upload local files, the exact native source set is stored as a deterministic tar.gz encoded into three base64 text parts. Run `restore_native_backbone.py` to verify the archive checksum and extract the files.

Archive SHA-256:

`2a7cf9fe266bb165b85c63ffe7b2520c563ef0ec223a0b93594ad59463ad4c52`

Restored files:

- `background-scene-pair-v0.3.5/Apply-SLSSRBackgroundScenePair-v0.3.5.ps1`
- `background-scene-pair-v0.3.5/SLBackgroundSceneLink_v0_3.cpp`
- `background-scene-pair-v0.3.5/build-msvc.bat`
- `background-scene-pair-v0.3.5/SL_BackgroundScenePair_v0_1c.fx`
- `avatar-thickness-v0.3.6b/Apply-SLSSRAvatarBackDepth-v0.3.6b.ps1`
- `avatar-thickness-v0.3.6b/SLBackgroundSceneLink_v0_4.cpp`
- `avatar-thickness-v0.3.6b/SL_AvatarThicknessProof_v0_1.fx`
- `avatar-thickness-v0.3.6b/build-msvc.bat`

Validated native semantics:

- `SL_DEPTH_PRIMARY_NATIVE` = D0
- `SL_DEPTH_BACKGROUND` = Dstatic
- `SL_COLOR_BACKGROUND` = Cstatic
- `SL_DEPTH_AVATAR_BACK` = DavatarBack

Do not replace DavatarBack with an FX heuristic. The native avatar backface mask was runtime-proven before v0.49 integration.
