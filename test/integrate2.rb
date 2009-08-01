#!/usr/bin/env ruby
require 'redshift/redshift.rb'

include RedShift
include Math

class Test < Component

  attach Enter, [
    EulerDifferentialFlow.new(:t, "1"),
    AlgebraicFlow.new(:true_x, "cos(t) + exp(t)")
  ]
  
  attach Enter, [
    RK4DifferentialFlow.new(:x,  "x1"),
    RK4DifferentialFlow.new(:x1, "x2"),
    RK4DifferentialFlow.new(:x2, "x3"),
    RK4DifferentialFlow.new(:x3, "x")
  ]
  
  def setup
    @t  = 0.0
    @x  = 2.0
    @x1 = 1.0
    @x2 = 0.0
    @x3 = 1.0
  end
  
  def inspect
    sprintf "Time %5.2f:  true_x: %12.6f  x: %12.6f  err: %12.6f",
            t, true_x, x, (true_x - x).abs
  end

end


if __FILE__ == $0

w = World.new {
  time_step 0.01
}

test = w.create(Test) {}

loop do
  p test
  w.run
end

end
