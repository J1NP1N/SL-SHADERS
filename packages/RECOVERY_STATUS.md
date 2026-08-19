# Package recovery status

Last verified: 2026-08-19

This file is intentionally strict: an archive is listed as **verified in GitHub** only when its GitHub byte count matches the recovered original. The GitHub connector previously truncated several larger binary uploads, so invalid copies were removed rather than left as fake backups.

## Verified directly in GitHub

| Package | Bytes | Status |
|---|---:|---|
| `SL_ProbeBridge_v0_3b_FBOAtlas.zip` | 12,934 | verified |
| `SL_HBAO_v0_5_SmoothAO.zip` | 6,106 | verified |
| `SL_UISeparation_v0_1.zip` | 10,169 | verified |

## Recovered source/package exists, but exact ZIP is not yet stored in GitHub

These originals remain in the ChatGPT Library/recovery set and their versions/state are documented here. They must **not** be described as remotely backed up until an exact transfer is verified.

| Artifact | Bytes | SHA-256 / status |
|---|---:|---|
| `SLNativeBridge_v0_9a_AlphaReplayMask.zip` | 20,765 | `e9b36236c2290a219b38dd2a4e3e93a05f1cfb52296fae817d835b2e11465e2a` |
| `SL_BlackDragon_Volumetric_v0_1d_PrivateShadowCopies.zip` | 15,183 | `06f69112c74d2ba8a808a82131c8fa07b879e887288e284fbcecefeb4a0da55c` |
| `SL_HybridGI_v0_14_BalancedAreaTemporal.zip` | 43,619 | `2ae0f32b98c0f6fa4560237ebda401b2266581ce301558219b23343a5bac9663` |
| `SL_SSGI_v0_3_RayMarch.zip` | 19,540 | `255d899353177180b589770573661392e1876184bc48299615d87206a3d60dc1` |
| `SL_SSR_v0_8_SourceProof.zip` | 46,969 | `69aff91a5afafecb147c73cb1569c34002ec63052401ff4e8331db948783c903` |
| `SL_iMMERSE_FirestormNative_v0_6_RawAOAlphaReceiver.zip` | 30,627 | recovered; checksum to be recorded when transferred |
| `SL_FirestormDepthOverride_v0_2_1.zip` | 34,277 | historical recovered checkpoint; superseded |

## SSR v0.10 MainPassGate recovery artifact

The active recovered SSR state is newer than the v0.8 ZIP above.

| Artifact | Bytes | SHA-256 |
|---|---:|---|
| `SL-SHADERS_ssr-v0.10-mainpassgate.patch` | 282,690 | `a855700f61e81fc1323037c370cdaffc29b8d3a78639a6e59b36fdc1c49cff57` |
| `SL-SHADERS_ssr-v0.10-mainpassgate.bundle` | 66,505 | `c750b2a7d8306b9067528a095653b273ca1b6f11c9bd3c0875bb94ffad22c217` |

Target source commit: `dd7022c80e0acf89295b11bda00ee788ae10d166` (SLProbeLighting v1.6.8 / SSR v0.10 MainPassGate).

The target commit and source tree are recoverable from the uploaded bundle. However, fetching all advertised refs from that bundle fails because its embedded `origin/main` advertises ancestry not fully included. Use the target commit plus the patch as the recovery source; do not treat the embedded remote-tracking ref as a complete clone.

The exact v0.10 C++ source is therefore **recovered**, but it is not yet represented as normal browsable files on GitHub `main`. The project state in `docs/HANDOFF.md` has nevertheless been advanced to v0.10 because the runtime proof and source commit are newer and authoritative.

## Why this distinction exists

A file appearing in the repository is not sufficient proof of a valid binary recovery artifact. Byte count and preferably SHA-256 must match the recovered original.

Project state, exact active test, upstream renderer findings, version map, and installer behavior are documented in GitHub. Binary/source-transfer verification is tracked separately here so a future chat cannot confuse documented state with a byte-valid remote backup.

## Rule for future recovery commits

For every new `SL_*.zip`, patch, bundle, or other recovery artifact, record:

1. exact filename;
2. byte count;
3. SHA-256;
4. active/superseded status;
5. whether the GitHub copy was independently verified;
6. for bundles, the intended target commit and whether advertised refs are complete.

Do not mark an artifact verified merely because an upload API returned success.
