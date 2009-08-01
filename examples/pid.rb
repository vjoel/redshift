# PID control example
# See http://en.wikipedia.org/wiki/PID_control.

require 'redshift'
include RedShift

srand(12345)

# Variable with discrete and continuous perturbation.
class Plant < Component
  continuous :x => 0, :t => 1
  
  link :control => :Control # fwd ref to undefined class Control
  
  flow do
    diff " x' = control.output + sin(t) "
    diff " t' = -1 "
  end
  
  transition do
    guard "t <= 0"
    action do
      self.t += rand * 20
      self.x += (rand - 0.5) * 10
    end
  end
end

# Tries to bring x back to the set_point.
class Control < Component
  continuous :set_point => 2.0
  continuous :p_out, :i_out, :d_out, :output
  
  # Gains
  constant :k_p => 1.0,
           :k_i => 1.0,
           :k_d => 1.0
  
  link :plant => Plant
  
  flow do
    algebraic     " error   = set_point - plant.x "
    algebraic     " p_out   = k_p * error "
    differential  " i_out'  = k_i * error "
    algebraic     " d_out   = k_d * (- sin(plant.t)) "
      # since in plant we have x' = control.output + sin(t)
      # and we can algebraically remove the "output" term.
      # this is a special case that doesn't need numerical differentiation
    algebraic     " output  = p_out + i_out + d_out "
  end
end

world = World.new
plant = world.create Plant
control = world.create Control
control.plant = plant
plant.control = control

x, p_out, i_out, d_out, output = [], [], [], [], []

world.evolve 1000 do
  time = world.clock
  x       << [time, plant.x]
  p_out   << [time, control.p_out]
  i_out   << [time, control.i_out]
  d_out   << [time, control.d_out]
  output  << [time, control.output]
end

require 'sci/plot'
include Plot::PlotUtils

gnuplot do |plot|
  plot.command %{set title "PID control"}
  plot.command %{set xlabel "time"}
  plot.add x, %{title "x" with lines}
  plot.add p_out, %{title "p_out" with lines}
  plot.add i_out, %{title "i_out" with lines}
  plot.add d_out, %{title "d_out" with lines}
  plot.add output, %{title "output" with lines}
end

if RUBY_PLATFOM =~ /win32/
  puts "Press enter to continue"
end
