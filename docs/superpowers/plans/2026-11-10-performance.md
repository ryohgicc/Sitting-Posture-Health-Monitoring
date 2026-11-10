# Performance Implementation Plan

> **For agentic workers:** Execute inline under user's performance request.

**Goal:** Reduce redundant preview and frame preparation work without altering detection cadence or reminder logic.
**Architecture:** Effective preview demand combines window occlusion, active dashboard tab and user toggle with revision cancellation. Reuse same-frame face boxes for privacy; reusable serial RGBA frame buffer for MediaPipe.
**Tech Stack:** Swift/SwiftUI/AppKit, Vision, CGContext, XCTest.
**Spec:** docs/superpowers/specs/2026-11-10-performance-design.md

## Global Constraints
- No camera auto-start, image/trajectory history or network additions.
- Preserve5Hz analysis,640×480 preset, serial inference and all reminder timing.
- Performance numbers are offline timing, not measured camera/energy savings.

## Review Focus
- Occluded/minimized/closed windows and other tabs must skip privacy work.
- Late previews after a visibility/blur transition must not reappear.
- User-disabled preview remains disabled when reopening.
- Reused buffer clears old alpha content and resizes safely.
- Same-frame faces reuse still hides every non-target face and degrades privately.

### Task1 — Establish baseline
- [x] Add offline benchmark to probe; warmup and per-stage wall timings on same image; capture baseline.
### Task2 — Preview lifecycle
- [x] Reproduce hidden-window processing with AppModel tests; implement window/tab demand and revision fencing; prove judgement continues.
### Task3 — Inference allocations and duplicate requests
- [x] Test buffer colors/alpha/resize, implement serial reuse; test supplied-face privacy fallback and retain standalone detection.
- [x] Compare offline timing, run full suite/warnings build/release/sign and independent review.
### Task4 — Handoff
- [x] Docs/changelog/PRD/VALIDATION0.8.1 build12, source archive, camera-off launch, authorized commit/push.

## Execution record

Baseline20 frames wall-stage25.80/42.95ms inference/privacy. Optimized26.41/33.47ms; same-version control25.75/44.19ms versus reuse24.57/34.94ms. No inference speedup claim; privacy phase~21–22% reduction in offline sample.85 tests pass, warning-free build/release/signature checks pass. Real camera energy and AppKit occlusion behavior still require user trial. Reused RGBA contents zeroed after synchronous inference; all face detections including low-confidence are forwarded for privacy. One supplied screenshot privacy energy limit fails identically in control/reuse, prior known algorithm limitation; original privacy fixture passes.
