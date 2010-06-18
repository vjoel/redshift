# This example shows how to define things in a module and include that in a
# Component or World class.

require 'redshift'
require 'redshift/util/modular'

module ThermoStuff
  extend Modular
  
  continuous :temp
  
  state :Heat, :Off

  flow :Heat do # Must quote constants, since they are defined later
    diff "temp' = (68 - temp)/3"
  end

  flow :Off do
    diff "temp' = (45 - temp)/10"
  end
  
  transition :Heat => :Off do
    guard "temp > 68 - 0.1"
  end
  
  transition :Off => :Heat do
    guard "temp < 66"
  end
  
  setup do
    start :Off
  end
end

class Thermostat < RedShift::Component
  include ThermoStuff
  
  default do
    self.temp = 35
  end
end

world = RedShift::World.new
thermostat = world.create Thermostat

world.evolve 30 do |w|
  printf "%6.2f: %7.3f %s\n", w.clock, thermostat.temp, thermostat.state
end

