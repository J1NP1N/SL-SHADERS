# Current SSR FX backbone

Current integration baseline: `SL_SSR_v0_49_AvatarThicknessTrace.fx`.

Native inputs:

- D0 — `SL_DEPTH_PRIMARY_NATIVE`
- Dstatic — `SL_DEPTH_BACKGROUND`
- Cstatic — `SL_COLOR_BACKGROUND`
- DavatarBack — `SL_DEPTH_AVATAR_BACK`

v0.49 uses independent world and avatar traces. The world branch is Dstatic/Cstatic. The avatar branch accepts geometry only inside the native `[D0,DavatarBack]` interval.

The original secondary avatar-shaped ghost is essentially fixed. Current work should target static-world resolve/tracing quality, temporal stability, or Hi-Z without altering the proven avatar-thickness architecture.

The exact v0.49 source is archived under `v0.49-source/` as gzip+base64 chunks because this connector cannot upload a local artifact directly. Run `restore_v0.49.py` in that directory to reconstruct `SL_SSR_v0_49_AvatarThicknessTrace.fx` byte-for-byte.

See `docs/HANDOFF.md` and `docs/BACKBONE_v0.49.md` before branching.
