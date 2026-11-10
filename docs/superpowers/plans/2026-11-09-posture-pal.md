# PosturePal Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline in this session. Track verified steps below.

**Goal:** Deliver the native Mac posture reminder specified by PRD v1.0, with explicit hardware-validation gates.
**Architecture:** A pure Swift posture/timing core with deterministic tests, Vision body pose plus face landmarks, AVFoundation camera pipeline, and a SwiftUI/AppKit menu bar app. Frames and keypoints stay in memory. Persist only preferences and scalar calibration.
**Tech Stack:** Swift Package Manager, SwiftUI, AppKit, Vision, AVFoundation, UserNotifications; no external packages.
**Spec:** ../../../../坐姿提醒工具-PRD-v1.0.md (canonical copy is in the parent outputs directory).

## Global Constraints
- Current Apple Silicon Mac only; integrated front camera; no autostart or auto camera on application launch.
- Head down, lateral lean and shoulder-line changes are candidates, not medically validated claims.
- 10s calibration, 20s deviation, 3s recovery, 10min cooldown, 60s minimum posture-notification interval, 45min activity reminder.
- No image/video/history storage, cloud, telemetry, medical score or rounded-shoulder diagnosis.
- A successful build or synthetic test does not satisfy actual-person accuracy or 60min energy verification.

## Review Focus
- Missing/invalid points and long sampling gaps must clear pending posture timers.
- Stop/pause/lock/failure must release camera and must not resurrect manually stopped capture.
- Snoozed or suppressed notifications must not accumulate stale alerts.
- Natural facial/shoulder movement and mirrored preview must not invert geometry or pretend to be validated.
- Saved preferences and baseline decoding must validate numerical ranges and version.

### Task 1: Pure posture core
Files: Package.swift, Sources/PostureCore/{Geometry,Judgement,Session}.swift, Tests/PostureCoreTests/CoreTests.swift.
Interfaces: PoseMetrics, CalibrationAccumulator, PostureJudge.update(metrics:now:), SessionClock.
- [ ] Write tests for stable calibration, head/shoulder normalization, dwell/recovery/cooldown, missing input, clock gaps, snooze, activity reset and preference validation.
- [ ] Observe failing tests before implementation, implement, run complete `swift test`.

### Task 2: Camera and native app
Files: Sources/PosturePal/{CameraPipeline,AppModel,Views,Main}.swift.
Interfaces: CameraPipeline.start/stop with generation cancellation; AppModel lifecycle and render state consume core types.
- [ ] Use AVFoundation/Vision with serial frame work, confidence gating and maximum 5 inference FPS.
- [ ] Add mirrored preview, keypoint overlay, stable baseline calibration and validation diagnostics with no saved frames.
- [ ] Add status item, settings, notification permission/status, snooze/pause/stop, lock/sleep lifecycle and activity timer.
- [ ] Build under Swift 6 toolchain and execute core tests.

### Task 3: Packaging, verification and handoff
Files: scripts/build-app.sh, README.md, CHANGELOG.md, docs/VALIDATION.md, AGENTS.md.
- [ ] Build ad-hoc signed .app with camera usage description, stable bundle identifier and resource plist.
- [ ] Verify package, signature, no unintended network dependencies, safe launch and zero automatic capture.
- [ ] Perform whole-code review; fix material issues with regression tests.
- [ ] Record actual checks, remaining real-camera and energy gates; do not claim field accuracy without user trial.

## Execution ledger

- Implemented native validation app plus pure core; final gate remains hardware trial.
- Full Xcode selected after CLT XCTest absence. Test-first evidence limitations recorded in VALIDATION.md.
- Independent final code review completed; fixed generation race, first-frame watchdog, reminder aggregation, partial calibration/geometry, and window reopening.
- Added scale-jump rejection with stable reentry. No camera access performed.
- User is unavailable for camera trial, so accuracy/device/energy gates remain pending; goal must remain active.
