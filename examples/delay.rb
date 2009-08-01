# Delay of a continuous signal by a given time.

# Compare with simulink/delay.mdl -- note that redshift is more accurate
# because the delay flow operates at all integrator steps, not just at
# the simulation timesteps.

require 'redshift'
include RedShift

class C < Component
  constant :pi => Math::PI
  constant :d => 0.3

  state :A, :B
  start A
  
  flow A, B do
    diff   "       t' = 1 "
    alg    "       u  = sin(t*pi/2) "
    alg    " shift_u  = sin((t-d)*pi/2) " # u shifted by d
    delay  " delay_u  = u ",  # delayed output from u (can be any expr)
            :by => "d"        # delayed by d (can be any expr)
    alg    "     err  = shift_u - delay_u "
    
    # Check how delay interacts with integration:
    diff   "     idu' = delay_u "
    diff   "      iu' = u"
    delay  "     diu  = iu ", :by => "d"
    alg    "iddi_err  = idu - diu"
  end

  constant :new_d => 0.5  # change this to see how varying delay works
  constant :t_new_d => 5.0
  transition A => B do
    guard "t >= t_new_d"
    reset :d => "new_d"
  end
  # Note that the buffered u values are preserved in the transition
end

world = World.new
world.time_step = 0.1
c = world.create(C)

u, shift_u, delay_u, err, iddi_err = [], [], [], [], []
gather = proc do
  time = c.t
  u       << [time, c.u]
  shift_u << [time, c.shift_u]
  delay_u << [time, c.delay_u]
  err     << [time, c.err]
  iddi_err<< [time, c.iddi_err]
end

gather.call
world.evolve 10 do
  gather.call
end

# The buffer used to store u's history is available:
if false
  p c.delay_u_buffer_data
  p c.delay_u_buffer_offset
  p c.delay_u_delay
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
  plot.add iddi_err, %{title "iddi_err" with lines}
end

if RUBY_PLATFORM =~ /win32/
  puts "Press enter to continue"
end
