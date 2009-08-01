#!/usr/bin/env ruby

require 'redshift/redshift'

include RedShift

=begin

This file tests discrete features of RedShift, such as transitions and events. Inheritance of discrete behavior is tested separately in test_interitance*.rb.

=end

class DiscreteTestComponent < Component
  def initialize(*args)
    super
    @t = @world.clock
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
  transition do guard {not @check}; action {@check = true} end
  def assert_consistent test
    test.assert(@check)
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
    test.assert_equal(:removed, world)
    test.assert_nil(@prev_world.find {|c| c == self})
  end
end

# start <state> sets the start state, but fails after initialization

class Discrete_3 < DiscreteTestComponent
  state :A
  default { start A }
  def assert_consistent test
    test.assert_equal(A, state)
    test.assert_exception(RuntimeError) {start A}
  end
end

# during a transition, the state method returns the initial state
# and active_transition returns the transition.
# after the transition, the state method returns the terminal state
# and active_transition returns nil and the event method returns nil.

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
    action {
      @x_state_after = @x.state.name
      @x_trans_after = @x.active_transition
      @x_e_after = @x.e
    }
  end
  setup { @x = create Discrete_4a }
  def assert_consistent test
    test.assert_equal(B, state)
    test.assert_equal(:A, @x_state_during)
    test.assert_equal("zap", @x_trans_during.name)
    test.assert_equal(:B, @x_state_after)
    test.assert_nil(@x_trans_after)
    test.assert_nil(@x_e_after)
  end
end

# event value is true by default

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
  end
end

# event value can be supplied by method

class Discrete_6a < DiscreteTestComponent
  EventValue = [[3.75], {1 => :foo}]
  transition Enter => Exit do event :e end
  def e; EventValue; end
end

class Discrete_6b < DiscreteTestComponent
  transition do
    guard {@x.e && @x_e = @x.e}  # note assignment
  end
  setup { @x = create Discrete_6a }
  def assert_consistent test
    test.assert_equal(Discrete_6a::EventValue, @x_e)
  end
end

# 

## guard: when it is evaluated, what context

## action: when does it happen, what does it affect

## test parallelism (will only work after changing algorithm)

## transition A=>B, C=>D is same as two clauses.

## stress test to make sure events are never lost, if someone is listening

#-----#

require 'runit/testcase'
require 'runit/cui/testrunner'
require 'runit/testsuite'

class TestDiscrete < RUNIT::TestCase
  
  def setup
    @world = World.new { time_step 0.1 }
  end
  
  def teardown
    @world = nil
  end
  
  def test_inherit_trans
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

END {
  Dir.mkdir "tmp" rescue SystemCallError
  Dir.chdir "tmp"

  RUNIT::CUI::TestRunner.run(TestDiscrete.suite)
}
