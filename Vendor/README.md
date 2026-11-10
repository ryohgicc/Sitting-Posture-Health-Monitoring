# Bundled local inference assets

Target: Apple Silicon macOS only. App inference uses the C runtime directly, without Python, pip, downloads, or a server. Never replace just the dylib: MediaPipeBridge models the pinned 0.10.32 ABI and must be verified with any upgrade.

## Runtime

MediaPipe 0.10.32, Apache-2.0. Original upstream license is preserved as MediaPipe-LICENSE.txt. C bridge structure definitions are adapted from that version's Python ctypes definitions (base_options_c.py, landmark_c.py, pose_landmarker.py).

Upstream: https://github.com/google-ai-edge/mediapipe

Distribution: https://files.pythonhosted.org/packages/24/d9/ca1be234911c76ccd87a9e0d8210394153cb6ad9b5da65a231aff8769d6f/mediapipe-0.10.32-py3-none-macosx_11_0_arm64.whl

Wheel SHA256: b62178b7585e0bb8789075c43bbb3e352fbc4a8f765797fded509f86a098b29b

Extracted libmediapipe.dylib SHA256: 52f10f8dec2bdbd762336c39e5311806f7f94e0d712c58875373addd8ee37cfc

Packaging re-signs its copy, so the packaged dylib hash may differ. This wheel supplies the Apache license and no separate NOTICE file. Version 1.2.2 was evaluated but not shipped; its additional metrics notice requires a separate privacy assessment before any upgrade. Pinning an older version alone is not proof of a complete network audit.

## Model

MediaPipe Pose Landmarker Lite, float16, model version 1:
https://storage.googleapis.com/mediapipe-models/pose_landmarker/pose_landmarker_lite/float16/1/pose_landmarker_lite.task

SHA256: 59929e1d1ee95287735ddd833b19cf4ac46d29bc7afddbbf6753c459690d574a

Official documentation/model listing:
https://ai.google.dev/edge/mediapipe/solutions/vision/pose_landmarker

The official BlazePose GHUM 3D model card states Apache License, Version 2.0:
https://storage.googleapis.com/mediapipe-assets/Model%20Card%20BlazePose%20GHUM%203D.pdf

The full Apache-2.0 terms are included in MediaPipe-LICENSE.txt.

The model runs entirely in-process on CPU. Both model and runtime must be present under the app's Contents/Resources/Models. If missing, head pose remains available and shoulder metrics remain unknown with a diagnostic.
