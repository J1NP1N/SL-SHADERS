SL SSR Temporal v0.1 - Reprojected History

WHAT THIS IS
- Separate temporal effect; v0.35 remains the trace + spatial resolve producer.
- Tiny ReShade add-on exposes v0.35's private resolved/meta textures to this FX.
- Reuses the already-proven Firestorm inv_modelview_delta reprojection contract from HybridGI.

INSTALL
1. CLOSE FIRESTORM. This package builds/installs an .addon.
2. Put this SL_*.zip in the Downloads folder used by SL_InstallLatest.ps1.
3. Run the installer. It builds SLSSRTemporalLink.addon and installs both addon + FX.
4. Start Firestorm.

RESHade ORDER (IMPORTANT)
1. SL SSR v0.35 - Legacy Resolve
2. SL SSR Temporal v0.1 - Reprojected History

FIRST TEST
- Keep v0.35 Long-Ray Ghost Fade OFF.
- Temporal Display -> Link / motion status: healthy = cyan/green-ish with link blue=1 and motion green=1; red means link missing.
- Temporal Display -> History acceptance: static opaque receivers should go green; disocclusions/avatar edges should reject red.
- Temporal Display -> Reprojected motion pixels: slowly pan camera and verify motion responds.
- Temporal Display -> Temporal resolved SSR: compare against Current resolved SSR input while holding camera still, then while panning slowly.
- Return Final temporal correction and report any trails on avatar/geometry.

NOTES
- v0.1 is conservative: it does not resurrect old SSR when the current frame has no hit.
- No object velocity vectors exist; moving avatars rely on depth/normal history rejection.
- Temporal is independently toggleable. Disabling it returns rendering to v0.35.
- ReShade Performance Mode must remain off because the link add-on mirrors runtime uniforms by name.
