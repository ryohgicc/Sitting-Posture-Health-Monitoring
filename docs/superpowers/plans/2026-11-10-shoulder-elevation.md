# Shoulder Elevation Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline under the user's implementation request.

**Goal:** Rename confusing indicators and add bilateral shoulder elevation through the existing local pose pipeline.
**Architecture:** Optional ear anchors through C bridge and Swift adapter; pure normalized shoulder-ear geometry and baseline-relative bilateral reduction. One signed deviation helper for judge and adaptation. Persist only accepted scalar values with old JSON compatibility.
**Tech Stack:** Swift/SwiftUI, native MediaPipe bridge, XCTest.
**Spec:** docs/superpowers/specs/2026-11-10-shoulder-elevation-design.md

## Global Constraints
- No camera auto-start, network, images or trajectory persistence; keep target association and stale-frame fences.
- Keep encoded lean/shoulders names and existing preferences readable.
-8% shoulder-width default is an engineering trial line, never a medical cutoff.

## Review Focus
- Single-side shoulder motion must not become a bilateral shrug.
- Missing/occluded ears and head motion reset shrug only, preserving other metrics.
- Pixel geometry handles aspect ratio and scale; same locked body provides ears/shoulders.
- Existing profiles load; missing shrug reference remains unknown.
- Per-item toggles survive restart and adaptation cancel retains configuration.

### Task1 — Geometry and judgement
- [x] Write failing tests for bilateral/single-side, scale/translation, missing/invalid inputs, head pose gating, old JSON and dwell/reset.
- [x] Implement ear-gap geometry, optional metrics, signed deviation, calibration and fourth issue; run complete suite.
### Task2 — Inference/UI/adaptation
- [x] Bridge ear7/8 from existing pose; normalize in pixel space only after strict association.
- [x] Add shrug guide step and skip/record coverage, preserve existing preference toggles.
- [x] Rename current UI indicators and explain values/limits consistently.
### Task3 — Verify and deliver
- [x] Update README/CHANGELOG/PRD/VALIDATION,0.7.0/build10.
- [x] Independent review, full tests, warnings-as-errors, release package/signature, camera-off launch.
- [x] Commit/push authorized repository and refresh source archive.

## Execution record

Implemented inline under current user instruction.72 tests pass. Independent review found diagonal-width single-side coupling, reproduced by geometry→judge test RED, fixed using horizontal span, full suite GREEN. Preserved old configurations with optional scalar fields and once-only toggle migration. Warning-free build, release and codesign checks passed; physical-camera accuracy remains unverified.
