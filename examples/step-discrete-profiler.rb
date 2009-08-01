require 'redshift'

include RedShift

# This example is a simple profiler for measuring time in guard phases and
# proc/reset phases. Finer grained measurements can be done using other hooks.

# See examples/step-discrete-hook.rb for more examples of hook methods.

# Note that ruby's profiler.rb can be used to profile the ruby methods, it just
# doesn't give any results _within_ World#step_discrete.

n_components = 1000
n_seconds = 1000

class ProfilingExample < Component
  continuous :x
  
  def x_less_than_0
    x < 0
  end
  
  def reset_x
    self.x = 2
  end
  
  transition do
#    guard :x_less_than_0  # 36.1 ms
#    guard {x < 0}         # 61.0 ms
    guard "x < 0"         #  3.2 ms

#    action :reset_x       #  1.8 ms
#    action {self.x = 2}   #  4.5 ms
    
    reset :x => 2         #  1.3 ms
  end
  flow { diff "x' = -1" }
end

class ProfilingWorld < World
  attr_accessor :guard_time, :proc_time, :reset_time
  
  def cpu_time
    #Time.now
    Process.times.utime # for short runs, this doesn't have enough granularity
  end
  
  def initialize(*args)
    super
    @guard_time = 0
    @proc_time = 0
    @reset_time = 0
  end
  
  def hook_enter_guard_phase
    @guard_start = cpu_time
  end

  def hook_leave_guard_phase
    t = cpu_time
    @guard_time += t - @guard_start
  end
  
  def hook_enter_action_phase
    @proc_start = cpu_time
  end
  
  def hook_leave_action_phase
    t = cpu_time
    @proc_time += t - @proc_start
  end
  
  def hook_begin_eval_resets(comp)
    @reset_start = cpu_time
  end
  
  def hook_end_eval_resets(comp)
    t = cpu_time
    @reset_time += cpu_time - @reset_start
  end
  
  def hook_begin_parallel_assign
    @reset_start = cpu_time
  end
  
  def hook_end_parallel_assign
    t = cpu_time
    @reset_time += cpu_time - @reset_start
  end
end

w = ProfilingWorld.new
n_components.times do
  w.create(ProfilingExample)
end

w.evolve n_seconds

x = n_components * n_seconds
puts "Times are averages per component, per second of simulation."
printf "Guard time: %10.3f ms\n", (w.guard_time/x)*1_000_000
printf "Proc time:  %10.3f ms\n", (w.proc_time/x)*1_000_000
printf "Reset time: %10.3f ms\n", (w.reset_time/x)*1_000_000
