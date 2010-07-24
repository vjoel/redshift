# Measures performance of redshift as an integrator with dynamically
# linked flows.
#
# Formulas are minimal to factor out C library time.

require 'redshift'

include RedShift

module LinkedFlows
  class C < Component
    strictly_continuous :x
    strict_link :d => 'LinkedFlows::D'
    flow do
      diff " x' =   d.y "
    end
  end

  class D < Component
    strictly_continuous :y
    strict_link :c => C
    flow do
      diff " y' =  -c.x "
    end
  end
  
  def self.make_world n=1
    w = World.new
    n.times do
      w.create(C) do |c|
        c.d = w.create(D) do |d|
          d.c = c
          d.y = 1.0
        end
        c.x = 0.0
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

  require 'bench'
  w = LinkedFlows.make_world(500)
  time = bench do
    w.run(500)
  end
  p time

end

