#!/usr/bin/env ruby
require 'redshift/redshift.rb'
#require 'redshift/plot.rb'
require 'complex'

include RedShift

class MyCurve < Component

  MyFormula = "z' = 3 * z ** 3 - 2"

  flow (Enter) {
    differential MyCurve::MyFormula
  }
  
  setup {
    @z = Complex.new(1, 1)
  }
  
end

w = World.new {time_step 0.01}

foo = w.create MyCurve

File.open("complexRK4.out", "w") do |f|

  1000.times do
    f.printf "%12.5f\t%12.5f\n", foo.z.real, foo.z.image
    w.run
  end
  f.printf "%12.5f\t%12.5f\n", foo.z.real, foo.z.image
  
end

MyCurve.flow (Enter) {
  euler MyCurve::MyFormula
}

foo.setup

File.open("complexEuler.out", "w") do |f|

  1000.times do
    f.printf "%12.5f\t%12.5f\n", foo.z.real, foo.z.image
    w.run
  end
  f.printf "%12.5f\t%12.5f\n", foo.z.real, foo.z.image
  
end

IO.popen("gnuplot", "w+") do |pipe|

  pipe.puts("plot 'complexRK4.out' w l, 'complexEuler.out' w l; pause 5")

end
