#!/usr/bin/env ruby

require 'redshift'

include RedShift

=begin

This file tests discrete features of RedShift, such as transitions and events. Inheritance of discrete behavior is tested separately in test_interit*.rb.

=end

class DiscreteTestComponent < Component
  def initialize(*args)
    super
    @t = world.clock if world
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

class Discrete_2a < DiscreteTestComponent
  default {@prev_world = world}
  start Exit
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
  state :A, :B; start A
  transition A => B do
    event :e => 3
  end
  transition B => Exit do
    event :e => 4
  end
end

class Discrete_4b < DiscreteTestComponent
  state :A, :B; start A
  link :x
  constant :x_e_value_in_reset
  
  transition A => B do
    sync :x => :e
    guard {
      @x_e_value_in_guard = [x.e] #no value during guard
      true
    }
    reset :x_e_value_in_reset => proc {x.e}
    action {
      @x_e_value_in_action = x.e
    }
    post {
      @x_e_value_in_post = x.e
    }
  end
  
  transition B => Exit do
    sync :x => :e
    guard {
      @x_e_value_in_guard2 = [x.e] #no value during guard
      true
    }
  end
  
  setup { self.x = create Discrete_4a }
  def assert_consistent test
    test.assert_equal(Exit, state)
    test.assert_equal([nil], @x_e_value_in_guard)
    test.assert_equal(3, @x_e_value_in_action)
    test.assert_equal(3, @x_e_value_in_post)
    test.assert_equal(3, x_e_value_in_reset)
    test.assert_equal([nil], @x_e_value_in_guard2)
  end
end

# event value is true by default, and nil when not exported

class Discrete_5a < DiscreteTestComponent
  transition Enter => Exit do event :e end
end

class Discrete_5b < DiscreteTestComponent
  link :x
  transition do
    sync :x => :e
    action {@x_e = [x.e]}
  end
  setup { self.x = create Discrete_5a }
  def assert_consistent test
    test.assert_equal([true], @x_e)
    test.assert_equal(nil, x.e)
  end
end

# event value can be supplied statically...

class Discrete_6a < DiscreteTestComponent
  EventValue = [[3.75], {1 => :foo}]
  transition Enter => Exit do
    event :e => EventValue
  end
end

class Discrete_6b < DiscreteTestComponent
  link :x
  transition do
    sync :x => :e
    action {@x_e = x.e}
  end
  setup { self.x = create Discrete_6a }
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
  link :x
  transition do
    sync :x => :e
    action {@x_e = x.e}
  end
  setup { self.x = create Discrete_7a }
  def assert_consistent test
    test.assert_equal(Discrete_7a::EventValue, @x_e)
  end
end

# Also, can use C exprs.

class Discrete_7c < DiscreteTestComponent
  constant :z => 0.31
  transition Enter => Exit do
    event :g => "z+0.11"
  end
end

class Discrete_7d < DiscreteTestComponent
  state :A
  link :x => Discrete_7c
  setup { self.x = create Discrete_7c }
  transition Enter => A do
    sync :x => :g
    action {@x_g = x.g}
  end
  def assert_consistent test
    test.assert_equal(A, state)
    test.assert_in_delta(0.42, @x_g, 1.0E-10)
  end
end

# a guard testing for event doesn't need a block

class Discrete_8a < DiscreteTestComponent
  state :A, :B
  transition Enter => A do
    event :e
  end
  transition A => B do
    event :f => 2.3, :g => literal("x+1") # Not an expr!
  end
end

class Discrete_8b < DiscreteTestComponent
  state :A, :B
  transition Enter => A do
    sync :x => :e
  end
  transition A => B do
    sync [:x, :f]    # alt. syntax, in future will allow value
    action {@x_f = x.f; @x_g = x.g}
  end
  link :x => Discrete_8a
  setup { self.x = create Discrete_8a }
  def assert_consistent test
    test.assert_equal(B, state)
    test.assert_equal(2.3, @x_f)
    test.assert_equal("x+1", @x_g)
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
    sync :x => :e
  end
  transition A => B do
    sync [:x, :f]
    sync :x => :e      # x.f AND x.e
    # or we could write sync :x => [:f, :e]
  end
  transition A => C do
    sync [:x, :f]
    guard do false end   # x.f AND FALSE
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
  state :A, :B, :C
  transition Enter => A do
    guard "x.v == 1", "0"
  end
  transition Enter => B do
    guard "x.v == 1"
    sync :x => :f
  end
  transition Enter => C do
    guard "x.v == 1" do false end
  end
  link :x => Discrete_11a
  setup { self.x = create Discrete_11a }
  def assert_consistent test
    test.assert_equal(Enter, state)
  end
end

# testing for an event in link which is nil is false

class Discrete_12a < DiscreteTestComponent
  transition do
    event :e
  end
end

class Discrete_12b < DiscreteTestComponent
  link :comp => Discrete_12a
  transition Enter => Exit do
    sync :comp => :e
  end
  def assert_consistent test
    test.assert_equal(Enter, state)
  end
end

