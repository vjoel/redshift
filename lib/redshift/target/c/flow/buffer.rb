require 'redshift/buffer/buffer.so'

class RedShift::Library
  def define_buffer
    unless @buffer_defined
      @buffer_defined = true
      text = <<-END

#ifndef buffer_h
#define buffer_h

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
      END
      include_file.declare :buffer_header_text => text
      ## would be better to copy buffer.h into dir and include it
    end
  end
  
  # An embedded struct that holds a pointer +ptr+ to an externally stored
  # array of doubles of length +len+.
  class BufferAttribute < CShadow::CNativeAttribute
    @pattern = /\A(RSBuffer)\s+(\w+)\z/
    
    def initialize(*args)
      super
      lib = owner_class.shadow_library
      ##owner_class.shadow_library_include_file.include "buffer.h"
      
      @reader = "result = rs_buffer_exhale_array(&shadow->#{@cvar})"
      @writer = "rs_buffer_inhale_array(&shadow->#{@cvar}, arg)"
      @dump = "rb_ary_push(result, rs_buffer_exhale_array(&shadow->#{@cvar}))"
      @load =
        "rs_buffer_inhale_array(&shadow->#{@cvar}, rb_ary_shift(from_array))"
      @free = "free(shadow->#{@cvar}.ptr)"
    end
  end
end
