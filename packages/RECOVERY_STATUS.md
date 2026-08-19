# Package recovery status

Last verified: 2026-08-19

This file is intentionally strict: an archive is listed as **verified in GitHub** only when its GitHub byte count matches the recovered original. The GitHub connector silently truncated several larger binary uploads, so those invalid copies were removed from `main` rather than left as fake backups.

## Verified directly in GitHub

| Package | Bytes | Status |
|---|---:|---|
| `SL_ProbeBridge_v0_3b_FBOAtlas.zip` | 12,934 | verified |
| `SL_HBAO_v0_5_SmoothAO.zip` | 6,106 | verified |
| `SL_UISeparation_v0_1.zip` | 10,169 | verified |

## Recovered source/package exists, but exact ZIP is not yet stored in GitHub

These originals remain in the ChatGPT Library/recovery set and their versions/state are documented here. They must **not** be described as remotely backed up until an exact transfer is verified.

| Package | Original bytes | SHA-256 |
|---|---:|---|
| `SLNativeBridge_v0_9a_AlphaReplayMask.zip` | 20,765 | `e9b36236c2290a219b38dd2a4e3e93a05f1cfb52296fae817d835b2e11465e2a` |
| `SL_BlackDragon_Volumetric_v0_1d_PrivateShadowCopies.zip` | 15,183 | `06f69112c74d2ba8a808a82131c8fa07b879e887288e284fbcecefeb4a0da55c` |
| `SL_HybridGI_v0_14_BalancedAreaTemporal.zip` | 43,619 | `2ae0f32b98c0f6fa4560237ebda401b2266581ce301558219b23343a5bac9663` |
| `SL_SSGI_v0_3_RayMarch.zip` | 19,540 | `255d899353177180b589770573661392e1876184bc48299615d87206a3d60dc1` |
| `SL_SSR_v0_8_SourceProof.zip` | 46,969 | `69aff91a5afafecb147c73cb1569c34002ec63052401ff4e8331db948783c903` |
| `SL_iMMERSE_FirestormNative_v0_6_RawAOAlphaReceiver.zip` | 30,627 | recovered; checksum to be recorded when transferred |
| `SL_FirestormDepthOverride_v0_2_1.zip` | 34,277 | historical recovered checkpoint; superseded |

## Why this distinction exists

The connected GitHub API path available in this chat handles normal source/docs correctly, but larger binary ZIP payloads were observed to truncate around 15 KB. A file appearing in the repository is therefore not sufficient proof of a valid package. Byte count and preferably SHA-256 must match the recovered original.

The project state, exact active test, upstream renderer findings, version map, and installer behavior are fully documented in GitHub. Package binary verification is tracked separately here so a future chat cannot mistake an invalid archive for a usable recovery point.

## Rule for future package commits

For every new `SL_*.zip` package, record:

1. exact filename;
2. byte count;
3. SHA-256;
4. whether the GitHub copy was independently verified;
5. whether it is FX-only or requires Firestorm closed for native add-on installation.

Do not mark a package verified merely because an upload API returned success.
