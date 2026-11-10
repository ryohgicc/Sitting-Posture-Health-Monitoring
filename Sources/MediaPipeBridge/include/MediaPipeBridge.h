#ifndef POSTURE_MEDIAPIPE_BRIDGE_H
#define POSTURE_MEDIAPIPE_BRIDGE_H
#include <stdint.h>
typedef struct PPDetector PPDetector;
typedef struct { float x, y, visibility, presence; } PPPoint;
typedef struct { PPPoint nose, leftShoulder, rightShoulder, leftEar, rightEar; } PPBody;
PPDetector *pp_create(const char *library_path, const char *model_path, char *error, int error_size);
int pp_detect(PPDetector *detector, const uint8_t *rgba, int width, int height, PPBody *bodies, int capacity, char *error, int error_size);
void pp_close(PPDetector *detector);
#endif
