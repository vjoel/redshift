# Overview of the different kinds of "constants" in redshift.
#
# 1. constants defined in a ruby module
#
# 2. constants defined in an external library -- see external-lib.rb
#
# 3. per component constant _functions_ (strict or piecewise).

require 'redshift'

RedShift.with_library do |library|
  library.declare_external_constant "M_E" # GNU C math lib
end

class C < RedShift::Component
  K = 10
  L = 456
  constant :kk => 2 # per instance, and can change discretely
  
  flow do
    alg "x = kk*K + #{L*1000} + M_E"
  end
end

w = RedShift::World.new
c = w.create C
p c.x
