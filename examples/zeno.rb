require "redshift"

include RedShift

class Z < Component
  state :A, :B
  start A
  transition A => B, B => A do
    guard {puts "in guard clause: #{self.inspect}"; true}
    action {puts "in action clause: #{self.inspect}"}
  end
end

class ZWorld < World
  # RedShift::ZenoDebugger already has a useful implementation of report_zeno,
  # but we can augment its non-interactive output by adding an interactive
  # debugging shell.
  include ZenoDebugger
  
  def report_zeno
    super # the normal zeno output
    
    unless @zeno_shell_started
      require 'irb-shell'
      puts
      puts "Zeno debugger shell"
      puts "^D to continue to next zeno step (^Z and Return on Windows)"
      puts "'exit' to exit"
      puts "Variable 'z' has the suspect object."
      puts
      @zeno_shell_started = true
    end
    
    z = curr_T[0] ###zeno_watch_list[0]
    IRB.start_session(binding, self)
    
  end
end

world = ZWorld.new

world.zeno_limit = 10
#world.zeno_limit = ZENO_UNLIMITED # don't check for zeno

world.debug_zeno = true
# After zeno_limit steps, RedShift starts calling world.step_zeno

world.debug_zeno_limit = ZENO_UNLIMITED
# The user is in control for as long as the user wants to be.

world.create(Z)

world.step 1
