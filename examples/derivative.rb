# Numerical differentiation.

require 'redshift'
include RedShift

class C < Component
  flow do
    diff   "     t' = 1 "

    alg    "     u  = sin(t) "
    alg    "   sdu  = cos(t) " # symbolic derivative
    derive "   ndu  = u'     " # numerical derivative
    diff   " nindu' = ndu    " # numerical integral of ndu
    diff   "   niu' = u      " # numerical integral of u
    derive " ndniu  = niu'   " # numerical derivative of niu
    
    alg    " err  = sdu - ndu "
      # This error is small.
    
    alg    " err1 = ndniu - u "
    alg    " err2 = nindu - u "
      # The error is small when numerically differentiating a signal that
      # has been numerically integrated (err1), but not the reverse (err2).
  end
end

world = World.new
c = world.create(C)

u, sdu, ndu, nindu, err, err1, err2 = [], [], [], [], [], [], []
  time = c.t
  u       << [time, c.u]
  sdu     << [time, c.sdu]
  ndu     << [time, c.ndu]
  nindu   << [time, c.nindu]
  err     << [time, c.err]
  err1    << [time, c.err1]
  err2    << [time, c.err2]

world.evolve 10 do
  time = c.t
  u       << [time, c.u]
  sdu     << [time, c.sdu]
  ndu     << [time, c.ndu]
  nindu   << [time, c.nindu]
  err     << [time, c.err]
  err1    << [time, c.err1]
  err2    << [time, c.err2]
end

require 'sci/plot'
include Plot::PlotUtils

gnuplot do
  command %{set title "Numerical differentiation"}
  command %{set xlabel "time"}
  add u, %{title "u" with lines}
  add sdu, %{title "sdu" with lines}
  add ndu, %{title "ndu" with lines}
  add nindu, %{title "nindu" with lines}
  add err, %{title "err" with lines}
  add err1, %{title "err1" with lines}
  add err2, %{title "err2" with lines}
end
