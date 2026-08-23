# Firestorm Renderer Audit Evidence

Pinned source revision used by the current canonical evidence set:

- Repository: `https://github.com/FirestormViewer/phoenix-firestorm`
- Branch: `master`
- Commit: `3e20e83b3ea01bb5ae3156d301d0d76ca88dd294`
- Platform scope: Windows
- Renderer scope: OpenGL

## Canonical evidence records

- `evidence/FS-FRAME-001.md`
- `evidence/FS-GBUF-001.md`
- `evidence/FS-POST-001.md`
- `evidence/FS-CAMERA-001.md`
- `evidence/FS-TEMPORAL-001.md`
- `evidence/FS-DEPTHSTATE-001.md`

`FS-ALPHA-001` is not included in this checkpoint because that audit is still in progress.

A consolidated `FIRESTORM-RENDERER-MAP.md` should be added separately after synthesis of the accepted evidence set.

## Known correction to preserve

`FS-TEMPORAL-001` source-proves that the main model-view delta calculation occurs in
`LLPipeline::renderGeomDeferred()`. This supersedes the earlier location claim in
`FS-CAMERA-001` that attributed that calculation to `updateCull()`.

The original evidence records are intentionally preserved rather than rewritten.
