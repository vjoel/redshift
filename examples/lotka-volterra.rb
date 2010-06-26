require 'redshift'

class Population < RedShift::Component
  flow do
    diff " rabbits' = 0.3*rabbits - 0.02 * rabbits * foxes "
    diff " foxes'   = 0.01*foxes*rabbits - 0.5 * foxes "
  end
end

world = RedShift::World.new do |w|
  w.time_step = 0.05
end

pop = world.create Population
pop.foxes = 2
pop.rabbits = 100

data = []
world.evolve 100 do |w|
  data << [w.clock, pop.foxes, pop.rabbits]
end

require 'redshift/util/plot'
include Plot::PlotUtils

gnuplot do |plot|
  plot.command %{set title "Lotka-Volterra"}
  plot.command %{set xlabel "time"}
  plot.add data, %{using 1:2 title "foxes" with lines}
  plot.add data, %{using 1:3 title "rabbits" with lines}
end

sleep 1 if /mswin32|mingw32/ =~ RUBY_PLATFORM
