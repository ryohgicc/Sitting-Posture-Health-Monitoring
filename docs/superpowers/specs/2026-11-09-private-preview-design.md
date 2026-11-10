# Private camera preview

User request: add background blur to avoid showing coworkers. Existing app never records or uploads frames. Implement as a local preview change, with existing raw in-memory posture analysis retained.

The preview defaults to blur with no raw-camera display path. Vision person-instance segmentation selects only the instance covering the currently locked face, rather than preserving every person. Other detected face rectangles are removed from the selected mask. An uncertain target/mask or processing failure produces full blur or a blank preview. Stopping, relocking, hiding, lock/sleep and stale-frame rejection clear the last preview. No mask/image history or image files are written.

Alternatives: generic person segmentation preserves background people, defeating the request; a fixed oval exposes coworkers entering the oval and cuts shoulders. Individual-instance segmentation plus extra face exclusion matches the existing foreground lock. Selection thresholds, blur radius and internal UI wiring are implementation decisions within this requested feature, not new product scope.

Background blur reduces visible detail; cannot guarantee anonymization for all occlusions or unseen faces. It affects this app preview only, not other camera apps. Camera still receives the full frame in local memory. Keep this distinction clear in docs/UI without claiming people outside the target cannot enter camera input.
