#!/usr/bin/env ruby

require 'redshift'
require 'redshift/util/random'
### TODO: add pure ruby ISAAC to util
#require 'isaac'

# Adaptor class to use ISAAC with redshift/util/random distributions.
#class ISAACGenerator < ISAAC
#  def initialize(*seeds)
#    super()
#    if seeds.compact.empty?
#      seeds = [Random::Sequence.random_seed]
#    end
#    @seeds = seeds
#    srand(seeds)
#  end
#  
#  attr_reader :seeds
#
#  alias next rand
#end

include RedShift

class FlowTestComponent < Component
  def finish test
  end
end

# Shows that despite lazy eval of alg flows, they do get evaled before
# changing states.

class Flow_Transition_Alg_To_Other < FlowTestComponent
  state :A, :B
  start A
  flow A do
    alg "x=42"
  end
  transition A => B
  
  def assert_consistent test
    if state == B
      test.assert_equal(42, x)
    end
  end
end

# state changes which change the type of flow

class Flow_Transition < FlowTestComponent
  state :Alg, :Diff, :Euler, :Empty, :Switch
  
  flow Alg, Diff, Euler, Empty do
    diff "t' = 1"
  end
  
  flow Alg do
    alg "x = 10*t"
  end
  
  flow Diff do
    diff "x' = 10"
  end
  
  flow Euler do
    euler "x' = 10"
  end
  
  setup do
    self.x = 0
    @alarm_time = 0
    @alarm_seq = Random::Exponential.new(
      #:generator => ISAACGenerator,
      :seed => 614822716,
      :mean => 0.5
    )
    @state_seq = Random::Discrete.new(
      #:generator => ISAACGenerator,
      :seed => 3871653669, ## doesn't make sense to re-seed the same global gen
      :distrib =>
        {
          Alg   => 100,
          Diff  => 100,
          Euler => 100,
          Empty => 100
        }
    )
    puts "\n\n  Flow_Transition used the following seeds:"
    puts "  alarm seed = #{@alarm_seq.generator.seeds rescue @alarm_seq.generator.seed}"
    puts "  state seed = #{@state_seq.generator.seeds rescue @state_seq.generator.seed}"
  end
  
  transition Enter => Switch,
             Alg   => Switch, Diff  => Switch,
             Euler => Switch, Empty => Switch do
    guard { t >= @alarm_time }
    action {
#      puts "Switching to #{@state_seq.next} at #{@alarm_time} sec."
#      puts "x = #{x}, t = #{t}."
      @alarm_time += @alarm_seq.next
      @current = @state_seq.next
#      puts "  Next switch at #{@alarm_time} sec.\n\n"
      ## unless we eval x here, the alg flow for x might not be up to date.
      if (state == Empty)
        @last_empty_t = t
        self.x = 10 * t   # manually update x
      end
    }
  end
  
  transition Switch => Alg do
    guard { @current == Alg }
  end
  transition Switch => Diff do
    guard { @current == Diff }
  end
  transition Switch => Euler do
    guard { @current == Euler }
  end
  transition Switch => Empty do
    guard { @current == Empty }
  end
  
  transition Empty => Empty do
    guard { t > (@last_empty_t || 0) }
    action {
      @last_empty_t = t
      self.x = 10 * t   # manually update x
    }
  end
  
  def assert_consistent test
    # In the alg case, calling the accessor invokes the update method. We want
    # to test that alg flows work even if the update method isn't called.
    unless state == Alg
      test.assert_in_delta(
        10 * t,
        x,
        0.00000000001,
        "in #{state.name} after #{t} sec,\n")
    end
  end
  
  def finish test
#    puts "At finish: t = #{t}, alarm_time = #{@alarm_time}"
  end
end


# After changing out of a state with an alg flow, the variable should
# have a value defined by that flow, even if the flow was never
# explicitly referenced. Check that the strict optimization doesn't
# interfere with this evaluation.
class Flow_LeavingAlgebraic < FlowTestComponent
  continuous :x
  strictly_continuous :y
  state :S, :T
  flow S do
    alg " x = 42 "
    alg " y = 43 "
  end
  transition Enter => S, S => T
  def assert_consistent test
    if state == T
      test.assert_equal(42, x)
      test.assert_equal(43, y)
    end
  end
end


# Test what happens when a transition changes the algebraic flow of a variable

class Flow_AlgToAlg < FlowTestComponent
  state :A, :B
  flow A, B do diff "t' = 1" end
  flow A do alg "x = 1" end
  flow B do alg "x = 2" end
  start A
  transition A => B do
    guard "t > 0.2"
    action do
      @snapshotA = x
    end
  end
  transition B => B do
    guard {!@snapshotB}
    action do
      @snapshotB = x
    end
  end
  def assert_consistent test
    return if t > 0.4 ## should be a way to remove this component
    case state
    when A; test.assert_equal(1, x)
    when B; test.assert_equal(2, x)
            test.assert_equal(1, @snapshotA)
            test.assert_equal(2, @snapshotB)
    end
  end
end

# Test what happens during an action when an algebraic flow's inputs change.
# The alg flow's value *does* change during the action, if there are changes
# in any of the links, continuous vars, or constants that it depends on.

class Flow_AlgebraicAction < FlowTestComponent
  continuous :x, :y
  constant :k
  link :other => self
  flow {alg " x = other.y + k "}
  
  @@first = true
  
  setup do
    self.other = self
    if @@first
      @@first = false
      @other = create(Flow_AlgebraicAction) {|c| c.y = 5}
    end
  end
  
  transition Enter => Exit do
    action do
      next unless @other
      
      @x_values = []
      @x_values << x
      other.y = 1
      @x_values << x
      other.y = 2
      @x_values << x
      
      self.other = @other
      @x_values << x
      
      self.k = 10
      @x_values << x
    end
  end

  def assert_consistent test
    test.assert_equal([0,1,2,5,15], @x_values) if @x_values
  end
end


#-----#

require 'test/unit'

class TestFlow < Test::Unit::TestCase
  
  def setup
    @world = World.new
    @world.time_step = 0.01
    @world.zeno_limit = 100
  end
  
  def teardown
    @world = nil
  end
  
  def test_flow
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= FlowTestComponent and
         cl.instance_methods.include? "assert_consistent"
        testers << @world.create(cl)
      end
    end
    
    testers.each { |t| t.assert_consistent self }
    @world.run 1000 do
      testers.each { |t| t.assert_consistent self }
#      testers.reject! { |t| t.state == Exit }
    end
    testers.each { |t| t.finish self }
  end
end

END {

#  require 'plot/plot'
#  Plot.new ('gnuplot') {
#    add Flow_Reconfig::Y, 'title "y" with lines'
#    add Flow_Reconfig::Y1, 'title "y1" with lines'
#    add Flow_Reconfig::Y2, 'title "y2" with lines'
#    add Flow_Reconfig::Y3, 'title "y3" with lines'
#    show
#    pause 5
#  }

}
