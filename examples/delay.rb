# Delay of a continuous signal by a given time.

require 'redshift'
include RedShift

class C < Component
  pi = Math::PI
  constant :d => 0.02

  flow do
    diff   "       t' = 1 "
    alg    "       u  = sin(t*#{pi/2}) "
    alg    " shift_u  = sin((t-d)*#{pi/2}) " # u shifted by d
    delay  " delay_u  = u ", :by => "d" # Note: refers to constant d
    alg    "     err  = shift_u - delay_u "
  end
end

world = World.new
world.time_step = 0.1
c = world.create(C)

u, shift_u, delay_u, err = [], [], [], []
  time = c.t
  u       << [time, c.u]
  shift_u << [time, c.shift_u]
  delay_u << [time, c.delay_u]
  err     << [time, c.err]

world.evolve 10 do
  time = c.t
  u       << [time, c.u]
  shift_u << [time, c.shift_u]
  delay_u << [time, c.delay_u]
  err     << [time, c.err]
end

require 'sci/plot'
include Plot::PlotUtils

gnuplot do |plot|
  plot.command %{set title "Time delay"}
  plot.command %{set xlabel "time"}
  plot.add u, %{title "u" with lines}
  plot.add shift_u, %{title "shift_u" with lines}
  plot.add delay_u, %{title "delay_u" with lines}
  plot.add err, %{title "err" with lines}
end