# test when the state actually changes during a transition
# (to wit, after the last clause)

class Discrete_13 < DiscreteTestComponent
  state :A1, :A2
  start A1
  flow A1 do alg "var = 1" end
  flow A2 do alg "var = 2" end
  transition A1 => A2 do
    action {@x = var}
    action {@xx = var}
  end
  transition A2 => Exit do
    action {@y = var}
    action {@yy = var}
  end
  def assert_consistent test
    test.assert_equal(1, @x)
    test.assert_equal(1, @xx)
    test.assert_equal(2, @y)
    test.assert_equal(2, @yy)
  end
end

# test that resets and events all happen in parallel

class Discrete_14 < DiscreteTestComponent
  state :A1, :A2, :B1, :B2
  continuous :x
  link :other => self

  default {start A1}
  setup {
    self.x = 1
    self.other ||= create(self.class) { |c|
      start B1
      self.x = 10
      c.other = self
    }
  }

  transition A1 => A2 do
    reset :x => "other.x"
    event :e => "x"
  end
  transition A2 => Exit do
    reset :x => proc { other.e.to_i }
  end
  
  transition B1 => B2 do
    reset :x => "other.x"
    event :e => "x"
  end
  transition B2 => Exit do
    reset :x => proc { other.e.to_i }
  end

  def assert_consistent test
    case state
    when A1
      test.assert_equal(1, x)
      test.assert_equal(nil, e)
    when A2
      test.assert_equal(10, x)
      test.assert_equal(1, e)
    when B1
      test.assert_equal(10, x)
      test.assert_equal(nil, e)
    when B2
      test.assert_equal(1, x)
      test.assert_equal(10, e)
    end
  end
end

# multiple simultaneous events

class Discrete_15a < DiscreteTestComponent
  transition Enter => Exit do
    event {e; f}
  end
end

class Discrete_15b < DiscreteTestComponent
  link :x => Discrete_15a
  setup { self.x = create Discrete_15a }
  transition Enter => Exit do
    sync :x => [:e, :f]
  end
  def assert_consistent test
    test.assert_equal(Exit, state)
  end
end

# priority of transitions is based on program text

class Discrete_16 < DiscreteTestComponent
  state :S
  transition(Enter => S) {name "C"; action {@pass=true}}
  transition(Enter => S) {name "B"; action {@pass=false}}
  transition(Enter => S) {name "A"; action {@pass=false}}
  transition(Enter => S) {name "X"; action {@pass=false}}
  transition(Enter => S) {name "Y"; action {@pass=false}}
  transition(Enter => S) {name "Z"; action {@pass=false}}
  def assert_consistent test
    test.flunk("transitions are not in priority order") unless @pass
  end
end

# Multiple transitions in one definition are allowed (but discouraged since
# they are not checked in order).
class Discrete_17 < DiscreteTestComponent
  state :A, :B
  transition Enter => A, A => B
  def assert_consistent test
    test.assert_equal(B, state)
  end
end

# Multiple transitions can be defined using arrays of source states.
class Discrete_18 < DiscreteTestComponent
  state :A, :B
  transition [A, Enter] => B
  def assert_consistent test
    test.assert_equal(B, state)
  end
end

# Check that post actions work.
class Discrete_19 < DiscreteTestComponent
  state :A
  constant :x
  transition Enter => A do
    reset :x => 1
    post {@x = x}
  end
  def assert_consistent test
    test.assert_equal(1, @x)
  end
end

# Check that false guards are never taken, but nil (empty) guards always are.
class Discrete_20 < DiscreteTestComponent
  transition Enter => Exit do
    guard false
    action { @fail = true }
  end
  transition Enter => Exit do
    guard nil
  end
  def assert_consistent test
    test.assert_equal(Exit, state)
    test.assert_equal(nil, @fail)
  end
end

# guard expr accepts "lnk.lnk"
class Discrete_21 < DiscreteTestComponent
  link :lnk => self, :old_lnk => self
  
  total = 2
  setup do
    self.name = total
    if total > 0
      total -= 1
      self.lnk = create(self.class)
    end
  end
  
  transition Enter => Exit do
    guard "lnk && lnk.lnk"
    reset :lnk => "lnk.lnk", :old_lnk => "lnk"
  end
  
  def assert_consistent test
    if name == 2
      test.assert_equal(Exit, state)
      test.assert_equal(old_lnk.lnk, lnk)
    else
      test.assert_equal(Enter, state)
    end
  end
end

# alg flow evaluated after state change remembers its value,
# even if never explicitly evaluated before.
class Discrete_22 < DiscreteTestComponent
  state :S
  flow Enter do
    alg " x = 123 "
  end
  transition Enter => S
  
  def assert_consistent test
    if state == S
      test.assert_equal(123, x)
    end
  end
end

=begin

test timing of other combinations of
  action, guard, event, reset

test guard phases

=end

#-----#

require 'test/unit'

class TestDiscrete < Test::Unit::TestCase
  
  def setup
    @world = World.new
    @world.time_step = 0.1
  end
  
  def teardown
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
