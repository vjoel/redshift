require 'redshift'

include RedShift

# This example is a simple profiler for measuring time in guard phases and
# proc/reset phases. Finer grained measurements can be done using other hooks.

# See examples/step-discrete-hook.rb for more examples of hook methods.

# Note that ruby's profiler.rb can be used to profile the ruby methods, it just
# doesn't give any results _within_ World#step_discrete.

n_components = 100
n_seconds = 100
$use_slow_guard = true

class ProfilingExample < Component
  continuous :x
  transition do

    if $use_slow_guard
      guard {x < 0}       # 95.2 ms
    else
      guard "x < 0"       #  3.2 ms
    end

    action {self.x = 2}   #  5.8 ms
    reset :x => 2         #  0.3 ms
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
  
  def hook_enter_proc_phase
    @proc_start = cpu_time
  end
  
  def hook_leave_proc_phase
    t = cpu_time
    @proc_time += t - @proc_start
  end
  
  def hook_enter_reset_phase
    @reset_start = cpu_time
  end
  
  def hook_leave_reset_phase
    t = cpu_time
    @reset_time += cpu_time - @reset_start
  end
end

w = ProfilingWorld.new
n_components.times do
  w.create(ProfilingExample)
end

w.age n_seconds

x = n_components * n_seconds
puts "Times are averages per component, per second of simulation."
printf "Guard time: %10.3f ms\n", (w.guard_time/x)*1_000_000
printf "Proc time:  %10.3f ms\n", (w.proc_time/x)*1_000_000
printf "Reset time: %10.3f ms\n", (w.reset_time/x)*1_000_000
