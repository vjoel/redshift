require 'redshift/buffer/buffer.so'
require 'redshift/buffer/dir'

class RedShift::Library
  def define_buffer
    unless @buffer_defined
      @buffer_defined = true
      text = File.read(File.join(REDSHIFT_BUFFER_DIR, "buffer.h"))
      buffer_h = CGenerator::CFile.new("buffer.h", self, nil, true)
      buffer_h.declare :buffer_header_text => text
      add buffer_h
    end
  end
  
  # An embedded struct that holds a pointer +ptr+ to an externally stored
  # array of doubles of length +len+.
  class BufferAttribute < CShadow::CNativeAttribute
    @pattern = /\A(RSBuffer)\s+(\w+)\z/
    
    def initialize(*args)
      super
      lib = owner_class.shadow_library
      owner_class.shadow_library_include_file.include "buffer.h"
      
      @reader = "result = rs_buffer_exhale_array(&shadow->#{@cvar})"
      @writer = "rs_buffer_inhale_array(&shadow->#{@cvar}, arg)"
      @dump = "rb_ary_push(result, rs_buffer_exhale_array(&shadow->#{@cvar}))"
      @load =
        "rs_buffer_inhale_array(&shadow->#{@cvar}, rb_ary_shift(from_array))"
      @free = "free(shadow->#{@cvar}.ptr)"
    end
  end
end
