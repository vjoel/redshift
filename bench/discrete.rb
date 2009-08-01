# Measures performance of redshift for pure discrete event simulation.
# See also the queue.rb benchmark.

require 'redshift'

include RedShift

module Discrete
  class Clock < Component
    # the only continuous var in the whole system
    strictly_continuous :time
    flow {
      diff " time' = 1 "
    }
  end
  
  class Awakener < Component
    export :awake
  end
  
  class Sleeper < Awakener
    strict_link :clock => Clock
    
    constant :next_wakeup
    strictly_constant :period
    
    setup do
      self.next_wakeup = period
    end
    
    transition do
      guard " clock.time >= next_wakeup "
      reset :next_wakeup => " clock.time + period "
        ## need something between strict and not:
        ## only changes at end of discrete update, and so
        ## strictness optimizations still apply
      event :awake
    end
  end
  
  class Watcher < Awakener
    link :target => Awakener
    transition do
      sync :target => :awake
      event :awake
    end
  end
  
  def self.make_world n_sleeper=1, n_watchers=0
    w = World.new
    clock = w.create(Clock)
    n_sleeper.times do |i|
      sleeper = w.create(Sleeper) do |c|
        c.clock = clock
        c.period = ((i % 99)+1) / 10.0
      end
      target = sleeper
      n_watchers.times do
        target = w.create(Watcher) do |c|
          c.target = target
        end
      end
    end
    w
  end

  def self.do_bench
    [0, 1, 5].each do |n_w|
      [ [       1, 1_000_000   ],
        [      10,   100_000   ],
        [     100,    10_000   ],
        [   1_000,     1_000   ],
        [  10_000,       100   ],
        [ 100_000,        10   ] ].each do
        |     n_c,       n_s|
        if n_w > 1
          do_bench_one(n_c, n_s/n_w, n_w) {|r| yield r}
        else
          do_bench_one(n_c, n_s, n_w) {|r| yield r}
        end
      end
    end
  end
  
  def self.do_bench_one(n_c, n_s, n_w)
    w = make_world(n_c, n_w)
    r = bench do
      w.run(n_s)
    end

    yield "  - %10d comps X %10d steps X %5d watchers: %8.2f" %
      [n_c, n_s, n_w, r]
  end
end

if __FILE__ == $0
  require File.join(File.dirname(__FILE__), 'bench')
  puts "discrete:"
  Discrete.do_bench_one(100, 5_000, 5) {|l| puts l}
end

