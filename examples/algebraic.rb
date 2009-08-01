#!/usr/bin/env ruby
require 'redshift/redshift'
require 'benchmark'

include RedShift
include Benchmark

$exp = 10
$n = 10
$reps = 1000

class Foo < Component

  flow {
    algebraic %{ y1 = 2.0 }
    for i in (2..$exp)
      algebraic %{ y#{i} = y1 * y#{i-1} }
    end
  }

end

class FooC < Component

  flow {
    algebraic_c %{ y1 = 2.0 }
    for i in (2..$exp)
      algebraic_c %{ y#{i} = y1 * y#{i-1} }
    end
  }

end


foo = []                         ;  foo_c = []
w = World.new {time_step 0.1}    ;  w_c = World.new {time_step 0.1}
$n.times {foo << w.create(Foo)}  ;  $n.times {foo_c << w.create(FooC)}


print "#{$n} objects, #{$reps} repetitions, calculating 2^#{$exp}.\n"

bm(12) do |test|
  test.report("In Ruby:") do
    w.run $reps
  end
  test.report("In C:") do
    w_c.run $reps
  end
end

in_rb = eval "foo[0].y#{$exp}"
in_c  = eval "foo_c[0].y#{$exp}"

if in_rb != in_c
  raise "Not equal: got #{in_rb} in ruby, but #{in_c} in c."
end

# Typical results:
#
#   10 objects, 1000 repetitions, calculating 2^20.
#                     user     system      total        real
#   In Ruby:     23.990000   0.000000  23.990000 ( 23.984814)
#   In C:         0.030000   0.000000   0.030000 (  0.031595)
#
# The difference is partly due to the common sub-expression
# optimizer in RedShift's flow parser. The algorithm for calculating
# 2^n is repeated multiplication, which is slooowwww in Ruby.
