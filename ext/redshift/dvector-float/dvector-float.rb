module RedShift; end

# A linear collection of single-precision floats.
#
# Intended primarily for access from C code, using the inline
# rs_dvf_push() and rs_dvf_pop() functions.
#
# Implements some of the same methods as Array, but not all.
#
# Like an Array, a DVector grows implicitly as elements are
# pushed. But unlike an Array, a DVector shrinks only explicitly.
# This is to minimize realloc() calls when a DVector rapidly
# grows and shrinks.

class RedShift::DVectorFloat
  include Enumerable
  require 'redshift/dvector-float/dvector_float.so'
  
  def self.[](*elts)
    new elts
  end
  
  def initialize(elts=nil)
    push(*elts) if elts
  end
  
  def inspect; to_a.inspect; end
  def to_s; to_a.to_s; end
  
  def dup
    self.class.new to_a
  end
end
