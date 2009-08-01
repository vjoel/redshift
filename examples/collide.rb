# Example of using sync and events to exchange data in parallel. This assumes that
# the two components are already linked, so it doesn't scale well. A scalable
# solution would separate detection into a cell mechanism or something, and use
# queues to notify the vehicles. This example is more about collision _handling_
# than _detection_.

require 'redshift'

class Ball < RedShift::Component
  link :other => Ball
  continuous :v
  
  flow do
    diff " x' = v "
    alg  " dist = fabs(other.x - x) "
    alg  " speed = (x < other.x) ? (v - other.v) : (other.v - v) " # approach speed
  end
  
  transition do
    guard " speed > 0 && dist/speed < 0.1 "
              # about to collide (assuming timestep 0.1) ...
          proc {other.other == self}     # ...and other is looking at self
    sync :other => :collision
    event :collision
    reset :v => "other.v"
  end
end

w = RedShift::World.new
b1 = w.create Ball
b2 = w.create Ball
b1.other = b2
b2.other = b1
b1.x = 0.0
b1.v = 6.0
b2.x = 10.0
b2.v = -4.0

w.evolve 1.2 do
  p w
  p b1
  p b2
end
