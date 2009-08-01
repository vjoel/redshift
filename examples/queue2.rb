# More complex example of queues, showing multiple queues, multiple
# simultaneous entries in a queue, and several kinds of matching.

require 'redshift'

include RedShift

class MyMessage
  attr_accessor :foo
  def initialize foo
    @foo = foo
  end
end
class OtherMessage; end

class Receiver < Component
  def wake_for_queue; puts "wake_for_queue"; end ###

  queue :q1, :q2 # same as attr_reader :q, plus initialize q to a new queue
  
  transition do
    # is there at least one instance of MyMessage on the *head* of the queue,
    # with foo=="bar"?
    wait :q1 => [MyMessage, proc {|m| m.foo == "bar"}]
    action do
      puts "messages received -- q1: #{q1.pop.inspect}"
    end
  end

  transition do
    # is there at least one instance of MyMessage on the *head* of the queue?
    # and also OtherMessage on q2?
    wait :q1 => MyMessage, :q2 => OtherMessage
    action do
      puts "messages received -- q1: #{q1.pop.inspect}, q2: #{q2.pop.inspect}"
    end
  end

  transition do
    # wait for numbers, explicitly handling the case of multiple
    # objects (assume all are numeric) pushed into the queue
    # simultaneously
    wait :q1 => Numeric
    action do
      x = q1.pop
      case x
      when SimultaneousQueueEntries
        x = x.max # choose the largest, and ignore the smaller, arbitrarily
      end
      puts "max x = #{x}"
    end
  end

  transition do
    wait :q1 # is there *anything* on the head of the queue?
      # note that this guard is checked after the MyMessage guard, so
      # this transition functions as an "else" clause
    action do
      p q1.pop
    end
  end
end

class Sender < Component
  link :r => Receiver
  state :S1, :S2, :S3, :S4
  
  transition Enter => S1 do
    action do
      r.q1 << MyMessage.new("bar")
    end
  end
  
  transition S1 => S2 do
    action do
      r.q1 << MyMessage.new("zzz")
      r.q2 << OtherMessage.new
    end
  end
  
  transition S2 => S3 do
    action do
      r.q1 << 1.2
      r.q1 << 42.0
    end
  end
  
  transition S3 => S4 do
    action do
      r.q1 << {"foo"=>[:bar, self.inspect, self, r.q1]}  # some weird hash
    end
  end
end

w = World.new
w.create Sender do |s|
  s.r = w.create(Receiver)
end

w.evolve 1
