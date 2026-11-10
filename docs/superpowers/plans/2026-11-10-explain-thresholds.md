# Explain Thresholds Implementation Plan

Goal: Users can see their current estimated change, entry boundary, and actual sustained/recovery state.
Spec: ../specs/2026-11-10-explain-thresholds.md
Implementation inline. No change to persistence, camera input, numeric thresholds or notification policy.

- [x] Add failing tests at entry equality,80%, just over threshold, actual dwell20s, recovery55%/3s, muted/missing/disabled, sensitivity and conversions.
- [x] Add judge observation values derived from existing state and single entry-threshold helper. UI must read same values as detection; no reconstructed wall clock timers.
- [x] Present metric rows with current/threshold units,100% marker, explanatory state and action hint. Clear observations on all existing judge resets, calibration, failure and snooze. Guide comfortable reference setup without medical claims.
- [x] Run tests, warnings-as-errors build, independent review, package/sign and launch. Update README/changelog/validation and repository rules for existing git state. Verify remote relationship before any push.

Review: fixed rounding near80%/100% to retain boundary relation. All51 tests pass. Camera remains manual; no live imagery captured or saved.
