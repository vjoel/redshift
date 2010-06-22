#include "buffer.h"

void rs_buffer_init(RSBuffer *buf, long len, double fill)
{
    int i;
    buf->ptr = ALLOC_N(double, len);
    buf->len = len;
    buf->offset = 0;
    for (i=0; i<len; i++) {
      buf->ptr[i] = fill;
    }
}

void rs_buffer_resize(RSBuffer *buf, long len)
{
    long    i;
    long    old_len = buf->len;
    long    offset  = buf->offset;
    double *ptr     = buf->ptr;
    double *dst, *src;
    double  fill;
    
    if (len < old_len) {
      if (offset < len) {
        dst = ptr + offset;
        src = ptr + offset + old_len - len;
        memmove(dst, src, (len - offset) * sizeof(double));
      }
      else {
        dst = ptr;
        src = ptr + offset - len;
        offset = 0;
        memmove(dst, src, len * sizeof(double));
      }
      REALLOC_N(ptr, double, len);
      // ## maybe better: don't release space, just use less of it
    }
    else if (len > old_len) {
      REALLOC_N(ptr, double, len);
    
      fill = ptr[offset];
      dst = ptr + offset + len - old_len;
      src = ptr + offset;
      memmove(dst, src, (old_len - offset) * sizeof(double));
    
      for (i = 0; i < len - old_len; i++) {
        ptr[offset + i] = fill;
      }
    }
    else
      return;
    
    buf->len = len;
    buf->offset = offset;
    buf->ptr = ptr;
}

void rs_buffer_inhale_array(RSBuffer *buf, VALUE ary)
{
    int  size, i;
    
    Check_Type(ary, T_ARRAY);
    
    size = RARRAY_LEN(ary);
    if (buf->ptr) {
      REALLOC_N(buf->ptr, double, size);
    }
    else {
      buf->ptr = ALLOC_N(double, size);
    }
    buf->len = size;
    buf->offset = 0;
    
    for (i = 0; i < size; i++) {
      buf->ptr[i] = NUM2DBL(RARRAY_PTR(ary)[i]);
    }
}

VALUE rs_buffer_exhale_array(RSBuffer *buf)
{
    VALUE ary;
    int i;
    int j;
    int size;
    
    size = buf->len;
    ary = rb_ary_new2(size);
    RARRAY_LEN(ary) = size;
    for (i = buf->offset, j=0; i < size; i++, j++) {
      RARRAY_PTR(ary)[j] = rb_float_new(buf->ptr[i]);
    }
    for (i = 0; i < buf->offset; i++, j++) {
      RARRAY_PTR(ary)[j] = rb_float_new(buf->ptr[i]);
    }
    
    return ary;
}

void
Init_buffer()
{
    VALUE Buffer;

    Buffer = rb_define_class("Buffer", rb_cObject);
    rb_const_set(Buffer, rb_intern("DIR"), rb_str_new2(__DIRECTORY__));
}
