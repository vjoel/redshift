require 'redshift'

include RedShift

class Flow_Euler < Component
  flow do
    euler "x' = 1"
    euler "y' = x" # y is a poor approx of z, due to Euler
    alg   "z = pow(x,2)"
  end
end

world = World.new
c = world.create(Flow_Euler)

x, y, z = [], [], []
x << [world.clock, c.x]
y << [world.clock, c.y]
z << [world.clock, c.z]
world.evolve 10 do
  x << [world.clock, c.x]
  y << [world.clock, c.y]
  z << [world.clock, c.z]
end

require 'sci/plot'
include Plot::PlotUtils

gnuplot do |plot|
  plot.command %{set title "Euler Integration"}
  plot.command %{set xlabel "time"}
  plot.add x, %{title "x" with lines}
  plot.add y, %{title "y" with lines}
  plot.add z, %{title "z" with lines}
end
