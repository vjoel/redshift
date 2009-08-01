#!/usr/bin/env ruby

require 'redshift'

include RedShift

class FlowTestComponent < Component
  def finish test
  end
end

# Empty flows are constant.

class Flow_Empty < FlowTestComponent
  continuous :x
  setup { self.x = 5 }
  def assert_consistent test
    test.assert_in_delta(5, x, 0.0000000000001)
  end
end

# Make sure timers work!

class Flow_Euler < FlowTestComponent
  flow { euler "t' = 1" }
  setup { self.t = 0 }
  def assert_consistent test
    test.assert_in_delta(world.clock, t, 0.0000000001)
  end
end

# Alg flows.

class Flow_Alg < FlowTestComponent
  flow { alg "f = 1", "g = f + 2" }
  def assert_consistent test
    test.assert_in_delta(1, f, 0.0000000001)
    test.assert_in_delta(3, g, 0.0000000001)
  end
end

# Trig functions.

class Flow_Sin < FlowTestComponent
  flow { diff  "y' = y_prime", "y_prime' = -y" }
  setup { self.y = 0; self.y_prime = 1 }
  def assert_consistent test
    test.assert_in_delta(sin(world.clock), y, 0.000000001)
    ## is this epsilon ok? how does it compare with cshift?
  end
end

# Exp functions.

class Flow_Exp < FlowTestComponent
  flow { diff  "y' = y" }
  setup { self.y = 1 }
  def assert_consistent test
    test.assert_in_delta(exp(world.clock), y, 0.0001)
  end
end

# Polynomials.

class Flow_Poly < Flow_Euler    # note use of timer t from Flow_Euler
  flow {
    alg   "poly = -6 * pow(t,3) + 1.2 * pow(t,2) - t + 10"
    diff  "y' = y1", "y1' = y2", "y2' = y3", "y3' = 0"
  }
  setup { self.y = 10; self.y1 = -1; self.y2 = 1.2 * 2; self.y3 = -6 * 3 * 2 }
  def assert_consistent test
    test.assert_in_delta(poly, y, 0.000000001, "at time #{world.clock}")
  end
end

# test for detection of circularity and assignment to algebraically
# defined vars

class Flow_AlgebraicErrors < FlowTestComponent
  flow {
    alg "x = y"
    alg "y = x"
    alg "z = 1"
  }
  
  def assert_consistent test
    return if world.clock > 1
    test.assert_raises(RedShift::CircularDefinitionError) {y}
    test.assert_raises(RedShift::AlgebraicAssignmentError) {self.z = 2}
  end
end

# Assignments to continuous vars force update of alg flows

class Flow_AlgUpdate_Assignment < FlowTestComponent
  flow {alg "y = x"}
  continuous :x

  def assert_consistent test
    return if world.clock > 1
    test.assert_in_delta(0, y, 1E-10);
    self.x = 1
    test.assert_in_delta(1, y, 1E-10);
    self.x = 0
  end
end

# Test that a diff flow that refers to an alg flow updates it during c.u. and
# that the updated value is used in the next d.u. This is related to the 
# var->d_tick assignment in step_continuous(). We're testing that the
# optimization doesn't *prevent* the evaluation of y.
class Flow_AlgDiff < FlowTestComponent
  flow {
    alg  " x = 3*y "
    diff " y' = x  "
  }
  state :S1
  default {self.y = 1}
  transition Enter => S1 do
    guard "y > 5"
    action {@x = x; @y = y}
  end
  
  def assert_consistent test
    if @x
      test.assert_in_delta(3*@y, @x, 1E-10)
      @x = @y = nil
    end
  end
end

## TO DO ##
=begin
 
 varying time step (dynamically?)
 
 handling of syntax errors
 
=end

###class Flow_MixedType < FlowTestComponent
###  flow  {
###    euler "w' = 4"
###    diff  "x' = w"
###    diff  "y' = 4"
###    diff  "z' = y"  ### fails if these are more complex than just w or y
###  }
###  setup { self.w = self.y = 0; self.x = self.z = 0 }
###  def assert_consistent test
###    test.assert_in_delta(x, z, 0.001, "at time #{world.clock}")
###  end
###end


#-----#

require 'test/unit'

class TestFlow < Test::Unit::TestCase
  
  def setup
    @world = World.new
    @world.time_step  = 0.01
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
