#!/usr/bin/env ruby

require 'redshift/redshift'

include RedShift

class FlowTestComponent < Component
end

# Make sure timers work!

class Flow_Euler < FlowTestComponent
  flow { euler "t' = 1" }
  setup { @t = 0 }
  def assert_consistent test
    test.assert_equal_float(world.clock, t, 0.0000000001)
  end
end

# Trig functions.

class Flow_Sin < FlowTestComponent
  flow { diff  "y' = y_prime", "y_prime' = -y" }
  setup { @y = 0; @y_prime = 1 }
  def assert_consistent test
    test.assert_equal_float(sin(world.clock), y, 0.000000001)
    ## is this epsilon ok? how does it compare with cshift?
  end
end

# Exp functions.

class Flow_Exp < FlowTestComponent
  flow { diff  "y' = y" }
  setup { @y = 1 }
  def assert_consistent test
    test.assert_equal_float(exp(world.clock), y, 0.0001)
  end
end

# Polynomials.

class Flow_Poly < Flow_Euler    # note use of timer t from Flow_Euler
  flow {
    alg   "poly = -6 * t**3 + 1.2 * t**2 - t + 10"
    diff  "y' = y1", "y1' = y2", "y2' = y3", "y3' = 0"
  }
  setup { @y = 10; @y1 = -1; @y2 = 1.2 * 2; @y3 = -6 * 3 * 2 }
  def assert_consistent test
    test.assert_equal_float(poly, y, 0.000000001)
  end
end

# other kinds of flows: cached algebraic, cflows, ...

# test when several flows of different kinds are used simultaneously,
#  esp. when substituting euler for rk4
#  i.e., test composition: alg w/ alg, diff w/ alg., etc.

class Flow_MixedType < FlowTestComponent
  flow  {
    euler "w' = 4"
    diff  "x' = w"
    diff  "y' = 4"
    diff  "z' = y"  ### fails if these are more complex than just w or y
  }
  setup { @w = @y = 0; @x = @z = 0 }
  def assert_consistent test
    test.assert_equal_float(x, z, 0.001, "at time #{world.clock}")
  end
end


#-----#

require 'runit/testcase'
require 'runit/cui/testrunner'
require 'runit/testsuite'

class TestInheritFlow < RUNIT::TestCase
  
  def setup
    @world = World.new { time_step 0.01 }
  end
  
  def teardown
    @world = nil
  end
  
  def test_inherit_flow
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
  end
end

END {
  RUNIT::CUI::TestRunner.run(TestInheritFlow.suite)
}
