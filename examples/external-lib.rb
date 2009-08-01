# Example of using an external C lib with redshift. Note that
# <math.h> is included and -lm is linked by default.

require 'redshift'

RedShift.with_library do |library|
  library.include_file.include "<gsl/gsl_sf_gamma.h>"
  library.include_file.include "<gsl/gsl_math.h>"
  library.include_file.include "<gsl/gsl_const_mksa.h>"
  library.link_with "-lgsl"
  library.declare_external_constant "GSL_CONST_MKSA_MASS_ELECTRON"

  # If you need custom cflags, you can put them here:
  # $CFLAGS = "-fPIC -O2 -march=i686 -msse2 -mfpmath=sse"
end

class C < RedShift::Component
  continuous :x, :y
  
  flow do
    diff " y' = 2 + GSL_CONST_MKSA_MASS_ELECTRON "
  end
  
  transition Enter => Exit do
    guard " gsl_fcmp(y, 1.0, 0.01) == 0 "
    reset :x => "gsl_sf_taylorcoeff(3, 2)"
  end
end

w = RedShift::World.new
c = w.create C
w.evolve 1
p c.x, c.y
