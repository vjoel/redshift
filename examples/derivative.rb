# Numerical differentiation.

require 'redshift'
include RedShift

class C < Component
  flow do
    diff   "     t' = 1 "

    alg    "     u  = sin(t) "
    alg    "   sdu  = cos(t) " # symbolic derivative
    derive "   ndu  = u'     " # numerical derivative (can be (<expr>)' )
    diff   " nindu' = ndu    " # numerical integral of ndu
    diff   "   niu' = u      " # numerical integral of u
    derive " ndniu  = niu'   " # numerical derivative of niu
    
    alg    "   err  = sdu - ndu "
      # This error is small.
    
    alg    " e_ndni = ndniu - u "
    alg    " e_nind = nindu - u "
      # The error is very small when numerically differentiating a signal that
      # has been numerically integrated (e_ndni), but the error is worse
      # for the integral of a differentiated signal (e_nind).
  end
end

world = World.new
c = world.create(C)

u, sdu, ndu, nindu, err, e_ndni, e_nind = [], [], [], [], [], [], []
  time = c.t
  u       << [time, c.u]
  sdu     << [time, c.sdu]
  ndu     << [time, c.ndu]
  nindu   << [time, c.nindu]
  err     << [time, c.err]
  e_ndni  << [time, c.e_ndni]
  e_nind  << [time, c.e_nind]

world.evolve 10 do
  time = c.t
  u       << [time, c.u]
  sdu     << [time, c.sdu]
  ndu     << [time, c.ndu]
  nindu   << [time, c.nindu]
  err     << [time, c.err]
  e_ndni  << [time, c.e_ndni]
  e_nind  << [time, c.e_nind]
end

require 'sci/plot'
include Plot::PlotUtils

gnuplot do |plot|
  plot.command %{set title "Numerical differentiation"}
  plot.command %{set xlabel "time"}
  plot.add u, %{title "u" with lines}
  plot.add sdu, %{title "sdu" with lines}
  plot.add ndu, %{title "ndu" with lines}
  plot.add nindu, %{title "nindu" with lines}
  plot.add err, %{title "err" with lines}
  plot.add e_ndni, %{title "e_ndni" with lines}
  plot.add e_nind, %{title "e_nind" with lines}
end
