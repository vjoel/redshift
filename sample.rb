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
      [(EulerDifferentialFlow.new "y", "v"),
       (EulerDifferentialFlow.new "v", "a")],
      [Transition.new nil, Stopped,
        proc {y <= 0},
        [Event.new(:dent)], nil]
	
  Falling.attach Ball
  
  def set_defaults
    @state = Falling
    @y = 100.0
    @v = 0.0
    @a = -9.8
    def self.dent
      nil
    end
  end
  
  def setup
  end
  
  def dent
   y < 0 ? -y : 0
  end
  
  def inspect
#    super
    print "y is nil.\n" if @y == nil
    print "v is nil.\n" if @v == nil
    print "a is nil.\n" if @a == nil

    printf "y = %8.4f, v = %8.4f, a = %8.4f%16s", @y, @v, @a, @state.name
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
