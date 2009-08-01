require 'redshift'
require 'enumerator'

include RedShift

module Inertness
  class Inert < Component
    # An inert component is one that has no transitions out of its
    # current state. However, flows are allowed. But for a sharper
    # comparison, we don't define any.
    #
    #  flow do
    #    diff " t' = 1 "
    #  end
  
    # Adding just one trivial transition prevents the inert optimization,
    # with dramatic effects (increase of 60% cpu time in first case).
    #
    # 1000 comps X      10000 steps X          0 non-inert:    +0.60
    # 1000 comps X      10000 steps X          1 non-inert:    +0.59
    #
    #  transition Enter => Exit do
    #    guard "0"
    #  end
    #
    # Turning off the inert optimization in the world source, without adding
    # a transition, is a bit less dramatic, but a more realistic indicator
    # of the value of the optimization:
    #
    # 1000 comps X      10000 steps X          0 non-inert:    +0.39
    # 1000 comps X      10000 steps X          1 non-inert:    +0.36
  end

  class NonInert < Component
    n_states = 10
      # increasing this doesn't make the difference (w/ and w/o the inert
      # optimization) larger because the inerts go on strict sleep anyway.
    my_states = state((0...n_states).map {|i| "S#{i}"})
    start S0
    flow S0 do
      diff " t' = 1 "
    end
    transition S0 => S1 do
      guard " t >= 0.1 "
      reset :t => 0
    end
    my_states[1..-1].each_cons(2) do |s, t|
      transition s => t
    end
    transition my_states.last => my_states.first
  end
  
  def self.make_world n_inert, n_non_inert=0
    w = World.new
    n_inert.times {w.create(Inert)}
    n_non_inert.times {w.create(NonInert)}
    w
  end

  def self.do_bench
    [0, 1].each do |n_non_inert|
      [ [        0,  10_000],
        [     1000,  10_000] ].each do
        | n_inert,      n_s|

        w = make_world(n_inert, n_non_inert)
        w.run 1 # warm up
        r = bench do
          w.run(n_s)
        end

        yield "  - %10d comps X %10d steps X %10d non-inert: %8.2f" %
          [n_inert, n_s, n_non_inert, r]
      end
    end
  end
end

if __FILE__ == $0

  require File.join(File.dirname(__FILE__), 'bench')
  puts "inert:"
  Inertness.do_bench {|l| puts l}

exit

  n_inert     = 10000
  n_non_inert = 0
  n_steps     = 1000


  times = Process.times
  t0 = Time.now
  pt0 = times.utime #+ times.stime

  w.run n_steps

  times = Process.times
  t1 = Time.now
  pt1 = times.utime #+ times.stime
  puts "process time: %8.2f" % (pt1-pt0)
  puts "elapsed time: %8.2f" % (t1-t0)

end

__END__

The best case so far is:

without inert optimization
process time:     6.58
elapsed time:     6.59

with inert optimization
process time:     5.11
elapsed time:     5.12
