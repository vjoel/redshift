require "redshift"

include RedShift

class Z < Component
  transition Enter => Enter do
    guard {puts "in guard clause"; true}
    action {puts "in action clause"}
  end
end

class ZWorld < World
  # RedShift::ZenoDebugger already has a useful implementation of report_zeno,
  # but we can augment its non-interactive output by adding an interactive
  # debugging shell.
  include ZenoDebugger
  
  # Try commenting out the action clause in Z. Without the following line,
  # the Zeno debugger will not be able to watch instances of Z. The cost
  # of this line is a recompilation and a small run-time speed hit. Note
  # that only one of these "include" lines is needed.
#  include ZenoDebugger::DetectEmptyTransitions
  
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
    
    z = zeno_watch_list[0]
    IRB.start_session(binding, self)
    
  end
end

world = ZWorld.new

world.zeno_limit = 10
#world.zeno_limit = ZENO_UNLIMITED # don't check for zeno

world.debug_zeno = true
# After zeno_limit steps, RedShift starts calling world.step_zeno

world.debug_zeno_limit = ZENO_UNLIMITED
# The user is in control.

world.create(Z)

world.step 1
