# A more complex example of the sync construct:
# clients make a request to a server (using a queue)
# the server syncs with the head of the queue, and
# provides the requested information.
#
# This shows the use of bi-directional sync, as well as
# using a guard to ensure that only the proper client can
# sync.

require 'redshift'

class Client < RedShift::Component
  state :Working, :Waiting
  start Working
  
  link :server
  
  flow Working do
    diff " time_left' = -1 "
  end
    
  transition Working => Waiting do
    guard "time_left <= 0"
    action do
      if server
        puts "%4.2f: #{self} requesting service" % world.clock
        server.clients << self
      end
    end
  end
  
  transition Waiting => Working do
    guard {server.client == self} # N.b.!
    sync :server => :serve
    event :accept
    post do
      self.time_left = server.serve # can do this as reset
      puts "%4.2f: #{self} receiving service, time_left=#{time_left}" %
        world.clock
    end
  end
end

class Server < RedShift::Component
  state :Waiting, :Serving
  start Waiting
  
  # the client currently being served
  link :client
  
  queue :clients
  
  transition Waiting => Serving do
    wait :clients
    action do
      cs = clients.pop
      case cs
      when RedShift::SimultaneousQueueEntries
        self.client = cs.shift # NOT deterministic--should rank clients
        clients.unpop cs # put the rest back on the head of the queue
      when RedShift::Component
        self.client = cs
      else
        raise "Error!"
      end
    end
  end
  
  transition Serving => Waiting do
    sync :client => :accept
    event :serve => proc {1.0 + rand()}
    action do
      puts "%4.2f: #{self} serving #{client}" % world.clock
      self.client = nil
    end
  end
end

w = RedShift::World.new
s = w.create(Server)
10.times do
  w.create Client do |c|
    c.server = s
  end
end

w.evolve 10.0

