require 'redshift/util/irb-shell'

class Object
  include IRB::ExtendCommandBundle
  # so that Marshal.dump still works, even when doing ">> irb obj"
end

def IRB.parse_opts
  # Don't touch ARGV, which belongs to the app which called this module.
end

# extend a World instance with this (or include in a World subclass)
module RedShift::Shell
  def shell
    @shell ||= IRBShell.new(binding, self)
  end
  
  def run(*)
    shell.install_interrupt_handler
    super
  end

  def step(*)
    super do
      yield self if block_given?
      if shell.handle_interrupt {before_shell}
        after_shell
        return
      end
    end
  end
  
  # Override to complete some action before dropping into shell.
  def before_shell
  end
  
  # Override to complete some action after leaving shell.
  def after_shell
  end
  
  # Typically, call this in a rescue clause, if you to let the user
  # examine state and possibly continue:
  #
  #   rescue ... => e
  #     require 'redshift/mixins/irb-shell'
  #     world.extend RedShift::IRBShell
  #     world.recoverable_error e, "Assertion failure", e.backtrace
  #
  def recoverable_error e, msg = "Error", bt = []
    puts "#{msg} at time #{clock}"
    puts "From " + bt[0..2].join("\n     ") unless bt.empty
    puts "     ..." if bt.length > 3
    shell.run
  end

private
  def q
    exit
  end

  ## commands:
  ##  step [n] {block}
  ##  step_until/while
  ##  continue -- safer than ^D, does step_discrete in case of changes
  ##  step_continuous
  ##  step_discrete [n]
  ##  break [class/component/transition/comp.event/condition]
  ##    until step_until, stops inside step_discrete
  ##  clear
  ##
  ## customize prompt
end
