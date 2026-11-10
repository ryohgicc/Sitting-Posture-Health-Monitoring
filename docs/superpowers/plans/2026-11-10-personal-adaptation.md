# Personal Adaptation Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans to implement in the current session; the user has already requested implementation.

**Goal:** Build a guided, cancellable personal reference and reminder-boundary trial.
**Architecture:** Pure PostureCore session accumulates bounded in-memory scalar samples and returns an uncommitted profile. AppModel suppresses notifications, owns lifecycle interruption and persists only explicit acceptance. SwiftUI renders the guide beside the existing preview.
**Tech Stack:** Swift, SwiftUI, XCTest, existing local Vision/MediaPipe.
**Spec:** docs/personal-adaptation-design.md

## Global Constraints
- macOS14+, manual camera enable, local only; never save images or per-frame history.
- Keep current notification acceptance gate, foreground target lock and generation fences.
- Defaults5s dwell; one threshold helper for judge and UI; previous preferences remain decodable.

## Review Focus
- Target loss/relock and stop must discard drafts and pending reminders.
- Skipped/invisible shoulders must not become learned successful measurements.
- Wrong-direction head motion and same-direction lateral trials must be rejected.
- New baseline invalidates personalized thresholds; cancel preserves prior settings.
- Experience uses real dwell/recovery while blocking system correction notifications.

### Task 1: Core session and effective thresholds
**Files:** new Sources/PostureCore/PersonalAdaptation.swift, Tests/PostureCoreTests/PersonalAdaptationTests.swift; modify Judgement.swift.
**Interfaces:** PersonalProfile(baseline, thresholds); threshold(for:sensitivity:); AdaptationSession.update/record/skip/adjust; session.profile only after reference.
- [x] Write tests for reference noise, action quality/direction, skip, missing/gaps, profile validation, and judge using personal thresholds.
- [x] Run swift test --filter PersonalAdaptationTests and observe missing feature failure.
- [x] Implement bounded scalar sampling, explicit actions and real judge demo; run full swift test.

### Task 2: App and guide
**Files:** AppModel.swift, Views.swift, new AdaptationView.swift.
**Interfaces:** start/cancel/record/skip/adjust/apply adaptation; centralized effectiveThreshold; profile persists versioned with matching baseline.
- [x] Integrate explicit-start and lifecycle cancellation. Never mutate saved baseline/thresholds before apply.
- [x] Guide UI with live boundary, skip reasons, experience and review confirmation; first-use/settings entry.
- [x] Build with warnings-as-errors; review interruption call sites and notification gate.

### Task 3: Package and handoff
**Files:** README.md, CHANGELOG.md, docs/VALIDATION.md, docs/PRD.md, scripts/build-app.sh.
- [x] Update0.6.0 docs and release metadata; no fabricated real-camera claims.
- [x] Full tests, warning-free build, release package, signature check; independent review and fix material findings.
- [x] Refresh source archive, launch with camera off; record git state and trial entry instructions.

## Execution record

Implemented inline under existing user authorization.65 tests green. Independent review3 findings fixed with reproducing app integration tests (RED→GREEN). AppModel dependencies accept isolated defaults, optional notification center and monotonic clock for real integration coverage without camera access. Ordinary recalibration retains accepted profile until replacement succeeds. Packaging/signature checked; physical camera trial pending.
