# Numerical differentiation.

# Compare with simulink/derivative.mdl -- note that redshift is more accurate
# because the derivative flow operates at all integrator steps, not just at
# the simulation timesteps.

require 'redshift'
include RedShift

class C < Component
  flow do
    diff   "     t' = 1 "

    alg    "     u  = sin(t) "
    alg    "   sdu  = cos(t) " # symbolic derivative
    derive "   ndu  = u'     ",# numerical derivative (can be (<expr>)' )
            :feedback => false
    diff   " nindu' = ndu    " # numerical integral of ndu
    diff   "   niu' = u      " # numerical integral of u
    derive " ndniu  = niu'   ",# numerical derivative of niu
            :feedback => false
    
    alg    "   err  = sdu - ndu "
      # This error is small.
    
    alg    " e_ndni = ndniu - u "
    alg    " e_nind = nindu - u "
      # The error is very small when numerically differentiating a signal that
      # has been numerically integrated (e_ndni), but the error is worse
      # for the integral of a differentiated signal (e_nind).
  end

#  Some alternative examples:
#    alg    "     u  = pow(t, 4) - 17*pow(t,3) + 102*pow(t,2) - 1300*t "
#    alg    "   sdu  = 4*pow(t, 3) - 3*17*pow(t,2) + 2*102*t - 1300 "
#
#  continuous :u => 1, :nindu => 1, :ndniu =>1
#    diff   "    u'  = 0.02*u "
#    alg    "   sdu  = 0.02*exp(0.02*u) "
end

world = World.new
c = world.create(C)

u, sdu, ndu, nindu, err, e_ndni, e_nind = [], [], [], [], [], [], []
gather = proc do
  time = c.t
  u       << [time, c.u]
  sdu     << [time, c.sdu]
  ndu     << [time, c.ndu]
  nindu   << [time, c.nindu]
  err     << [time, c.err]
  e_ndni  << [time, c.e_ndni]
  e_nind  << [time, c.e_nind]
end

gather.call
world.evolve 10 do
  gather.call
end

require 'redshift/util/plot'
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

sleep 1 if /mswin32|mingw32/ =~ RUBY_PLATFORM
