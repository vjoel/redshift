require 'irb'
require 'irb/completion'

# A shell that runs when the user interrupts the main process.
class IRBShell
  @@irb_setup_done = false
  
  # +args+ are binding, self (both optional)
  def initialize(*args)
    ## maybe set some opts here, as in parse_opts in irb/init.rb?

    unless @@irb_setup_done
      @@irb_setup_done = true

      conf = IRB.conf
      
      if File.directory?("tmp")
        conf[:HISTORY_FILE] = "tmp/.irb_shell_history"
      else
        conf[:HISTORY_FILE] = ".irb_shell_history"
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
          puts "\nType one more ^C to abort, or wait for shell."
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
