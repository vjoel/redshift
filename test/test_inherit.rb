#!/usr/bin/env ruby

require 'redshift'

include RedShift

=begin

=test_inherit.rb

One big, complex test class hierarchy, for testing mixed features.

=end

class A < Component

  attr_accessor :t
  
  state :S0, :S1, :S2
  
  setup { start S0; @x = -100000; @t = 0 } # To override
  
  flow(S0, S1, S2) { diff "t' = 1" }
  
  flow(S0) { diff "x' = 1" }
  flow(S1) { diff "x' = -10" }   # To override
  flow(S2) { diff "x' = 100" }
  
  transition S0 => S1 do guard { @t > 1 }; action { @t -= 1 } end

  # To override:
  transition(S1 => S2) {
    name :from_S1_to_S2  # so that inheritance knows what to replace
    guard { @t > 0.5 }; action { puts "KABOOM!" }
  }

end

class B < A

  state :S3
  
  setup { @x = 0 }

  flow(S1) { diff "x' = -20" }   # To override
  flow(S3) { diff "x' = 1000", "t' = 1" }
  
  transition(S1 => S2) {
    name :from_S1_to_S2
    guard { @t > 1 }; action { @t -= 1 }
  }
  
  transition(S2 => S3) { guard { @t > 1 }; action { @t -= 1 } }

end

class C < B

  state :S4

  flow(S1) { diff "x' = 10" }
  flow(S4) { diff "x' = 10000", "t' = 1" }

  transition(S3 => S4) { guard { @t > 1 }; action { @t -= 1 } }

end

class Z < Component

  attr_accessor :t
  
  state :S0, :S1, :S2, :S3, :S4

  setup { start S0; @x = 0; @t = 0 }

  flow(S0, S1, S2, S3, S4) { diff "t' = 1" }
  
  flow(S0) { diff "x' = 1" }
  flow(S1) { diff "x' = 10" }
  flow(S2) { diff "x' = 100" }
  flow(S3) { diff "x' = 1000" }
  flow(S4) { diff "x' = 10000" }
  
  transition(S0 => S1) { guard { @t > 1 }; action { @t -= 1 } }
  transition(S1 => S2) { guard { @t > 1 }; action { @t -= 1 } }
  transition(S2 => S3) { guard { @t > 1 }; action { @t -= 1 } }
  transition(S3 => S4) { guard { @t > 1 }; action { @t -= 1 } }
  
end


require 'test/unit'

class TestInherit < Test::Unit::TestCase
  
  def setup
    @world = World.new
    @world.time_step = 0.1
  end
  
  def teardown
    @world = nil
  end
  
  def test_mixed
    c = @world.create(C)
    z = @world.create(Z)
    
    # Static assertions
    c_state_names = c.states.map {|s| s.name}
    z_state_names = z.states.map {|s| s.name}
    assert_equal([], c_state_names - z_state_names)
    assert_equal([], z_state_names - c_state_names)
    
    # Dynamic assertions
    while @world.clock <= 10 do
      @world.run
      
      assert_equal(c.t, z.t,
                   "time #{@world.clock}\n")
      assert_equal(c.state.name, z.state.name,
                   "time #{@world.clock}\n c.t: #{c.t} z.t: #{z.t}")
    
      assert_in_delta(c.x, z.x, 0.000001)
    end
  end
end
