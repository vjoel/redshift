# Example of using sync and events to exchange data in parallel. This assumes that
# the two components are already linked, so it doesn't scale well. A scalable
# solution would separate detection into a cell mechanism or something, and use
# queues to notify the vehicles. This example is more about collision _handling_
# than _detection_.

require 'redshift'

class Ball < RedShift::Component
  link :other => Ball
  continuous :v
  constant :dir
  
  state :Moving
  
  transition Enter => Moving do
    action do
      self.dir = other.x < x ? -1 : 1
    end
  end
  
  flow Moving do
    diff " x' = v "
  end
  
  transition Moving => Moving do
    guard " dir * (other.x - x) < 0 "
    guard {other.other == self}
      # meaning: only if other is colliding with self
      # The guard above is a bit unnecessary in this model,
      # but in general it is needed.
    sync :other => :collision
    event :collision
    reset :v => "other.v", :x => "other.x"
  end
end

w = RedShift::World.new
b1 = w.create Ball
b2 = w.create Ball
b1.other = b2
b2.other = b1
b1.x =   0.0
b1.v =  30.0
b2.x = 100.0
b2.v = -70.0

b1_x, b2_x = [], []
gather = proc do
  time = w.clock
  b1_x << [time, b1.x]
  b2_x << [time, b2.x]
end

gather.call
w.evolve 1.2 do
  gather.call
end

require 'sci/plot'
include Plot::PlotUtils

gnuplot do |plot|
  plot.command %{set title "Bouncing balls"}
  plot.command %{set xlabel "time"}
  plot.add b1_x, %{title "b1.x" with lines}
  plot.add b2_x, %{title "b2.x" with lines}
end

sleep 1 if /mswin32|mingw32/ =~ RUBY_PLATFORM
