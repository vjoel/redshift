# Example of using an external C lib with redshift. Note that
# <math.h> is included and -lm is linked by default.

require 'redshift'

RedShift.with_library do |library|
  library.include_file.include "<gsl/gsl_sf_gamma.h>"
  library.link_with "-lgsl"

  # If you need custom cflags, you can put them here:
  # $CFLAGS = "-fPIC -O2 -march=i686 -msse2 -mfpmath=sse"
end

class C < RedShift::Component
  continuous :x
  transition Enter => Exit do
    reset :x => "gsl_sf_taylorcoeff(3, 2)"
  end
end

w = RedShift::World.new
c = w.create C
w.run 1
p c.x
