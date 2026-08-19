# SSR v0.31–v0.34 bundle provenance

Uploaded recovery artifact: `SL-SHADERS_ssr-v0.31-v0.34-session.bundle`

- Size: 24,390 bytes
- SHA-256: `81e4578444077df9a6dbcc9f7e80c32a6f76500d2fb798bbc5f50ccfb2956d14`
- Bundle prerequisite: `47ba4ad3b9e884ab129f2558410f2c117ed06e2c` (`Advance handoff through SSR v0.30 DeferredCandidate`)
- Bundle HEAD: `fc5d5c5ec5c78a16434ea441495301e811578d50`
- Bundle HEAD tree: `1552aac845472ea71fd73f3220983958735750a1`
- Bundle commit message: `SSR v0.31-v0.34 session: correct the artifact diagnosis; store full FX`

Verified objects recovered from the bundle:

- full current FX blob: `08f9c78e0eeb50ec9c3f08c0e278afc9f841a78`
  - path in bundle tree: `addons/SLSSR/current-fx/SL_SSR_v0_1_LegacyFirst.fx`
  - size: 69,778 bytes
  - technique: `SL SSR v0.34 - Ghost Cull`
- exact session runtime record blob: `17b574ec29edfef5913c0f0d6c4538abfbd7cd19`
  - path: `history/ssr/SSR_v0.31-v0.34_SESSION_RUNTIME.md`
- v0.30 -> v0.34 session patch blob: `48321d06ec9868f59645557c0a09616f765c7dd5`
  - path: `history/ssr/ssr-v0.30-to-v0.34-session.patch`

The bundle is incremental and requires the v0.30 prerequisite commit. It is otherwise internally consistent; the current GitHub `main` was exactly that prerequisite when this artifact was imported.

## Connector limitation

The GitHub connector can safely commit the session state and small text records, but this chat does not have a direct local-file upload primitive for repository blobs. The 69,778-byte FX is therefore **verified inside the uploaded bundle but is not yet claimed as a normal GitHub source file** unless its repository blob is independently confirmed at `08f9c78e0eeb50ec9c3f08c0e278afc9f841a78`.

Do not report the direct FX-source import complete until that SHA is present at the expected repository path.
