# Example of some basic features of queues. Uses strings as messages
# just to make the matching examples simple. See also queue2.rb.

require 'redshift'

include RedShift

class Receiver < Component
  queue :q
  
  transition do
    wait :q => /time is now 2/
    action do
      msg = q.pop
      puts "SPECIAL CASE! popped #{msg.inspect} at time #{world.clock}"
    end
  end

  transition do
    wait :q => [/time is/, /3/]
    action do
      msg = q.pop
      puts "CONJUNCTION! popped #{msg.inspect} at time #{world.clock}"
    end
  end

  transition do
    wait :q => /time is/
    action do
      msg = q.pop
      puts "popped #{msg.inspect} at time #{world.clock}"
    end
  end
end

class Sender < Component
  link :receiver
  flow {diff "t' = 1"}
  
  transition do
    guard "t>1"
    reset :t => 0
    action do
      msg = "time is now #{world.clock}"
      puts "pushed #{msg.inspect}"
      receiver.q << msg
    end
  end
end

w = World.new
receiver = w.create Receiver
sender = w.create Sender
sender.receiver = receiver

w.evolve 5
