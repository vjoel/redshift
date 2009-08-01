# Measures benefit of optimizing the case in which only some of the outgoing
# transitions are strict.

require 'redshift'
require 'enumerator'

include RedShift

module HalfStrict
  class Clock < Component
    # the only continuous var in the whole system
    strictly_continuous :t_strict
    flow {
      diff " t_strict' = 1 "
      diff " t' = 1 "
    }
  end
  
  class Observer < Component
    strict_link :clock => Clock
    
    transition do
      guard " clock.t_strict < 0 "
    end
    transition do
      guard " clock.t_strict < 0 "
    end
    transition do
      guard " clock.t_strict < 0 "
    end
    transition do
      guard " clock.t_strict < 0 "
    end
    transition do
      guard " clock.t_strict < 0 "
    end

    transition do
      guard " clock.t < 0 "
    end
  end
  
  class Dummy < Component
    n_states = 10
    my_states = state((0...n_states).map {|i| "S#{i}"})
    start S0
    
    flow S0 do
      diff " t' = 1 "
    end
    
    transition S0 => S1 do
      guard "t > 0"
      reset :t => 0
    end

    my_states[1..-1].each_cons(2) do |s, t|
      transition s => t
    end
    transition my_states.last => my_states.first
  end

  def self.make_world n_observers=1
    w = World.new
    w.create(Dummy)
    clock = w.create(Clock)
    n_observers.times do |i|
      observer = w.create(Observer) do |c|
        c.clock = clock
      end
    end
    w
  end

  def self.do_bench
    [ [      10,   100_000   ],
      [     100,    10_000   ],
      [   1_000,     1_000   ],
      [  10_000,       100   ],
      [ 100_000,        10   ] ].each do
      |     n_c,       n_s|
      
      do_bench_one(n_c, n_s) {|r| yield r}
    end
  end
  
  def self.do_bench_one(n_c, n_s)
    w = make_world(n_c)
    r = bench do
      w.run(n_s)
    end

    yield "  - %10d comps X %10d steps: %8.2f" %
      [n_c, n_s, r]
  end
end

if __FILE__ == $0
  require File.join(File.dirname(__FILE__), 'bench')
  puts "half-strict:"
  HalfStrict.do_bench_one(1000, 1000) {|l| puts l}
end

