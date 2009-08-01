# Measures performance of redshift queues.

require 'redshift'

module Queue
  class Clock < RedShift::Component
    # the only continuous var in the whole system
    strictly_continuous :time
    flow {
      diff " time' = 1 "
    }
  end
  
  class Sender < RedShift::Component
    strict_link :clock => Clock
    
    constant :next_wakeup
    strictly_constant :period
    
    # list of target queues that this comp will send to
    def targets
      @targets ||= []
    end
    
    setup do
      self.next_wakeup = period
    end
    
    transition do
      guard " clock.time >= next_wakeup "
      reset :next_wakeup => " clock.time + period "
      action do 
        targets.each do |target|
          target << :awake
        end
      end
    end
  end
  
  class Receiver < RedShift::Component
    def wake_for_queue; end ###
    queue :q
    transition do
      wait :q
      action do
        q.pop
      end
    end
  end
  
  def self.make_world n_sender=1, n_receiver=0
    w = RedShift::World.new
    clock = w.create(Clock)
    n_sender.times do |i|
      sender = w.create(Sender) do |s|
        s.clock = clock
        s.period = ((i % 99)+1) / 10.0
        n_receiver.times do
          w.create(Receiver) do |r|
            s.targets << r.q
          end
        end
      end
    end
    w
  end

  def self.do_bench
    [1, 10, 100].each do |n_r|
      [1, 10, 100].each do |n_s|
        n_steps = 100_000 / (n_r * n_s)
        do_bench_one(n_s, n_steps, n_r) {|r| yield r}
      end
    end
  end
  
  def self.do_bench_one(n_s, n_steps, n_r)
    w = make_world(n_s, n_r)
    r = bench do
      w.run(n_steps)
    end

    yield "  - %10d senders X %10d steps X %5d receivers: %8.2f" %
      [n_s, n_steps, n_r, r]
  end
end

if __FILE__ == $0
  require File.join(File.dirname(__FILE__), 'bench')
  puts "queue:"
  Queue.do_bench_one(10, 1000, 10) {|l| puts l}
end
