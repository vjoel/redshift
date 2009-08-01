#!/usr/bin/env ruby

require 'redshift/redshift'
require 'nr/random'

include RedShift

class FlowTestComponent < Component
  def finish test
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
    @alarm_seq = NR::Random::Exponential.new \
      :seed => nil, # 614822716,
      :mean => 0.5
    @state_seq = NR::Random::Discrete.new \
      :seed => nil, # 3871653669,
      :distrib =>
        {
          Alg   => 100,
          Diff  => 100,
          Euler => 100,
          Empty => 100
        }
    puts "\n\n  Flow_Transition used the following seeds:"
    puts "  alarm seed = #{@alarm_seq.seed}"
    puts "  state seed = #{@state_seq.seed}"
  end
  
  transition Enter => Switch
  
  transition Alg   => Switch, Diff  => Switch,
             Euler => Switch, Empty => Switch do
    guard { t >= @alarm_time }
    action {
#      puts "Switching to #{@state_seq.next} at #{@alarm_time} sec."
#      puts "x = #{x}, t = #{t}."
      @alarm_time += @alarm_seq.next
#      puts "  Next switch at #{@alarm_time} sec.\n\n"
      ## unless we eval x here, the alg flow for x might not be up to date.
      if (state == Empty)
        @last_empty_t = t
        self.x = 10 * t   # manually update x
      end
    }
  end
  
  transition Switch => Alg do
    guard { @state_seq.current == Alg }
  end
  transition Switch => Diff do
    guard { @state_seq.current == Diff }
  end
  transition Switch => Euler do
    guard { @state_seq.current == Euler }
  end
  transition Switch => Empty do
    guard { @state_seq.current == Empty }
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


# Test what happens to a var when transitioning from a state in which
# it is defined algebraically to a state in which is has no definition.
# (This isn't quite the same as Flow_StateChange.)

class Flow_AlgebraicToEmptyFlow < FlowTestComponent
  state :A, :B
  transition Enter => A
  transition A => B do guard {world.clock > 1} end
  flow A do alg "x = 1" end
  def assert_consistent test
    return if world.clock > 2 ## should be a way to remove this component
    if state == B
      test.assert_in_delta(0, x, 1E-10) ## is this what we want?
    end
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
