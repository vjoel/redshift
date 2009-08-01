#!/usr/bin/env ruby

require 'redshift/redshift'

include RedShift

=begin

This file tests discrete features of RedShift, such as transitions and events. Inheritance of discrete behavior is tested separately in test_interitance*.rb.

=end

class DiscreteTestComponent < Component
  def initialize(*args)
    super
    @t = world.clock
  end
end

# Enter is the default starting state

class Discrete_1 < DiscreteTestComponent
  def assert_consistent test
    test.assert_equal(state, Enter)
  end
end

# Transitions are Enter => Enter by default

class Discrete_1_1 < DiscreteTestComponent
  transition do
    guard {not @check}
    action {@check = true}
  end
  def assert_consistent test
    test.assert(@check == true)
  end
end

# Exit causes the component to leave the world

class Discrete_2 < DiscreteTestComponent
  def initialize(*args)
    super
    @prev_world = world
  end
  transition Enter => Exit
  def assert_consistent test
    test.assert_equal(Exit, state)
    test.assert_nil(world)
    test.assert_nil(@prev_world.find {|c| c == self})
  end
end

# 'start <state>' sets the start state, but fails after initialization

class Discrete_3 < DiscreteTestComponent
  state :A
  default { start A }
  def assert_consistent test
    test.assert_equal(A, state)
    test.assert_raises(AlreadyStarted) {start A}
  end
end

class Discrete_4a < DiscreteTestComponent
  state :A, :B; default { start A }
  transition A => B do
    name "zap"
    event :e
  end
end

class Discrete_4b < DiscreteTestComponent
  state :A, :B; default { start A }
  transition A => B do
    guard { 
      # during guard evaluation, the transition emitting e is still active
      if @x.e
        @x_state_during = @x.state.name
        @x_trans_during = @x.active_transition
      end
      @x.e
    }
    pass
  end
  setup { @x = create Discrete_4a }
  def assert_consistent test
    test.assert_equal(B, state)
    test.assert_equal(:A, @x_state_during)
    test.assert_equal("zap", @x_trans_during.name)
    test.assert_equal(:B, @x.state.name)
    test.assert_nil(@x.active_transition)
    test.assert_nil(@x_e_after)
  end
end

# event value is true by default, and false when not exported

class Discrete_5a < DiscreteTestComponent
  transition Enter => Exit do event :e end
end

class Discrete_5b < DiscreteTestComponent
  transition do
    guard {@x.e && @x_e = @x.e}  # note assignment
  end
  setup { @x = create Discrete_5a }
  def assert_consistent test
    test.assert_equal(true, @x_e)
    test.assert_equal(false, @x.e)
  end
end

# event value can be supplied statically...

class Discrete_6a < DiscreteTestComponent
  EventValue = [[3.75], {1 => :foo}]
  transition Enter => Exit do
    event :e => Discrete_6a::EventValue ## note scope is not Discrete_6a
  end
end

class Discrete_6b < DiscreteTestComponent
  transition do
    guard {@x.e}
    action {@x_e = @x.e}
  end
  setup { @x = create Discrete_6a }
  def assert_consistent test
    test.assert_equal(Discrete_6a::EventValue, @x_e)
  end
end

# ...or dynamically

class Discrete_7a < DiscreteTestComponent
  EventValue = [[3.75], {1 => :foo}]
  transition Enter => Exit do
    event {
      e {EventValue}
    }
  end
end

class Discrete_7b < DiscreteTestComponent
  transition do
    guard {@x.e}
    action {@x_e = @x.e}
  end
  setup { @x = create Discrete_7a }
  def assert_consistent test
    test.assert_equal(Discrete_7a::EventValue, @x_e)
  end
end

# a guard testing for event doesn't need a block

class Discrete_8a < DiscreteTestComponent
  state :A, :B
  transition Enter => A do
    event :e
  end
  transition A => B do
    event :f => 2.3
  end
end

class Discrete_8b < DiscreteTestComponent
  state :A, :B
  transition Enter => A do
    guard :x => :e
  end
  transition A => B do
    guard [:x, :f]    # alt. syntax, in future will allow value
    action {@x_f = x.f}
  end
  link :x => Discrete_8a
  setup { self.x = create Discrete_8a }
  def assert_consistent test
    test.assert_equal(B, state)
    test.assert_equal(2.3, @x_f)
  end
end

# multiple guard terms are implicitly AND-ed

class Discrete_9a < DiscreteTestComponent
  state :A, :B
  transition Enter => A do
    event :e
  end
  transition A => B do
    event :f
  end
end

class Discrete_9b < DiscreteTestComponent
  state :A, :B, :C
  transition Enter => A do
    guard :x => :e
  end
  transition A => B do
    guard [:x, :f], :x => :e      # x.f AND x.e
  end
  transition A => C do
    guard [:x, :f] do false end   # x.f AND FALSE
  end
  link :x => Discrete_9a
  setup { self.x = create Discrete_9a }
  def assert_consistent test
    test.assert_equal(A, state)
  end
end

# test C expressions as guards

class Discrete_10a < DiscreteTestComponent
  state :A, :B
  continuous :v
  transition Enter => A do
    action {self.v = 1}
  end
  transition A => B do
    action {self.v = 2}
  end
end

class Discrete_10b < DiscreteTestComponent
  state :A, :B
  transition Enter => A do
    guard "x.v == 1"
  end
  transition A => B do
    guard "x.v == 3"
  end
  link :x => Discrete_10a
  setup { self.x = create Discrete_10a }
  def assert_consistent test
    test.assert_equal(A, state)
  end
end

# multiple guard terms with C exprs

class Discrete_11a < DiscreteTestComponent
  state :A, :B
  continuous :v
  transition Enter => A do
    action {self.v = 1}
  end
  transition A => B do
    action {self.v = 2}
    event :e
  end
end

class Discrete_11b < DiscreteTestComponent
  state :A, :B
  transition Enter => A do
    guard "x.v == 1", "0"
  end
  transition Enter => A do
    guard "x.v == 1", :x => :e
  end
  transition Enter => A do
    guard "x.v == 1" do false end
  end
  link :x => Discrete_11a
  setup { self.x = create Discrete_11a }
  def assert_consistent test
    test.assert_equal(Enter, state)
  end
end

=begin

test timing of various combinations of
  action, guard, event, reset

test guard phases

=end

#-----#

require 'test/unit'

class TestDiscrete < Test::Unit::TestCase
  
  def set_up
    @world = World.new { time_step 0.1 }
  end
  
  def tear_down
    @world = nil
  end
  
  def test_discrete
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= DiscreteTestComponent and
         cl.instance_methods.include? "assert_consistent"
        testers << @world.create(cl)
      end
    end
    
    @world.run
    
    for t in testers
      t.assert_consistent self
    end
  end
end
