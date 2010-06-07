require 'redshift'

include RedShift

class Observer < Component
  link :ball => :Ball
  state :Observing, :Decision
  attr_reader :counter

  setup do
    @counter = 0
  end
  
  start Observing

  transition Observing => Decision do
    sync :ball => :impact
    action do
      print "\n\n ***** Time of impact #{world.clock}.\n\n"
      @counter += 1
    end
  end
  
  transition Decision => Exit do
    guard {@counter == 2}
    action {print " ***** Observer leaving after 2 bounces.\n\n"}
  end
  
  transition Decision => Observing do
    guard {@counter < 2}
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
    guard "y <= 0"
    event :impact
    reset :v  => "-v",
          :y0 => "y",
          :v0 => "-v",
          :t_elapsed => 0,
          :bounce_count => "bounce_count + 1"
    # The reset is essentially the same as:
    # action {
    #   self.v = -v
    #   self.y0 = y; self.v0 = v
    #   self.t_elapsed = 0.0
    #   self.bounce_count += 1
    # }
    # The difference: reset is faster, and has parallel semantics,
    # which is why ':v0 => "-v"', in place of 'self.v0 = v'.
  end
  
  transition Rising => Falling do
    guard "v <= 0"
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
w.create(Observer) {|o|o.ball = ball}

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

if ARGV.delete('-p')
  require 'redshift/util/plot'
  include Plot::PlotUtils

  gnuplot do |plot|
    plot.add y, 'title "height" with lines'
  end
else
  puts "use -p switch to show plot"
end
