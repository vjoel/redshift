#!/usr/bin/env ruby
require 'redshift'

include RedShift

class Observer < Component
  link :ball => :Ball
  state :Observing
  
  transition Enter => Observing

  transition Observing => Observing do
    guard {ball.impact}
    action {print "\n\t ***** Time of impact #{world.clock}.\n\n"}
  end
  
  transition Observing => Exit do
    guard {world.clock >= 20.0}
    action {print "\n\n ***** Observer leaving.\n\n"}
  end
end

class Ball < Component
  constant :y0, :v0, :a, :bounce_count
  state :Falling, :Rising
  
  flow Falling, Rising do
    differential  " y' = v "
    euler         " v' = a "
    
    euler         " t_elapsed' = 1.0 "
    algebraic     " true_y = y0 + v0 * t_elapsed +
                             0.5 * a * pow(t_elapsed, 2) "
    algebraic     " y_err = fabs(true_y - y) "
  end
  
  transition Falling => Rising do
    guard {y <= 0}
    event :impact
    action {
      self.v = -v
      self.y0 = y; self.v0 = v
      self.t_elapsed = 0.0
      self.bounce_count += 1
    }
  end
  
  transition Rising => Falling do
    guard {v <= 0}
  end
  
  transition Rising => Exit, Falling => Exit do
    guard "bounce_count >= 3"
  end
  
  defaults {
    start Falling
    self.y0 = 100.0
    self.v0 = 0.0
    self.a = -9.8
  }
  
  setup {
    self.y = y0; self.v = v0
    self.t_elapsed = 0.0
    self.bounce_count = 0
  }
  
  def inspect
    sprintf "y = %8.4f, v = %8.4f, y_err = %8.6f%16s",
            y, v, y_err, state
  end
end

w = World.new
w.time_step = 0.01

ball = w.create(Ball) {|b| b.a = -9.8}
obs = w.create(Observer) {|o|o.ball = ball}

y = [[w.clock, ball.y]]

while w.size > 0 do
  t = w.clock
  if t == t.floor
    print "\nTime #{t}\n"
  end
  p ball unless ball.state == Exit
  
  w.run
  
  y << [w.clock, ball.y]
end

require 'sci/plot'
include Plot::PlotUtils

gnuplot do |plot|
  plot.add y, 'title "height" with lines'
end
