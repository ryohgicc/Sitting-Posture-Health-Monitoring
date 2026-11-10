# PosturePal

Native macOS menu bar prototype; Swift package with PostureCore (pure geometry/timers) PostureVision (shared inference), PostureProbe (offline image replay), and PosturePal (camera/UI). Canonical requirements: ../坐姿提醒工具-PRD-v1.0.md. Read docs/VALIDATION.md before claiming completion.

## Commands

Use full Xcode because standalone CLT lacks XCTest on this machine:

```sh
export DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer
swift test
swift build -Xswiftc -warnings-as-errors
./scripts/build-app.sh
codesign --verify --deep --strict dist/坐姿搭子.app
```

Bundled third-party MediaPipe 0.10.32 ARM64 runtime/model; preserve Vendor provenance/license, pinned ABI, bundle resources and nested signing. No database, migrations, remote, deployment or login startup. Camera must start only after a user click. Never record frames, screenshots, videos or per-frame keypoints. Preferences/baseline scalars only in UserDefaults, versioned keys. No network code.

Keep Vision and MediaPipe inference serial and off main thread; generation-check callbacks and queued frames. Stop/pause/lock/failure releases camera. Missing metrics remain unknown, clear their pending timers. Never claim real accuracy, release verification or energy results from synthetic tests.

Update README, CHANGELOG and VALIDATION when behavior changes. This generated workspace has no git repository; do not initialize or commit unrelated parent files. Use targeted core tests, a warning-free app build, release packaging and signature checks for changes. Real camera and UI testing needs the user's availability.

For multi-person offices follow PRD section 10: one foreground target, no face identity/embedding, no background takeover. SubjectTracker and SubjectAssociation are pure geometry; lost/ambiguous target must clear live posture. Offline probe reads user-supplied images and never writes their contents.

Preview is image-based, no AVCaptureVideoPreviewLayer. User-authorized background blur toggle defaults on and persists backgroundBlur.v1. Only explicit off permits camera-image passthrough; never use raw fallback when on. Blur-mode revision rejects old in-flight previews after switching. PrivacyCompositor selects one target instance and excludes other faces; failed/unknown masks blur all or show blank. Clear processed images on lifecycle/reset/hide/stale and retain generation checks. Blur reduces detail but is not guaranteed anonymization.
