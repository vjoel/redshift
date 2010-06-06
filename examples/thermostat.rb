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

world.evolve 30 do |w|
  puts [w.clock, thermostat.temp].join(" ")
end

