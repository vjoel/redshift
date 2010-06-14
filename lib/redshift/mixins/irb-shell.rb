require 'irb'
require 'irb/completion'

class Object
  include IRB::ExtendCommandBundle
  # so that Marshal.dump still works, even when doing ">> irb obj"
end

def IRB.parse_opts
  # Don't touch ARGV, which belongs to the app which called this module.
end

class RedShift::IRBShell
  @@irb_setup_done = false
  
  # +args+ are binding, self (both optional)
  def initialize(*args)
    ## maybe set some opts here, as in parse_opts in irb/init.rb?

    unless @@irb_setup_done
      @@irb_setup_done = true

      conf = IRB.conf
      
      if File.directory?("tmp")
        conf[:HISTORY_FILE] = "tmp/.redshift_irb_shell_history"
      else
        conf[:HISTORY_FILE] = ".redshift_irb_shell_history"
      end

      IRB.setup nil
      
      at_exit do
        IRB.irb_at_exit
      end
    end

    workspace = IRB::WorkSpace.new(*args)

    if conf[:SCRIPT] ## normally, set by parse_opts
      @irb = IRB::Irb.new(workspace, conf[:SCRIPT])
    else
      @irb = IRB::Irb.new(workspace)
    end

    conf[:IRB_RC].call(@irb.context) if conf[:IRB_RC]
    conf[:MAIN_CONTEXT] = @irb.context
  end
  
  def run
    @interrupt_requests = nil

    trap("INT") do
      @irb.signal_handle
    end

    begin
      catch(:IRB_EXIT) do
        @irb.eval_input
      end
    ensure
      install_interrupt_handler
    end
  end
    
  def install_interrupt_handler
    unless @interrupt_requests
      @interrupt_requests = 0
      trap("INT") do
        @interrupt_requests += 1
        if @interrupt_requests == 2
          puts "\nType one more ^C to abort, or wait for RedShift shell."
        elsif @interrupt_requests >= 3
          exit!
        end
      end
    end
  end

  def handle_interrupt after = nil
    if @interrupt_requests && @interrupt_requests > 0
      yield if block_given?
      run
      true
    else
      false
    end
  end
end

# extend a World instance with this (or include in a World subclass)
module RedShift::Shellable
  def shell
    @shell ||= RedShift::IRBShell.new(binding, self)
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
