require 'redshift.rb'

include RedShift

w = World.new {
  time_step 0.05
}

class Observer < Component

  attr_accessor :b
  
  Done = State.new "Done", [], []

  Normal =
    State.new "Normal", [],
      [Transition.new nil, Done, proc {@save_dent = b.dent}, [],
       proc {p b.dent; print "Dent is #{@save_dent}\n"}]
       #we need a begin-action and an end-action
  
  def set_defaults
    @state = Normal
  end
  
end

class Ball < Component

  attr_accessor :y, :v, :a
  
  Stopped =
    State.new "Stopped", [], []
  
 	Falling =
    State.new "Falling",
      [(EulerDifferentialFlow.new :add_to_y, Formula.new "@v"),
       (EulerDifferentialFlow.new :add_to_v, Formula.new "@a")],
      [Transition.new nil, Stopped,
        proc {y <= 0},
        [Event.new("dent")], nil]
	
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
  
  def add_to_v d
    @v += d
  end
  
  def add_to_y d
    @y += d
  end
  
  def dent
    y < 0 ? -y : 0
  end
  
  def inspect
#    super
    printf "y = %8.4f, v = %8.4f, a = %8.4f%16s\n", @y, @v, @a, @state.name
  end

end # class Ball

#p w.options

$b = w.create(Ball) {}
$obs = w.create(Observer) {@b = $b}

#print "\nWorld:\n\n" + w.inspect.gsub!(',', "\n") + "\n"

200.times do
  t = w.clock_now
  p t, t.floor  # huh?
  if t == t.floor
    print "\nTime #{t}\n"
  end
  w.run
  p $b
end

#print "\nBall:\n\n" + $b.inspect.gsub!(',', "\n") + "\n"
