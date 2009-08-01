#!/usr/bin/env ruby

require 'redshift/redshift'

include RedShift

# Tests resets in transitions.

class A < Component
  continuous :x
  continuous :y
  
  link :other => A
  
  state :S1, :S2
  
  transition Enter => S1 do
    reset :y => 1           # literal value
  end

  transition S1 => S2 do
    reset :x => "other.x",  # expr value
          :y => proc {10-y} # proc value
  end
  
  transition S2 => Exit
end

require 'test/unit'

class TestReset < Test::Unit::TestCase
  
  def setup
    @world = World.new
    @world.time_step = 0.1
  end
  
  def teardown
    @world = nil
  end
  
  def test_reset
    a1 = @world.create(A)
    a2 = @world.create(A)
    
    a1.other = a2
    a2.other = a1
    
    a1.x = v1 = 5
    a2.x = v2 = 1.23
    
    @world.run 1
    
    assert_equal(v2, a1.x)
    assert_equal(v1, a2.x)
    
    assert_equal(9, a1.y)
    assert_equal(9, a2.y)
  end
end

