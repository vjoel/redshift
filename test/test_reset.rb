#!/usr/bin/env ruby

require 'redshift'

include RedShift

# Tests resets in transitions.

class A < Component
  constant :k1, :k2

  continuous :x
  continuous :y
  
  link :other => A
  
  state :S1, :S2
  
  transition Enter => S1 do
    reset :y => 1           # literal value
  end

  transition S1 => S2 do
    reset :x => "other.x",  # expr value
          :y => proc {10-y}, # proc value
          :k1 => "y",
          :k2 => proc {42}
  end
  
  transition S2 => Exit
end

class B < Component
  state :S1, :S2
  
  flow Enter do
    diff " x' = 3 "
  end
  transition Enter => S1 do
    reset :x => 2
  end
  
  flow S1 do
    alg " x = 1 "
  end
  transition S1 => S2 do
    reset :x => 3
  end
end

class C < Component
  constant :k, :kk
  state :S
  transition Enter => S do
    reset :k => "kk"
  end
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
    
    assert_equal(1, a1.k1)
    assert_equal(42, a1.k2)
  end
  
  def test_reset_algebraic_flow_error
    b = @world.create(B)
    assert_raises AlgebraicAssignmentError do
      @world.step
    end
    assert_equal(B::S1, b.state)
      # there should have been no problem whie in Enter, where x not alg.
  end
  
  # This is to test the expansion of the reset value cache.
  def test_many_constant_resets
    ## need to get the limit as a const
    n = World::CV_CACHE_SIZE + 10
    cs = (0..n).map {|i| @world.create(C) {|c| c.kk = i}}
    @world.run 1
    cs.each do |c|
      assert_equal(c.kk, c.k)
    end
  end
end

