#!/usr/bin/env ruby
require 'redshift'
require 'plot/plot'
require 'complex'

include RedShift

class MyCurve < Component

  MyFormula = "z' = 3 * z ** 3 - 2"

  flow (Enter) {
    differential MyCurve::MyFormula
  }
  
  setup {
    @z = Complex.new(1.0, 1.0)
  }
  
end


w = World.new {time_step 0.01}


curve = w.create MyCurve

dataRK4 = [[curve.z.real, curve.z.image]]

1000.times do
  w.run
  dataRK4 << [curve.z.real, curve.z.image]
end


MyCurve.flow (Enter) {
  euler MyCurve::MyFormula
}

curve.setup

dataEuler = [[curve.z.real, curve.z.image]]

1000.times do
  w.run
  dataEuler << [curve.z.real, curve.z.image]
end

Plot.new ('gnuplot') {

  add dataRK4, 'title "Runge-Kutta 4th order" w l'
  add dataEuler, 'title "Euler" w l'
  show
  pause 100

}
