#!/usr/bin/env ruby
require 'redshift.rb'

include RedShift

class Observer < Component

  attr_accessor :b
  
  Done = State.new "Done", [], []

  Normal =
    State.new "Normal", [],
      [Transition.new nil, Done, proc {@save_dent = b.dent}, [],
       proc {
         print "Time #{world.clock_now}. Dent is #{@save_dent}\n"}]
  
  def set_defaults
    @state = Normal
  end
  
end

class Ball < Component

  attr_accessor :a
  
  Stopped =
    State.new "Stopped", [], []
  
 	Falling =
    State.new "Falling",
      [(AlgebraicFlow.new "y_err",
          "t = world.clock_now
           (@y0 + @v0 * t + 0.5 * @a * t ** 2 - y).abs"),
       (RK4DifferentialFlow.new "y", "v"),
       (EulerDifferentialFlow.new "v", "a")],
      [Transition.new nil, Stopped,
        proc {y <= 0},
        [Event.new(:dent)], proc {self.v = -v}]
	
  Falling.attach Ball
  
  def set_defaults
    @state = Falling
    @y0 = 100.0
    @v0 = 0.0
    @y = @y0
    @v = @v0
    @a = -9.8
    @y_err
    def self.dent
      nil
    end
  end
  
  def setup
  end
  
  def dent
   y.abs
  end
  
  def inspect
    printf "y = %8.4f, v = %8.4f, y_err = %8.6f%16s",
           @y, @v, y_err, @state.name
  end

end # class Ball

if __FILE__ == $0

w = World.new {
  time_step 0.01
}

$b = w.create(Ball) {}
$obs = w.create(Observer) {@b = $b}

#print "\nWorld:\n\n" + w.inspect.gsub!(',', "\n") + "\n"

600.times do
  t = w.clock_now
  if t == t.floor
    print "\nTime #{t}\n"
  end
  p $b
  w.run
end

#print "\nBall:\n\n" + $b.inspect.gsub!(',', "\n") + "\n"

end
