// Adapter for pinned MediaPipe 0.10.32 C ABI, derived from Apache-2.0 Python ctypes definitions.
// Upstream types: base_options_c.py, landmark_c.py, pose_landmarker.py. License in Vendor/.
#include "MediaPipeBridge.h"
#include <stdbool.h>
#include <stddef.h>
#include <stdlib.h>
#include <stdio.h>
#include <string.h>
#include <dlfcn.h>

typedef struct { const char *buffer; unsigned count; const char *path; int delegate; } BaseOptions;
typedef struct { BaseOptions base; int running_mode, num_poses; float detection, presence, tracking; bool segmentation; void *callback; } Options;
typedef struct { float x,y,z; bool has_visibility; float visibility; bool has_presence; float presence; const char *name; } Landmark;
typedef struct { Landmark *landmarks; uint32_t count; } Landmarks;
typedef struct { void **masks; uint32_t mask_count; Landmarks *poses; uint32_t pose_count; Landmarks *world; uint32_t world_count; } Result;
// Fail compilation if platform layout drifts from the pinned ARM64 ctypes ABI.
_Static_assert(sizeof(BaseOptions)==32, "MediaPipe BaseOptions ABI");
_Static_assert(sizeof(Options)==64, "MediaPipe Options ABI");
_Static_assert(sizeof(Landmark)==40, "MediaPipe Landmark ABI");
_Static_assert(offsetof(Landmark, visibility)==16, "MediaPipe visibility ABI");
_Static_assert(sizeof(Result)==48, "MediaPipe Result ABI");
struct PPDetector {
    void *library, *task;
    int (*create)(Options*,void**,char**);
    int (*image_create)(int,int,int,const uint8_t*,int,void**,char**);
    int (*detect)(void*,void*,const void*,Result*,char**);
    void (*result_close)(Result*);
    void (*image_free)(void*);
    void (*error_free)(char*);
    int (*close)(void*,char**);
};
static void message(char *out,int size,const char *text) { if(out && size>0) snprintf(out,(size_t)size,"%s",text ? text : "MediaPipe error"); }
PPDetector *pp_create(const char *library_path,const char *model_path,char *error,int size) {
    PPDetector *d=calloc(1,sizeof(*d));
    if(!d) { message(error,size,"Out of memory"); return NULL; }
    d->library=dlopen(library_path,RTLD_NOW|RTLD_LOCAL);
    if(!d->library) { message(error,size,dlerror()); free(d); return NULL; }
#define SYMBOL(field,name) do { *(void **)(&d->field)=dlsym(d->library,name); if(!d->field) {message(error,size,"Missing MediaPipe 0.10.32 ABI symbol: " name); pp_close(d); return NULL;} } while(0)
    SYMBOL(create,"MpPoseLandmarkerCreate"); SYMBOL(image_create,"MpImageCreateFromUint8Data");
    SYMBOL(detect,"MpPoseLandmarkerDetectImage"); SYMBOL(result_close,"MpPoseLandmarkerCloseResult");
    SYMBOL(image_free,"MpImageFree"); SYMBOL(error_free,"MpErrorFree"); SYMBOL(close,"MpPoseLandmarkerClose");
#undef SYMBOL
    Options options={0}; options.base.path=model_path; options.running_mode=1; options.num_poses=3;
    options.detection=0.5f; options.presence=0.5f; options.tracking=0.5f;
    char *err=NULL;
    int status=d->create(&options,&d->task,&err);
    if(status != 0 || !d->task) { message(error,size,err); if(err) d->error_free(err); pp_close(d); return NULL; }
    return d;
}
static PPPoint point(Landmark *p) {
    return (PPPoint){p->x,p->y,p->has_visibility ? p->visibility : 0,p->has_presence ? p->presence : 0};
}
int pp_detect(PPDetector *d,const uint8_t *rgba,int width,int height,PPBody *out,int capacity,char *error,int size) {
    if(!d || !rgba || width<=0 || height<=0 || width>4096 || height>4096 || !out || capacity<=0) {message(error,size,"Invalid frame");return -1;}
    void *image=NULL; char *err=NULL;
    int status=d->image_create(2,width,height,rgba,width*height*4,&image,&err);
    if(status != 0 || !image) { message(error,size,err);if(err)d->error_free(err);return -1; }
    Result result={0};
    status=d->detect(d->task,image,NULL,&result,&err);
    int count=0;
    if(status==0) {
        for(uint32_t i=0;i<result.pose_count && count<capacity;i++) {
            if(result.poses[i].count<13 || !result.poses[i].landmarks)continue;
            Landmark *p=result.poses[i].landmarks;
            out[count++]=(PPBody){point(&p[0]),point(&p[11]),point(&p[12])};
        }
    } else {message(error,size,err); count=-1;}
    if(err)d->error_free(err);
    d->result_close(&result); d->image_free(image);
    return count;
}
void pp_close(PPDetector *d) {
    if(!d)return;
    if(d->task && d->close) {char *err=NULL;d->close(d->task,&err);if(err && d->error_free)d->error_free(err);}
    if(d->library)dlclose(d->library);
    free(d);
}
