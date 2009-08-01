require 'redshift'
require 'enumerator'

include RedShift

module AlgState
  class PureAlg < Component
    # An algebraic state is one that has no diff flows in its
    # current state. However, algebraic flows are allowed.
    #
    # The diff_list optimization improves performance by about
    # a factor of 5.
    #
    flow do
      alg " x = 1 "
    end
  end

  class NonAlg < Component
    flow do
      diff " t' = 1 "
    end
  end
  
  def self.make_world n_alg, n_non_alg=0
    w = World.new
    n_alg.times {w.create(PureAlg)}
    n_non_alg.times {w.create(NonAlg)}
    w
  end

  def self.do_bench
    [0].each do |n_non_alg|
      [ [        0,   1_000],
        [       10,   1_000],
        [      100,   1_000],
        [     1000,   1_000],
        [    10000,   1_000] # cache nonlinearity happens here!
      ].each do
        |    n_alg,     n_s|

        w = make_world(n_alg, n_non_alg)
        w.run 1 # warm up
        r = bench do
          w.run(n_s)
        end

        yield "  - %10d comps X %10d steps X %10d non-alg: %8.2f" %
          [n_alg, n_s, n_non_alg, r]
      end
    end
  end
end

if __FILE__ == $0

  require File.join(File.dirname(__FILE__), 'bench')
  puts "alg-state:"
  AlgState.do_bench {|l| puts l}

end
