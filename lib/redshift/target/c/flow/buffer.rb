class RedShift::Library
  def define_buffer
    return if @define_buffer
    @define_buffer = true
    
    include_file, source_file = add_file "buffer"

    include_file.declare :Buffer => %{
      typedef struct {
        long    len;
        long    offset;
        double  *ptr;
      } Buffer;
    }.tabto(0)

    source_file.define_c_function(:buffer_init).instance_eval {
      arguments "Buffer *buf", "long len", "double fill"
      scope :extern
      body %{
        int i;
        buf->ptr = ALLOC_N(double, len);
        buf->len = len;
        buf->offset = 0;
        for (i=0; i<len; i++) {
          buf->ptr[i] = fill;
        }
      }
    }
    
    source_file.define_c_function(:buffer_resize).instance_eval {
      arguments "Buffer *buf", "long len"
      scope :extern
      body %{
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
    }
    
    source_file.define_c_function(:buffer_inhale_array).instance_eval {
      arguments "Buffer *buf", "VALUE ary"
      scope :extern
      body %{
        int  size, i;

        Check_Type(ary, T_ARRAY);

        size = RARRAY(ary)->len;
        if (buf->ptr) {
          REALLOC_N(buf->ptr, double, size);
        }
        else {
          buf->ptr = ALLOC_N(double, size);
        }
        buf->len = size;
        buf->offset = 0;

        for (i = 0; i < size; i++) {
          buf->ptr[i] = NUM2DBL(RARRAY(ary)->ptr[i]);
        }
      }
    }

    source_file.define_c_function(:buffer_exhale_array).instance_eval {
      arguments "Buffer *buf"
      return_type "VALUE"
      returns "ary"
      scope :extern
      declare :size => "int size",
              :i => "int i",
              :j => "int j",
              :ary => "VALUE ary"
      body %{
        size = buf->len;
        ary = rb_ary_new2(size);
        RARRAY(ary)->len = size;
        for (i = buf->offset, j=0; i < size; i++, j++) {
          RARRAY(ary)->ptr[j] = rb_float_new(buf->ptr[i]);
        }
        for (i = 0; i < buf->offset; i++, j++) {
          RARRAY(ary)->ptr[j] = rb_float_new(buf->ptr[i]);
        }
      }
    }
  end

  # An embedded struct that holds a pointer +ptr+ to an externally stored
  # array of doubles of length +len+.
  class BufferAttribute < CShadow::CNativeAttribute
    @pattern = /\A(Buffer)\s+(\w+)\z/
    
    def initialize(*args)
      super
      lib = owner_class.shadow_library
      owner_class.shadow_library_include_file.include "buffer.h"
      
      @reader = "result = buffer_exhale_array(&shadow->#{@cvar})"
      @writer = "buffer_inhale_array(&shadow->#{@cvar}, arg)"
      @dump = "rb_ary_push(result, buffer_exhale_array(&shadow->#{@cvar}))"
      @load = "buffer_inhale_array(&shadow->#{@cvar}, rb_ary_shift(from_array))"
      @free = "free(shadow->#{@cvar}.ptr)"
    end
  end
end
