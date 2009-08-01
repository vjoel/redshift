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
  
  start S1
  
  flow S1 do
    alg " x = 1 "
  end
  flow S2 do
    alg " x = 2 "
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

class ResetVarToNonFloat < Component
  continuous :var
  state :S
  transition Enter => S do
    reset :var => proc {nil}
  end
end

class ResetLink < Component
  link :lnk => C
  state :S
  transition Enter => S do
    reset :lnk => proc {create(C) {|c| c.kk = 1.337}}
  end
end

class ResetLinkToNil < Component
  link :lnk => C
  state :S
  transition Enter => S do
    reset :lnk => proc {nil}
  end
end

class ResetLinkToWrongType < Component
  link :lnk => C
  state :S
  transition Enter => S do
    reset :lnk => proc {create(A)}
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

    assert_equal(B::S1, b.state)
    assert_equal(1, b.x)

    @world.run 1

    assert_equal(B::S2, b.state)
    assert_equal(2, b.x)
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
  
  def test_reset_var_to_wrong_type
    rl = @world.create(ResetVarToNonFloat)
    assert_raises(VarTypeError) {@world.run 1}
  end
  
  def test_reset_link
    rl = @world.create(ResetLink)
    assert_equal(nil, rl.lnk)
    @world.run 1
    assert_equal(C, rl.lnk.class)
    assert_equal(1.337, rl.lnk.k)
  end
  
  def test_reset_link_to_nil
    rl = @world.create(ResetLinkToNil)
    assert_equal(nil, rl.lnk)
    @world.run 1
    assert_equal(nil, rl.lnk)
  end
  
  def test_reset_link_to_wrong_type
    rl = @world.create(ResetLinkToWrongType)
    assert_raises(LinkTypeError) {@world.run 1}
  end
end
