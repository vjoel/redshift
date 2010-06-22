#ifndef buffer_h
#define buffer_h

#include <ruby.h>

typedef struct {
  long    len;
  long    offset;
  double  *ptr;
} RSBuffer;

void rs_buffer_init(RSBuffer *buf, long len, double fill);
void rs_buffer_resize(RSBuffer *buf, long len);
void rs_buffer_inhale_array(RSBuffer *buf, VALUE ary);
VALUE rs_buffer_exhale_array(RSBuffer *buf);

#endif
