# Show some of the hooks that can be dynamically compiled into a redshift
# simulation. All you have to do is define the following methods in the
# World class or your own subclass, and the hooks will be called when
# the world runs. Some hooks take arguments, such the component being
# handled. In all cases, if you do not define the hook, the code to call it
# is not generated, so there is no cost.
#
# grep -o -P 'hook_\w+' world-gen.rb | sort | uniq
#
#  hook_begin
#  hook_begin_eval_events
#  hook_begin_eval_resets
#  hook_begin_parallel_assign
#  hook_begin_step
#  hook_call_action
#  hook_can_sync
#  hook_end
#  hook_end_eval_events
#  hook_end_eval_resets
#  hook_end_parallel_assign
#  hook_end_step
#  hook_enter_action_phase
#  hook_enter_eval_phase
#  hook_enter_guard_phase
#  hook_enter_post_phase
#  hook_enter_sync_phase
#  hook_eval_event
#  hook_eval_guard
#  hook_eval_port_connect
#  hook_eval_reset_constant
#  hook_eval_reset_continuous
#  hook_eval_reset_link
#  hook_export_events
#  hook_finish_transition
#  hook_leave_action_phase
#  hook_leave_eval_phase
#  hook_leave_guard_phase
#  hook_leave_post_phase
#  hook_leave_sync_phase
#  hook_pat
#  hook_remove_comp
#  hook_start_transition
#  hook_sync_step

require 'redshift'

include RedShift

class Example < Component
  state :S
  continuous :x, :y

  flow S do
    diff "x' = 1"
  end

  transition Enter => S do
    reset :x => 0
  end

  transition S => S do
    guard "x > 1"
    reset :x => 0, :y => "y+1"
  end
end

# Can do this in World itself, or in a subclass
class ExampleWorld < World
  def hook_begin
    puts "world step #{step_count}"
    puts "  hook_begin"
  end
  
  def hook_end
    puts "  hook_end #{discrete_step}"
  end
  
  def hook_begin_step
    puts "    hook_begin_step #{discrete_step}"
  end
  
  def hook_end_step
    puts "    hook_end_step #{discrete_step}"
  end
  
  def hook_enter_guard_phase
    puts "    hook_enter_guard_phase #{discrete_step}"
  end
  
  def hook_leave_guard_phase
    puts "    hook_leave_guard_phase #{discrete_step}"
  end
  
  def hook_enter_action_phase
    puts "    hook_enter_proc_phase #{discrete_step}"
  end
  
  def hook_leave_action_phase
    puts "    hook_leave_proc_phase #{discrete_step}"
  end

  def hook_begin_parallel_assign
    puts "    hook_begin_parallel_assign #{discrete_step}"
  end
  
  def hook_end_parallel_assign
    puts "    hook_end_parallel_assign #{discrete_step}"
  end
  
  def hook_start_transition(comp, trans, dest)
    puts "      hook_start_transition:"
    puts "        %p" % [[comp, trans, dest]]
  end

  def hook_finish_transition(comp, trans, dest)
    puts "      hook_finish_transition:"
    puts "        %p" % [[comp, trans.class, dest]]
  end
  
  def hook_eval_guard(comp, guard, enabled, trans, dest)
    puts "      hook_eval_guard:"
    puts "        %p" % [[comp, guard, enabled, trans, dest]]
  end
  
  def hook_enter_sync_phase
    puts "    hook_enter_sync_phase #{discrete_step}"
  end
  
  def hook_leave_sync_phase
    puts "    hook_leave_sync_phase #{discrete_step}"
  end
  
  def hook_sync_step curr_S, changed
    puts "      hook_sync_step, changed = #{changed.inspect}:"
    puts "        %p" % [curr_S]
  end
  
  def hook_can_sync comp, can_sync
    puts "        hook_can_sync, can_sync = #{can_sync.inspect}:"
    puts "          %p" % [comp]
  end

  def hook_call_action(comp, pr)
    puts "      hook_call_proc:"
    puts "        %p" % [[comp, pr]]
    file, lineno = pr.inspect.scan(/@(.*):(\d+)>\Z/)[0] ## better way?
    lineno = lineno.to_i - 1
    puts extract_code_block(file, lineno)
  rescue Errno::ENOENT
    puts "        can't open file #{File.expand_path(file)}"
  end
  
  ## put in a lib somewhere--as inspect methods for proc subclasses?
  def extract_code_block(file, lineno)
    result = ""
    File.open(file) do |f|
      lineno.times {f.gets}
      line = f.gets
      result << line
      
      first_indent = (line =~ /\S/)
      loop do
        str = f.gets
        indent = (str =~ /\S/)
        if indent > first_indent or
           (indent == first_indent and str =~ /\A\s*(\}|end)/)
          result << str 
        end
        break if indent <= first_indent
      end
    end
    result
  end

  def hook_eval_event(comp, event, event_value)
    puts "      hook_export_event:"
    puts "        %p" % [[comp, event, event_value]]
  end
  
  def hook_eval_reset_constant(comp, var, val)
    puts "      reset constant #{var} to #{val} in #{comp}"
  end
  
  def hook_eval_reset_continuous(comp, var, val)
    puts "      reset continuous #{var.name} to #{val} in #{comp}"
  end
  
  def hook_eval_reset_link(comp, var, val)
    puts "      reset link #{var} to #{val} in #{comp}"
  end
  
  def hook_not_a_known_hook
    # This will generate a warning, since it is not a known hook.
  end
end

world = ExampleWorld.new
comp = world.create(Example)

world.evolve 1.2
p world
