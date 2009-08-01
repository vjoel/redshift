#!/usr/bin/env ruby
require 'redshift/redshift.rb'

include RedShift

class Observer < Component

  attr_accessor :ball
  
  state :Observing
  
  transition(Enter => Observing)

  transition(Observing => Observing) {
    guard {ball.impact}
    action {print "\n\t ***** Time of impact #{world.clock}.\n\n"}
  }
  
  transition(Observing => Exit) {
    guard {world.clock >= 20.0}
    action {print "\n\n ***** Observer leaving.\n\n"}
  }
  
end

class Ball < Component

  attr_accessor :a
  
 	state :Falling,:Rising
  
  flow(Falling, Rising) {
  
    differential  " y' = v "
    euler         " v' = a "
    
    euler         " t_elapsed' = 1.0 "
    algebraic     " true_y = @y0 + @v0 * t_elapsed +
                             0.5 * @a * t_elapsed ** 2 "
    algebraic     " y_err = (true_y - y).abs "
    
  }
  
  transition(Falling => Rising) {
    guard {y <= 0}
    event :impact
    action {
      @v = -v
      @y0 = y; @v0 = v
      @t_elapsed = 0.0
      @bounce_count += 1
    }
	}
  
  transition(Rising => Falling) {
    guard {v <= 0}
  }
  
  transition(Rising => Exit, Falling => Exit) {
    guard {@bounce_count == 3}
  }
	
  def set_defaults
    @state = Falling
    @y0 = 100.0
    @v0 = 0.0
    @a = -9.8
  end
  
  def setup
    @y = @y0; @v = @v0
    @t_elapsed = 0.0
    @bounce_count = 0
  end
  
  def inspect
    sprintf "y = %8.4f, v = %8.4f, y_err = %8.6f%16s",
            @y, @v, y_err, @state.name
  end

end # class Ball

if __FILE__ == $0

w = World.new {
  time_step 0.01
}

b = w.create(Ball) {@a = -20.0}
obs = w.create(Observer) {@ball = b}

while w.components.size > 0 do
  t = w.clock
  if t == t.floor
    print "\nTime #{t}\n"
  end
  p b
  w.run
end

end
