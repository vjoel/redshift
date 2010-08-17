#ifndef dvector_h
#define dvector_h

#include <ruby.h>

typedef struct {
  long    len;
  long    capa;
  VALUE  *ptr;
} RS_DVector;

extern void rs_dv_grow(RS_DVector *dv);
extern void rs_dv_shrink(RS_DVector *dv);

inline static void rs_dv_push(RS_DVector *dv, VALUE val)
{
    if (dv->len == dv->capa) {
        rs_dv_grow(dv);
    }
    dv->ptr[dv->len++] = val;
}

inline static VALUE rs_dv_pop(RS_DVector *dv)
{
    if (dv->len == 0) {
        return Qnil;
    }
    return dv->ptr[--dv->len];
}

#endif
