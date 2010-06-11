require 'irb'
require 'irb/completion'
require 'irb/cmd/load'

#===== for recent versions only =====
###module IRB
###  class Irb
###    def initialize(workspace = nil, input_method = nil)
###      @context = Context.new(self, workspace, input_method)
###      #@context.main.extend ExtendCommandBundle
###      @signal_status = :IN_IRB
###
###      @scanner = RubyLex.new
###      @scanner.exception_on_syntax_error = false
###    end
###  end
###end

class Object
  include IRB::ExtendCommandBundle # so that Marshal.dump works
end
#======================================

def IRB.parse_opts
  # Don't touch ARGV, which belongs to the app which called this module.
end

# include this into World or a World subclass, or extend a World instance
module RedShift::IRBShell
  include IRB::ExtendCommand ## to avoid adding singleton methods
  $irb_setup = false

  def start_irb_shell(*args)
    unless $irb_setup
      IRB.setup nil
      ## maybe set some opts here, as in parse_opts in irb/init.rb?
      $irb_setup = true
    end
    
    workspace = IRB::WorkSpace.new(*args)
    irb_conf = IRB.instance_variable_get(:@CONF) ## ?

    if irb_conf[:SCRIPT] ## normally, set by parse_opts
      @irb = IRB::Irb.new(workspace, irb_conf[:SCRIPT])
    else
      @irb = IRB::Irb.new(workspace)
    end

    irb_conf[:IRB_RC].call(@irb.context) if irb_conf[:IRB_RC]
    irb_conf[:MAIN_CONTEXT] = @irb.context
    @irb.context.eval_history = IRB.conf[:EVAL_HISTORY] if IRB.conf[:EVAL_HISTORY]
    ##@irb.context.save_history = IRB.conf[:SAVE_HISTORY] if IRB.conf[:SAVE_HISTORY]

    trap("INT") do
      @irb.signal_handle
    end

    IRB.custom_configuration if defined?(IRB.custom_configuration)

    catch(:IRB_EXIT) do
      @irb.eval_input
    end
    print "\n"
    
    set_interrupt_handler
  end

  def set_interrupt_handler
    trap("INT") do
      @interrupt_requests ||= 0
      @interrupt_requests += 1
      if @interrupt_requests == 2
        puts "\nType one more ^C to abort, or wait for RedShift shell."
      elsif @interrupt_requests >= 3
        exit!
      end
    end
  end

  def handle_interrupt w
    if @interrupt_requests
      w.shell
      @interrupt_requests = nil
    end
  end
  
  def clean_binding
    binding
  end

  def shell
    @binding ||= clean_binding # a blank, but persistent binding
    start_irb_shell(@binding, self)
  end

  def step(*)
    super do
      yield self if block_given?
      handle_interrupt self if @interrupt_requests
    end
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
    puts "From " + bt[0..2].join("\n     ")
    puts "     ..." if bt.length > 3
    shell
  end

private
  def q
    exit!
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
  ##  simple plotting environment, to simplify the stuff below
  ##
  ## Store history separately
  ##
  ## customize prompt
end
