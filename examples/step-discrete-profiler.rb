require 'redshift'

include RedShift

## express profiler as mixin, and as executable

class ProfilingExample < Component
  continuous :x
  transition do
#    guard {x < 0}
    guard "x < 0"
#    action {self.x = 2}
    reset :x => 2
  end
  flow { diff "x' = -1" }
end

class ProfilingWorld < World
  attr_accessor :guard_time, :proc_time
  def initialize(*args)
    super
    @guard_time = 0
    @proc_time = 0
    @guard_start = nil
    @proc_start = nil
  end
  
  def hook_enter_guard_phase(dstep)
    @guard_start = Time.now
  end
  
  def hook_leave_guard_phase(dstep)
    @guard_time += Time.now - @guard_start
  end
  
  def hook_enter_proc_phase(dstep)
    @proc_start = Time.now
  end
  
  def hook_leave_proc_phase(dstep)
    @proc_time += Time.now - @proc_start
  end
end

w = ProfilingWorld.new
c = w.create(ProfilingExample)

w.age 100
p w.guard_time
p w.proc_time
