require "redshift"
require "plot/plot"

include RedShift

class TimeKeeper < Component
  default { self.t = 0 }      # t is a "slot" or "instance var",
  flow { euler "t' = 1" }     # uses the default state, Enter
end

class Timer < TimeKeeper      # inherits the default and the flow
  transition do
    guard {t > 10}
    action {self.t -= 10}
    event :tick
  end
end

class Vehicle < Component
  state :SpeedUp, :SlowDown
  
  default do                  # "do .. end" and "{ .. }" are almost the same
    self.x = 0
    self.xDot = 20
    start SlowDown         # alt. to "transition Enter => SlowDown"
  end
  
  flow SpeedUp, SlowDown do   # both states have same flow
    diff "xDot' = xDDot"
    diff "x' = xDot"
  end
  
  flow SpeedUp do
    alg "xDDot = 3"
  end
  
  flow SlowDown do
    alg "xDDot = -3"
  end
  
  transition SpeedUp => SlowDown, SlowDown => SpeedUp do
    guard {@timer.tick}
  end
    
  setup do
    @timer = create(Timer)
  end
end

# done with defs, now script a world and a plot

w = World.new { time_step 0.1 }
v = w.create(Vehicle) {
  self.xDot = 30                  # override default
}

data = [ [w.clock, v.x] ]

w.run 200 do
  data << [w.clock, v.x]      # each timestep, append data
end

fork do
  Plot.new('gnuplot') {
    add data, 'title "xDot" with lines'
    show
    pause 500
  }
end
Process.wait
