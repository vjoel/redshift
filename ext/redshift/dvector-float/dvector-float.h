#ifndef dvector_float_h
#define dvector_float_h

#include <ruby.h>

typedef struct {
  long    len;
  long    capa;
  float  *ptr;
} RS_DVectorFloat;

extern void rs_dvf_grow(RS_DVectorFloat *dvf);
extern void rs_dvf_shrink(RS_DVectorFloat *dvf);

inline static RS_DVectorFloat *rs_dvf(VALUE obj)
{
    return (RS_DVectorFloat *)DATA_PTR(obj);
}

inline static void rs_dvf_push(RS_DVectorFloat *dvf, float val)
{
    if (dvf->len == dvf->capa) {
        rs_dvf_grow(dvf);
    }
    dvf->ptr[dvf->len++] = val;
}

inline static float rs_dvf_pop(RS_DVectorFloat *dvf)
{
    if (dvf->len == 0) {
        return 0;
    }
    return dvf->ptr[--dvf->len];
}

#endif
