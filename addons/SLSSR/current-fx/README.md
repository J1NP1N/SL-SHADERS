# Current SSR FX source transfer status

The v0.31-v0.34 session bundle contains the full current shader source at the intended path:

`addons/SLSSR/current-fx/SL_SSR_v0_1_LegacyFirst.fx`

Verified bundle object:

- Git blob SHA: `08f9c78e0eeb50ec9c3f08c0e278afc9f841a78a`
- size: 69,778 bytes
- technique: `SL SSR v0.34 - Ghost Cull`

The connected GitHub write interface in the importing chat did not expose a reliable local-file upload path for this 69 KB source file, so the normal `.fx` file is **not yet present here**. Do not claim otherwise.

The exact v0.30 -> v0.34 source delta is committed at:

`history/ssr/ssr-v0.30-to-v0.34-session.patch`

The exact uploaded bundle is identified/checksummed at:

`history/ssr/SSR_v0.31-v0.34_BUNDLE_PROVENANCE.md`

Next time a direct repository file-upload path is available, import the full FX and verify that GitHub reports blob SHA `08f9c78e0eeb50ec9c3f08c0e278afc9f841a78a`; then replace this transfer-status note with the actual source file.
