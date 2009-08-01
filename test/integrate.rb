#!/usr/bin/env ruby
require 'redshift/redshift.rb'

include RedShift
include Math

=begin
Seems to run 10x slower than cshift, assuming mosky*2=tercel
but more accurate than .hs (?)
=end

class Test < Component

  attach Enter, [
    EulerDifferentialFlow.new(:t, "1"),
    AlgebraicFlow.new(:true_x, "sin(t)**2 + cos(t)*exp(1/(1+t))")
  ]
  
  attach Enter, [
    RK4DifferentialFlow.new(:x, "2 * s * c - s * e - c * e * f"),
#      "2 sin t cos t - sin t exp(1/(1+t)) - cos t exp(1/(1+t)) (1/(1+t))**2"
    RK4DifferentialFlow.new(:s, "c"),
    RK4DifferentialFlow.new(:c, "-s"),
    RK4DifferentialFlow.new(:e, "e * f"),
    RK4DifferentialFlow.new(:f, "-2 * f ** (3/2)")
  ]
  
  def setup
    @t = 0.0
    @x = exp(1)
    @s = 0.0
    @c = 1.0
    @e = exp(1)
    @f = 1.0
  end
  
  def inspect
    sprintf "Time %5.2f:  true_x: %12.6f  x: %12.6f  err: %12.6f",
            t, true_x, x, (true_x - x).abs
#    sprintf "Time %5.2f: true sin t = %10.7f approx sin t = %10.7f err = %10.7f",
#            t, sin(t), s, (sin(t) - s).abs
#    sprintf "Time %5.2f: true e(t) = %10.7f approx e(t) = %10.7f err = %10.7f",
#            t, exp(1/(1+t)), e, (exp(1/(1+t)) - e).abs
  end

end


if __FILE__ == $0

w = World.new {
  time_step 0.01
}

test = w.create(Test) {}

for i in 1..100
  p test
  w.run 1000
end
p test
puts "Press return.\n"; gets

end
