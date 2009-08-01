#!/usr/bin/env ruby
require 'redshift/redshift.rb'

include RedShift
include Math

class Test < Component

  def fexp x
    (1000 * exp(x/1000.0)).round
  end
  
  def fpow x, n
    (1000 * (x/1000.0)**n).round
  end

  attach Enter, [
    EulerDifferentialFlow.new(:t, "1"),
##    AlgebraicFlow.new(:true_x, "1000 * fpow(t, 3) / fexp(t)")
    AlgebraicFlow.new(:true_x, "1000*sin(t)")
  ]
  
  attach Enter, [
##    RK4DifferentialFlow.new(:x, "3 * x / t - x")
###      "(3 * t**2 - t**3) / exp(t)"
    RK4DifferentialFlow.new(:x, "y"),
    RK4DifferentialFlow.new(:y, "-x"),
  ]
  
  def setup
    @t = 0.0
##    @x = fpow(@t, 3) / fexp(@t)
    @x = 0.0
    @y = 1.0
  end
  
  def inspect
    sprintf "Time %5.2f:  true_x: %12.6f  x: %12.6f  err: %12.6f",
            t, true_x, x, (true_x - x).abs
  end

end


if __FILE__ == $0

w = World.new {
  time_step 1
}

test = w.create(Test) {}

for i in 1..1000
  p test
  w.run 1
end
p test
#puts "Press return.\n"; gets

end
