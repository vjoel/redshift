#!/usr/bin/env ruby
require 'redshift'
require 'benchmark'
require 'plot/plot'

include RedShift
include Benchmark
include Math

$n = 3
$reps = 2000
$fmla = " x' = sin(t) + cos(t) + sin(2*t) * cos(2*t)"

class Foo < Component

  flow {
    differential $fmla
    euler " t' = 1 "
  }
  
  defaults { @x = -1; @t = 0 }

end

class FooC < Component

  flow {
    differential_c $fmla
    euler_c " t' = 1 "
  }
  
  defaults { @x = -1; @t = 0 }

end


foo = []                         ;  foo_c = []
w = World.new {time_step 0.1}    ;  w_c = World.new {time_step 0.1}
$n.times {foo << w.create(Foo)}  ;  $n.times {foo_c << w_c.create(FooC)}


print "#{$n} objects, #{$reps} repetitions, integrating #{$fmla}.\n"

pr = proc { |f| 10.times { f.x } }
pl_rb = []
pl_c = []

bm(12) do |test|
  2.times do
    GC.start
    test.report("In Ruby:") do
      w.run($reps) {
        foo.each &pr
        pl_rb << [w.clock, foo[0].x]
      }
    end
    GC.start
    test.report("In C:") do
      w_c.run($reps) {
        foo_c.each &pr
        pl_c << [w_c.clock, foo_c[0].x]
      }
    end
  end
end

Plot.new ('gnuplot') {
  add pl_rb, 'title "rb" with lines'
  add pl_c, 'title "c" with lines'
  show
  pause 5
}

in_rb = eval "foo[0].x"
in_c  = eval "foo_c[0].x"

if in_rb != in_c
  raise "Not equal: got #{in_rb} in ruby, but #{in_c} in c."
end
