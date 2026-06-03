# Pub.dev Deployment Plan — image_forge, image_forge_core, video_forge, pixel_surface

**Status:** Awaiting approval. No code changes have been made.

**Date:** 2026-06-03
**Scope:** 4 packages in the `rust_image` monorepo
- `packages/image_forge` (full engine + face beauty + GPU preview surface)
- `packages/image_forge_core` (lightweight engine)
- `packages/video_forge` (FFmpeg + Rust video engine)
- `packages/pixel_surface` (Flutter GPU texture bridge)

**Goal:** All 4 packages ready for `dart pub publish` to pub.dev at version `1.0.0` (or the next released version of each), with passing tests, passing analyzer, passing `dart pub publish --dry-run`, and pub.dev Pub Points parity with established FFI packages like `flutter_rust_bridge`.

---

## 1. Verification results (current state)

| Package | Version | README | LICENSE | CHANGELOG | `flutter analyze` | `flutter test` | `dart pub publish --dry-run` |
|---|---|---|---|---|---|---|---|
| `image_forge` | 1.0.0 OK | full | Apache-2.0 | 1.0.0 | clean | 93/93 pass | 0 warnings |
| `image_forge_core` | 1.0.0 OK | full | Apache-2.0 | 1.0.0 | clean | 81/81 pass | 0 warnings |
| `video_forge` | 2.4.0 BLOCK | full | Apache-2.0 | 2.4.0 | 6 errors | 1 file fails to load | 0 warnings |
| `pixel_surface` | 1.1.0 BLOCK | sparse | Apache-2.0 | 1.1.0 | clean | 5/5 pass | 0 warnings |

All 4 packages already pass `dart pub publish --dry-run` for archive validation. The blockers are **metadata hygiene** and **one broken test file** in `video_forge`.

---

## 2. Cross-cutting issues (all 4 packages)

| # | Issue | Why it matters | Affected |
|---|---|---|---|
| C1 | `resolution: workspace` line in `pubspec.yaml` | Required for melos + pub workspace. `dart pub publish` from inside a workspace member is supported in Dart 3.6+, but the safest workflow is to keep this line for `pub get`/test and **strip it just before `dart pub publish`**, then re-add. Will confirm at publish time. | all 4 |
| C2 | Missing `license:` field in `pubspec.yaml` | Pub.dev shows the verified-license badge only when this is set. Without it, pub points drop. | image_forge, video_forge, pixel_surface |
| C3 | Missing `.pubignore` | Without it, `build/`, `target/`, `*.iml`, `.dart_tool/`, etc. can end up in the published tarball. | image_forge_core, video_forge, pixel_surface |
| C4 | Native platform build files reference an old version | Mismatch between pubspec version and podspec/gradle version looks unprofessional and trips up `pod lib lint` / `gradle build`. | video_forge, pixel_surface |

---

## 3. Per-package issues

### 3.1 `image_forge` (smallest set of fixes)
- **I-1** Add `license: Apache-2.0` to `pubspec.yaml:7`.
- **I-2** `ios/image_forge.podspec` and `macos/image_forge.podspec` are still the **default Flutter FFI template** (`s.version = '0.0.1'`, `s.summary = 'A new Flutter FFI plugin project.'`, `s.homepage = 'http://example.com'`, `s.author = 'Your Company' <email@example.com>`). Replace with real values matching `pubspec.yaml`.

### 3.2 `image_forge_core` (already the cleanest)
- **C-2a** Stray `image_forge_core.iml` in package root (in addition to `melos_image_forge_core.iml`). Add `.pubignore` to drop `*.iml`, `build/`, `target/`, `.dart_tool/`, etc. (mirror `image_forge/.pubignore`).
- No other changes.

### 3.3 `video_forge` (needs the most work)
- **V-1 CRITICAL** `test/types/video_forge_error_test.dart` has 6 analyzer errors at lines 109, 125, 142: the `when()` and `map()` calls are missing the new `cooldownActive` and `recoveryBudgetExhausted` branches added in `lib/src/frb_generated/error.dart:36,42`. This is why `flutter analyze` fails and `flutter test` cannot even load the file. Fix the test file (add the two missing branches in all three call sites).
- **V-2** `pubspec.yaml:8` version is `2.4.0` → change to `1.0.0` per your request.
- **V-3** Rewrite `CHANGELOG.md` to keep only a `## 1.0.0` section that summarizes the current feature set (compress, transcode, thumbnails, audio mix, decoder cache, output profiles, prefetch, release-token pool). The 2.x history is dropped (this is the "fresh start" 1.0 release).
- **V-4** Add `license: Apache-2.0` to `pubspec.yaml`.
- **V-5** Add `.pubignore` (mirror `image_forge/.pubignore`; also drop `ios/Frameworks/`, `rust/target/`, `hook/build/`).
- **V-6** `macos/video_forge.podspec` has `s.version = '2.3.0'` → update to `1.0.0`. (There is no `ios/video_forge.podspec`; only `ios/Frameworks/` exists — confirm whether an iOS podspec is needed or if it is auto-generated.)
- **V-7** `android/build.gradle:2` has `version = "2.4.0"` → update to `1.0.0`.

