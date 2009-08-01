class RedShift::World

  # Include this module in a World class. See example in examples/zeno.rb. Has a
  # very small performance cost, so don't use it in production runs. Note that,
  # even without ZenoDebugger, RedShift will still detect zeno problems by
  # raising a ZenoError when world.zeno_counter > world.zeno_limit, if
  # zeno_limit >= 0.
  #
  # ZenoDebugger is compatible with other kinds of debuggers.

  module ZenoDebugger

    # Can be used to turn on and off this module, set to $REDSHIFT_DEBUG_ZENO by
    # default.
    attr_accessor :debug_zeno

    # Zeno output goes to this object, $stderr by default, using #<<.
    attr_accessor :zeno_io

    # Can be used to see which components are causing trouble.
    attr_accessor :zeno_watch_list
    
    # How many zeno steps before the debugger gives up. Set to ZENO_UNLIMITED to
    # debug indefinitely, e.g., for interactive mode. By default, equal to 3
    # times world.zeno_limit, so that batch runs will terminate.
    attr_accessor :debug_zeno_limit
    
    def initialize
      @debug_zeno       ||= $REDSHIFT_DEBUG_ZENO
      @zeno_io          ||= $stderr
      @zeno_watch_list  ||= []
      
      super
    end

    def step_discrete
      super
      zeno_watch_list.clear
    end

    # This method is called for each discrete step after the zeno_limit has been
    # exceeded. This implementation is just one possibility, useful for
    # debugging. One other useful behavior might be to shuffle guards in the
    # active components.
    #
    # In this implementation, when the zeno_counter exceeds zeno_limit, we start
    # to add active objects to the zeno_watch_list. When the counter exceeds
    # two times the zeno_limit, we call report_zeno. When the counter exceeds
    # three times the zeno_limit, we fall back to the super definition of
    # step_zeno, which is typically to raise a ZenoError.
    
    def step_zeno
      self.debug_zeno_limit ||= zeno_limit*3
      if debug_zeno and
         (debug_zeno_limit == ZENO_UNLIMITED or zeno_counter < debug_zeno_limit)
        self.zeno_watch_list |= select {|c| c.trans}
        report_zeno if zeno_counter >= 2*zeno_limit

      else
        super
      end
    end
    
    # Reports to zeno_io the list of active components. (Unless you are
    # using ZenoDebugger_DetectEmptyTransitions, you will not see active
    # components that take only transitions with no phases other than
    # guards
    
    def report_zeno
      f = zeno_io
      
      ag = active_G

      f << '-'*30 + " Zeno step: #{zeno_counter} " + '-'*30 + "\n"
      f << "    active component counts: P: #{curr_P.size}," +
             " E: #{curr_E.size}, R: #{curr_R.size}, G: #{ag.size}" + "\n"
      f << 'P:  ' + curr_P.map{|c|c.inspect}.join("\n    ") + "\n"
      f << 'E:  ' + curr_E.map{|c|c.inspect}.join("\n    ") + "\n"
      f << 'R:  ' + curr_R.map{|c|c.inspect}.join("\n    ") + "\n"
      f << 'G:  ' + ag.map{|c|c.inspect}.join("\n    ") + "\n"
    end
    
    # Returns list of components that appear to be active and in Guard phase.
    def active_G
      active_G = zeno_watch_list & curr_G
    end
    
  end

  # Include this module in your World class if you want the Zeno debugger to
  # detect components that take only transitions with no phases other than
  # guards. Detected components will be added to the zeno_watch_list.
  #
  # Including this module may force a brief recompilation, which requires that a
  # C compiler be installed.
  #
  # This module automatically includes ZenoDebugger, as well.

  module ZenoDebugger_DetectEmptyTransitions
    include ZenoDebugger
    
    def hook_start_transition(comp, trans, dest)
      super if defined?(super)
      self.zeno_watch_list |= [comp]
    end
  end
end
