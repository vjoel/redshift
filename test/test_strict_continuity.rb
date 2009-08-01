#!/usr/bin/env ruby

require 'redshift'

include RedShift

# Tests strictly continuous vars.

class StrictContinuityComponent < Component
  def finish(test); end
end

class A < StrictContinuityComponent
  strictly_continuous :x
  flow do
    diff "x' = 1"
  end
  
  setup do
    @guard1_count = 0
    @guard2_count = 0
    @x_event_time = nil
  end
  
  transition Enter => Exit do
    guard {@guard1_count += 1; x > 0.95} ## use hook for this?
    action do
      @x_event_time = world.clock
    end
  end

  transition Enter => Exit do
    guard {@guard2_count += 1; x > 0.95} ## use hook for this?
    action do
      @x_event_time = world.clock
    end
  end

  def assert_consistent(test)
    case state
    when Enter
      # Should not check the guard more than once per step, or so.
      test.assert(@guard1_count <= world.step_count + 1)
      test.assert(@guard1_count >= world.step_count)
      
      test.assert(@guard2_count <= world.step_count + 1)
      test.assert(@guard2_count >= world.step_count)
    when Exit
      test.assert_equal(1.0, @x_event_time)
    
      test.assert_raises(RedShift::ContinuousAssignmentError) do
        self.x = 3
      end
    end
  end
end

# This component exists to give the A instance a chence to make too many
# guard checks.
class B < StrictContinuityComponent
  flow do
    diff "time' = 1"
  end
  
  state :S, :T, :U
  setup do
    start S
  end
  
  transition S => T do
    guard "time > 0"
    action {self.time = 0}
  end
  
  transition T => U, U => S

  def assert_consistent(test)
  end
end


#-----#

require 'test/unit'

class TestStrictContinuity < Test::Unit::TestCase
  
  def setup
    @world = World.new
    @world.time_step = 0.1
  end
  
  def teardown
    @world = nil
  end
  
  def test_strict_continuity
    testers = []
    ObjectSpace.each_object(Class) do |cl|
      if cl <= StrictContinuityComponent and
         cl.instance_methods.include? "assert_consistent"
        testers << @world.create(cl)
      end
    end
    
    testers.each { |t| t.assert_consistent self }
    @world.run 10 do
      testers.each { |t| t.assert_consistent self }
    end
    testers.each { |t| t.finish self }
    
    a = testers.find {|t| t.class == A}
    assert_equal(StrictContinuityComponent::Exit, a.state)

    b = testers.find {|t| t.class == B}
    assert(b)
  end
end