### 3.4 `pixel_surface`
- **P-1** `pubspec.yaml:6` version is `1.1.0` → change to `1.0.0` per your request.
- **P-2** Rewrite `CHANGELOG.md` to keep only `## 1.0.0` (initial pub release). The 1.1.0 history is dropped — the pool / memory-warning / recycling work is summarized in the single 1.0.0 entry.
- **P-3** Add `license: Apache-2.0` to `pubspec.yaml:7`.
- **P-4** Add `topics:` and `issue_tracker:` to `pubspec.yaml` to match the other 3 packages and gain pub points.
- **P-5** Add `.pubignore` (mirror `image_forge/.pubignore`; also `build/`, `rust/target/`).
- **P-6** `android/build.gradle:2` has `version = "1.0-SNAPSHOT"` → update to `1.0.0`.
- **P-7** `README.md` is ~60 lines vs ~200 for the others. Add a Quick Start, Platform Support table, App-Size section, and Contributing section so it has parity with the other packages and helps the pub points "Provide documentation" score.

---

## 4. Comparison with `flutter_rust_bridge` (the canonical FFI package on pub.dev)

| Metadata | `flutter_rust_bridge` | our 4 packages |
|---|---|---|
| License field | MIT | only image_forge_core |
| Repository / Homepage | both | all 4 |
| Topics | yes | only pixel_surface is missing |
| Issue tracker | yes | only pixel_surface is missing |
| Description (concise, 60-180 chars) | yes | all 4 |
| README has Quick Start + Platform + Examples | yes | all except pixel_surface |
| `.pubignore` keeps tarball small | yes | only image_forge |

---

## 5. Execution plan (no code yet — explicit approval required before each phase)

### Phase 0 — Approvals
- Confirm CHANGELOG history policy (drop / keep-as-pre-1.0 / keep-above-1.0).
- Confirm `pixel_surface` 1.0 scope (ship 1.1 work in 1.0 / strip it / gate it).
- Confirm publish mode (independent / workspace / manual).
- Confirm whether to run Rust unit tests (`cargo test` in 3 crates) this round.

### Phase 1 — Fix `video_forge` test (blocking)
1. Edit `test/types/video_forge_error_test.dart` to add the two missing `cooldownActive` / `recoveryBudgetExhausted` branches to the three `err.when(...)` / `err.map(...)` calls. Use placeholder branches that return a constant string.
2. `flutter test` and `flutter analyze` both green for `video_forge`.

### Phase 2 — Reset versions and align native config
3. Set `version: 1.0.0` in `packages/video_forge/pubspec.yaml` and `packages/pixel_surface/pubspec.yaml`.
4. Rewrite both CHANGELOG.md to a single `## 1.0.0` entry (per Phase 0 policy).
5. Update version strings in `macos/*.podspec` and `android/build.gradle` to match.

### Phase 3 — Pub.dev metadata hygiene
6. Add `license: Apache-2.0` to image_forge, video_forge, pixel_surface pubspec.yaml.
7. Add `topics:` and `issue_tracker:` to pixel_surface.
8. Update `image_forge/ios/image_forge.podspec` and `image_forge/macos/image_forge.podspec` (kill default template).
9. Drop the duplicate `image_forge_core.iml` and add a proper `.pubignore` to image_forge_core, video_forge, pixel_surface.

### Phase 4 — README parity
10. Expand `pixel_surface/README.md` to match the structure of image_forge / image_forge_core / video_forge READMEs (Quick Start, Platform Support table, App Size note, Installation, Examples, Build & Test, Contributing, Links).

### Phase 5 — Re-verification
11. `dart pub get` at root.
12. `dart run melos exec --scope={image_forge,image_forge_core,video_forge,pixel_surface} -- flutter analyze --no-fatal-infos` — must be clean on all 4.
13. `flutter test` in each of the 4 packages — must be 100% green.
14. `dart pub publish --dry-run` in each of the 4 — must report 0 warnings.

### Phase 6 — Publish
15. Per Phase 0 decision, run `dart pub publish` (independent) or `dart pub workspace publish` (workspace).
16. Verify each package on pub.dev: `/packages/image_forge`, `/packages/image_forge_core`, `/packages/video_forge`, `/packages/pixel_surface`.

### Phase 7 — Optional: Rust unit tests
17. `cd packages/image_forge/rust && cargo test --features gpu,blurhash`
18. `cd packages/image_forge_core/rust && cargo test --features gpu,blurhash`
19. `cd packages/video_forge && cargo test -p video_forge`

---

## 6. Risks and open questions

1. **Workspace publishing**: Dart 3.6 supports `dart pub publish` from a workspace member, but the `resolution: workspace` line is still controversial in some pub.dev discussions. Mitigation: strip the line at publish time, re-add after.
2. **Podspecs**: I have not run `pod lib lint` on any podspec — that is a final-step verification. The default-template `image_forge/ios/.../image_forge.podspec` will fail `pod lib lint` until I-2 is fixed.
3. **Rust tests** were not run this round. If the Dart-side fixes cause any transitive breakage, the Rust test suite is the next line of defense.
4. **`video_forge` iOS podspec** — only `ios/Frameworks/` exists; no `ios/video_forge.podspec`. This may be intentional (auto-generated by the hook), or it may be a gap. Will check at Phase 1.

---

## 7. Sign-off

Approve this plan and the assumptions below to start Phase 1.

| Decision | Default | Override |
|---|---|---|
| CHANGELOG history for video_forge and pixel_surface | Drop (single 1.0.0 entry that summarizes the current feature set) | |
| pixel_surface 1.0.0 scope | Ship the 1.1.0 work (pool, memory warnings, recycling) as part of 1.0.0 | |
| Publish mode | Independent — one `dart pub publish` per package | |
| Rust tests this round | Run them after Dart-side fixes | |
| `resolution: workspace` line | Keep during dev; strip + re-add around `dart pub publish` | |
