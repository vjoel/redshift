# efficient and convenient way to manage timed events

require 'redshift'

class Scheduler < RedShift::Component
  queue :request_queue
  continuous :time
  constant :next_wakeup_time
  
  default do
    @schedule = [] ## could use rbtree for efficient sorted list
    self.next_wakeup_time = RedShift::Infinity
  end
  
  flow do
    diff " time' = 1 "
  end
  
  class Request
    include Comparable

    attr_accessor :time, :queue, :message

    def <=>(other)
      self.time <=> other.time
    end

    # Scheduled request: at given +time+, send +message+ to +queue+.
    def initialize time, queue, message
      @time, @queue, @message = time, queue, message
    end
  end
  
  EPSILON = 1E-12 # float fuzziness, if timestep is 0.1, for example
  
  # Schedule the sending of +message+ to +queue+, after +delta_t+ elapses.
  # Returns the request object for use with unschedule
  def schedule_message delta_t, queue, message
    req = Request.new(time + delta_t - EPSILON, queue, message)
    request_queue << req
    req
  end
  
  def unschedule req
    @schedule.delete req
  end
  
  transition do
    wait :request_queue
    action do
      case reqs = request_queue.pop
      when RedShift::SimultaneousQueueEntries
        reqs.each do |req|
          @schedule << req
        end
      else
        @schedule << reqs
      end
    
      @schedule.sort!
      self.next_wakeup_time = @schedule.first.time
    end
  end
  
  transition do
    guard "time >= next_wakeup_time"
    action do
      while (req = @schedule.first and req.time <= time)
        @schedule.shift
        req.queue << req.message
      end
      
      if (req = @schedule.first)
        self.next_wakeup_time = req.time
      else
        self.next_wakeup_time = RedShift::Infinity
      end
    end
  end
end

class Client < RedShift::Component
  queue :wakeup
  link :scheduler
  state :Waiting
  constant :delay => 4.2
  
  transition Enter => Waiting do
    action do
      puts "scheduling message at #{world.clock} sec to run after #{delay} sec"
      scheduler.schedule_message delay, wakeup, "Time to wake up, snoozebrain!"
    end
  end
  
  transition Waiting => Exit do
    wait :wakeup
    action do
      msg = wakeup.pop
      puts "wake up received at #{world.clock} sec: #{msg.inspect}"
    end
  end
end

w = RedShift::World.new
s = w.create Scheduler
c = w.create Client
c.scheduler = s

w.evolve 10
