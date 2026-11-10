# Private Preview Implementation Plan

> Execute inline using executing-plans; finish with one focused independent review.

Goal: Show only a processed preview that keeps the locked foreground person sharp and blurs the background.
Architecture: PostureVision privacy compositor uses Vision instance masks and Core Image; CameraPipeline emits only processed preview images with generation protection; AppModel clears images across lifecycle transitions; SwiftUI displays these images instead of a capture preview layer.
Tech: Swift, Vision, Core Image, native macOS14.
Spec: ../specs/2026-11-09-private-preview-design.md

Constraints: no video/image/history writes, no network, no new dependencies, camera only user start. No git repository.
Review focus: other people in same/overlapping mask, selection ambiguity, stale preview after stop/relock, fallback accidentally showing raw frames, camera orientation/mirror.

- [x] Write selection-policy tests for foreground, ambiguous/no target, and weak coverage. Run to fail, then implement.
- [x] Add privacy compositor and offline privacy probe. Check target mask coverage, background suppression and complete blur fallback on supplied images without writing images.
- [x] Wire processed preview through generation-protected callbacks; remove AVCaptureVideoPreviewLayer; clear preview on all stop/reset/hide/failure paths.
- [x] Test/build/strict native checks, docs/changelog/version0.4.0, independent review, package/sign, launch without starting camera, refresh source archive.

Ruling: implement the directly requested preview blur without another permission round; use native instance segmentation, no dependency changes. Review added unique face selection, stale result age checks, and relock epoch fencing. Remaining live lifecycle/performance and arbitrary-scene privacy cannot be proven from static screenshots.
