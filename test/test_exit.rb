#!/usr/bin/env ruby

require 'redshift/redshift'

include RedShift

# Tests that exited components do not evolve continuously or discretely.

class ExitComponent < Component
  strictly_continuous :x
  flow do
    diff "x' = 1"
  end
  
  setup do
    @guard_count = 0
    @x_event_time = nil
  end
  
  transition Enter => Exit do
    guard {x > 0.5}
  end
  
  transition Exit => Exit do
    action {@transition_on_exit = true}
  end

  def assert_consistent(test)
    test.assert(!@transition_on_exit)
    test.assert(x < 0.61)
  end
end

#-----#

require 'test/unit'

class TestExit < Test::Unit::TestCase
  
  def setup
    @world = World.new
    @world.time_step = 0.1
  end
  
  def teardown
    @world = nil
  end
  
  def test_exit
    tc = @world.create(ExitComponent)
    
    tc.assert_consistent(self)
    @world.run 10 do
      tc.assert_consistent(self)
    end
    tc.assert_consistent(self)
  end
end

