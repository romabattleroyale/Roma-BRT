# SENTINEL ONE — Room Reconstruction Design

**Status:** Proposed for review  
**Date:** 2026-10-17  
**Branch:** `feature/sentinel-house-reconstruction`

## Goal

Deliver a dependable first complete room-mapping workflow in SENTINEL ONE: guided photo/video capture and ARCore plane acquisition feed a single room project, whose 2D plan and navigable 3D model stay consistent and can be corrected manually. Do not generate or publish APK artifacts from CI; CI must validate code only.

## User-visible workflow

1. The user creates/selects a named room and captures photos/videos. Files remain associated with that room and are not silently discarded.
2. The user starts AR scanning. The app reports tracking readiness and collects valid horizontal/vertical ARCore planes with their measured extents and positions, avoiding duplicate/stale plane observations.
3. The app builds a provisional geometry estimate only from measurements actually available. It marks estimates as unconfirmed and tells the user when coverage is insufficient; it must not label the largest detected floor plane as the full room perimeter without qualification.
4. The room editor loads the same persisted geometry for the 2D plan and 3D scene. Dimensions, wall segments, doors and windows use one coordinate convention and stay aligned after edits/reload.
5. The user can manually correct dimensions and openings, save, leave, reopen, and continue. Failed saves or unsupported AR features produce explicit feedback and preserve the last valid project.

## Architecture

- Keep the native Android Kotlin/Jetpack Compose flow and the existing SceneView/Filament renderer.
- Keep photo/video acquisition as evidence linked to the room. In this phase, do not claim that ordinary photos are automatically photogrammetrically reconstructed; a real image-based reconstruction engine is a separate capability unless an existing dependency/code path proves otherwise.
- Introduce/strengthen a room reconstruction domain model and validation so AR plane observations, provisional geometry, openings, persisted JSON, the 2D plan and 3D walls share consistent dimensions and orientation.
- Treat ARCore tracking as optional at runtime. If ARCore/Depth API is unavailable, manual 2D/3D editing and capture remain usable.
- Preserve the existing streaming, Nearby Connections and live-view flows; changes must stay within room scanning/reconstruction and its CI workflow.

## Requirements

- Room-specific capture and project data must never cross between similarly named rooms after sanitization.
- AR observations must be filtered for tracking state and plane type; repeated updates of the same plane must not inflate the plane count.
- Estimated dimensions must have bounds and provenance; estimates remain unconfirmed until the user confirms measurements.
- Openings must be clamped to wall length, must not overlap, and must be represented identically in 2D and 3D.
- Save operations must be recoverable and invalid/corrupt JSON must not crash the editor.
- User-facing status must distinguish capture, AR tracking, provisional estimate, manually confirmed geometry and save failures.
- CI must run Kotlin compilation and relevant automated tests/checks but must not run the APK packaging task or upload an APK artifact.
- No merge to main and no claim of device verification without a real device run.

## Acceptance criteria

1. A named room can be captured, reopened, and retains its own files and geometry.
2. With supported ARCore, valid tracked plane observations create a clearly provisional estimate; with no valid floor or inadequate coverage, the app explains what is missing and does not overwrite a valid project with a false estimate.
3. Editing dimensions or openings updates the 2D and 3D views consistently; no opening extends beyond its wall or intersects another opening.
4. Save/reopen round-trips the geometry, including openings and confirmation state; malformed old project files fall back safely without crashing.
5. ARCore unsupported, permission/session errors and save errors leave capture and manual editing usable and explain the limitation.
6. CI succeeds on the source branch while producing no APK artifact.
7. A final report distinguishes automated verification from the remaining physical-device acceptance checks.

## Explicit limitations

- ARCore plane extents are observed surfaces, not a guaranteed complete architectural floor perimeter.
- A photo/video folder alone is not a reconstructed 3D model. True photogrammetry or neural image reconstruction requires an actual implemented engine, compute strategy and validation; do not simulate this by relabeling captured files.
- Physical camera, tracking quality, rendering and lifecycle behavior must be checked on the user's Xiaomi M11i 5G before calling the release device-verified.
