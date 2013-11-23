# Measures performance of redshift as a pure integrator.
# using more complex formulas than in continuous.rb.

# Try replacing
#   CFLAGS   =  -fPIC -g -O2 
# with
#   CFLAGS   = -fPIC -O2 -march=i686 -msse2 -mfpmath=sse

$CFLAGS="-fPIC -O2 -march=native"
case RUBY_PLATFORM
when /x86_64/
  $CFLAGS << " -msse2 -mfpmath=sse"
end

require 'redshift'

include RedShift

module Formula
  class C < Component
    strictly_continuous :x, :y
    flow do
      diff " x' =   pow(y,3) + sqrt(fabs(sin(y))) "
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
    [ [       1, 100_000],
      [      10,  10_000],
      [     100,   1_000],
      [   1_000,     100],
      [  10_000,      10] ].each do
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
  Formula.do_bench {|l| puts l}
  
  if false
    require 'ruby-prof'

    w = Formula.make_world(10_000)
    result = RubyProf.profile do
      w.run(10)
    end

    printer = RubyProf::GraphPrinter.new(result)
    printer.print(STDOUT, 0)
  end

end

