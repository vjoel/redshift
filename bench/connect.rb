# Measures performance of connected ports.
#
# Formulas are minimal to factor out C library time.

require 'redshift'

include RedShift

module Connect
  class Source < Component
    continuous :t
    flow do
      diff " t' = 1 "
    end
  end
  
  class Sink < Component
    input :t
    flow do
      diff " u' = t "
    end
  end
  
  class Connector < Component
    input :t
  end
  
  def self.make_world n=1
    w = World.new
    w.input_depth_limit = n
    source = w.create(Source)
    prev = source
    n.times do
      w.create(Connector) do |c|
        c.port(:t) << prev.port(:t)
        prev = c
      end
    end
    sink = w.create(Sink) do |s|
      s.port(:t) << prev.port(:t)
    end
    w
  end

  def self.do_bench
    [ #[       1, 1_000_000],
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

  require 'bench'
  w = Connect.make_world(1000)
  time = bench do
    w.run(1000)
  end
  p time

end

