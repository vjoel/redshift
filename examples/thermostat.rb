require 'redshift'

class Thermostat < RedShift::Component
  continuous :temp
  
  state :Heat, :Off

  flow Heat do
    diff "temp' = (68 - temp)/3"
  end

  flow Off do
    diff "temp' = (45 - temp)/10"
  end
  
  transition Heat => Off do
    guard "temp > 68 - 0.1"
  end
  
  transition Off => Heat do
    guard "temp < 66"
  end
  
  setup do
    start Off
  end
end

world = RedShift::World.new do |w|
  w.time_step = 0.1
end

thermostat = world.create Thermostat do |t|
  t.temp = 55
end

temp_history = []
world.evolve 30 do |w|
  point = [w.clock, thermostat.temp]
  #puts point.join(" ")
  temp_history << point
end

require 'sci/plot'
include Plot::PlotUtils

gnuplot do |plot|
  plot.command %{set title "Thermostat control"}
  plot.command %{set xlabel "time"}
  plot.add temp_history, %{title "temperature" with lines}
end

sleep 1 if /mswin32|mingw32/ =~ RUBY_PLATFORM
