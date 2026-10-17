# SENTINEL ONE — Room reconstruction implementation plan

**Date:** 2026-10-17  
**Branch:** `feature/sentinel-house-reconstruction`  
**Spec:** `docs/superpowers/specs/2026-10-17-room-reconstruction-design.md`

## Product rule: make the map obvious

The user should understand the workflow without technical knowledge. Keep the screen organized into three numbered steps:
1. **Raccogli foto e video** — capture evidence for this room.
2. **Misura la stanza** — scan with AR when available; explain simply what to do and when the estimate is uncertain.
3. **Sistema la piantina** — show the 2D plan first, then dimensions/openings and the 3D preview.

Use short Italian instructions, clear progress/status, and plain-language error messages. Never imply that photos alone created a true 3D reconstruction. Do not add complex onboarding, new libraries, or unrelated app changes.

## Task 1 — Make room-project persistence safe and testable
- File: `native-android/app/src/main/java/com/sentinelone/nativeapp/HouseReconstructionActivity.kt`
- Extract/strengthen small pure helpers for room-name normalization, geometry bounds, opening normalization, and room project JSON decoding/encoding.
- Ensure corrupt/missing project data falls back safely; save errors remain visible; a failed estimate never overwrites the last valid geometry.
- Ensure sanitized room names cannot accidentally share capture folders or AR evidence/project files. Add collision-safe handling where needed rather than silently merging different raw names.
- Tests: round-trip dimensions/openings/confirmation; malformed JSON; dimensions out of range; openings beyond wall bounds/overlap; room-name collisions.

## Task 2 — Make AR scan produce honest provisional measurements
- File: `native-android/app/src/main/java/com/sentinelone/nativeapp/HouseReconstructionActivity.kt` (and the existing AR scan activity if that is where plane collection lives).
- Filter observations to tracked, relevant planes; update observations by plane identity rather than counting every frame as a new plane.
- Keep a clear readiness state and use only valid measured extents for a **provisional** estimate. Do not treat the largest detected plane as a guaranteed full room perimeter.
- If tracking/coverage is insufficient, show the user what to do next and preserve existing saved geometry. Keep manual editing usable if ARCore is unavailable or errors.
- Tests: invalid/untracked planes ignored; repeated plane updates deduplicated; invalid dimensions rejected; insufficient data does not overwrite a saved project.

## Task 3 — Simplify the editor into a guided, consistent map workflow
- File: `native-android/app/src/main/java/com/sentinelone/nativeapp/HouseReconstructionActivity.kt`
- Group the existing controls into three clearly numbered steps, in simple Italian; make the 2D plan the main visual and the 3D model a secondary preview.
- State plainly whether measurements are provisional or confirmed and provide one obvious action to confirm real measurements.
- Keep width/depth, wall orientation, and door/window coordinates shared between the 2D and 3D views. Preserve editing controls but avoid introducing a new complex workflow.
- Make save state/error visible and ensure changes to dimensions normalize openings before rendering/saving.
- Tests: verify UI text and shared model behavior where practical; run Kotlin compilation and available automated checks.

## Task 4 — Verify CI without creating APKs
- File: `.github/workflows/native-android.yml`
- Remove `assembleDebug` and APK artifact upload steps. Keep source validation only (Kotlin compilation and appropriate unit tests/checks); do not add APK build, signing, or upload steps.
- Ensure the workflow triggers on the feature branch PR and fails on compile/test errors.
- Verification: inspect the final workflow and run the repository's available Gradle compile/test tasks. Report exact commands and outcomes; do not claim physical-device verification.

## Task 5 — Final audit and handoff
- Review the diff for scope, accidental unrelated changes, room-data safety, and misleading reconstruction claims.
- Verify the final commit and latest GitHub Actions run status/jobs; confirm no APK artifact was generated/uploaded by this workflow.
- Report what is implemented, what automated checks passed/failed, and the remaining checks that require the user's Xiaomi M11i 5G. Do not ask the user to install/test until source checks are complete.

## Constraints
- Work only on `feature/sentinel-house-reconstruction`; do not merge to main.
- Preserve streaming, Nearby Connections, and live-view functionality.
- No new dependencies unless an existing implementation makes them strictly necessary.
- No APK packaging or artifact generation in CI.
- Photos/videos remain room evidence; do not call them photogrammetry or claim automatic image-based 3D reconstruction.
