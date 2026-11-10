# Forward Head Estimate Implementation Plan

> **For agentic workers:** Use superpowers:executing-plans inline under current user request.

**Goal:** Add an honestly labeled frontal-camera head approach estimate with calibration, guide, threshold display and notification.
**Architecture:** Pure HeadApproachGeometry produces a head/shoulder scale ratio and normalized shoulder span from the already-associated face/body. PoseMetrics gates signed relative ratio growth using reference span and angles. Reuse judge, scalar profiles and configurable dwell.
**Tech Stack:** Swift/SwiftUI, Vision/MediaPipe, XCTest.
**Spec:** docs/superpowers/specs/2026-11-10-forward-head-design.md

## Global Constraints
- Manual camera enable, local processing, no imagery/trajectory/network additions.
- Optional scalar fields preserve existing JSON/profiles; target identity is geometry only.
-12% ratio growth is an experimental engineering reminder line, no cervical angle/diagnosis claim.

## Review Focus
- Whole-body scale changes and head angle changes must not be claimed as valid head-only motion.
- Signed ratio increase only; retracting head is below line, missing data resets just this item.
- Existing references stay usable for existing items; new reference required for new item.
- Adaptation skip/cancel preserves existing config, optional new toggle migration runs once.
- Shared threshold and units remain equal in UI/judge/guide.

### Task1 — Pure metric
- [x] Write failing tests for ratio invariance/invalid geometry, reference-relative growth, angle/span/lateral gating, dwell and independent reset, oldJSON.
- [x] Implement optional metrics and stable reference accumulation; run full tests.
### Task2 — Inference and guided UX
- [x] Compute ratio only for matched face/body, add fifth toggle migration and guide stage.
- [x] Tests for new stage, skip and preference restart, warnings-free UI build.
### Task3 — Validation and release
- [x] Docs/changelog/PRD and0.8.0 build11; independent review plus material fixes.
- [x] Full suite, warnings-as-errors, release/sign, static offline probe; no-camera launch.
- [x] Sync parent PRD/source archive, commit and authorized remote push.

## Execution record

Implemented inline under user instruction. Independent review found calibration used absolute scale spread versus relative runtime growth; reproduced RED with ratio .2/.23 and shoulder-span .1/.12, corrected reference criteria, full79-test suite GREEN. Existing supplied screenshot with synthetic extra face passed all five input requirements. Warning-free build/release/signature passed; no camera opened. Real detection accuracy remains pending.
