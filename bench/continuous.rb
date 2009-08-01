# Measures performance of redshift as a pure integrator.
#
# Formulas are minimal to factor out C library time.

require 'redshift'

include RedShift

module Continuous
  class C < Component
    strictly_continuous :x, :y
    flow do
      diff " x' =   y "
      diff " y' =  -x "
    end
  end
  
  def self.make_world n=1
    w = World.new
    n.times do
      w.create(C) do |c|
        c.x = 0.0
        c.y = 1.0
      end
    end
    w
  end

  def self.do_bench
    [ [       1, 1_000_000],
      [      10,   100_000],
      [     100,    10_000],
      [   1_000,     1_000],
      [  10_000,       100],
      [ 100_000,        10] ].each do
      |     n_c,     n_s|
      
      w = make_world(n_c)
      w.run 1 # warm up
      r = bench do
        w.run(n_s)
      end
      
      yield "  - %10d comps X %10d steps: %8.2f" % [n_c, n_s, r]
    end
  end
end

if __FILE__ == $0
  require File.join(File.dirname(__FILE__), 'bench')
  puts "continuous:"
  Continuous.do_bench {|l| puts l}
#  puts "continuous:", (1..3).map {Continuous.do_bench}
  
  if false
    require 'ruby-prof'

    w = Continuous.make_world(10_000)
    result = RubyProf.profile do
      w.run(10)
    end

    printer = RubyProf::GraphPrinter.new(result)
    printer.print(STDOUT, 0)
  end
end

