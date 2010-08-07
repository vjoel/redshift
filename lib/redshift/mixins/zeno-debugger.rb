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
    attr_accessor :zeno_output

    # Can be used to see which components are causing trouble. Ny default,
    # the output covers all compontents taking transitions. However, you
    # can use this attr to focus more narrowly.
    attr_accessor :zeno_watch_list
    
    # How many zeno steps before the debugger gives up. Set to ZENO_UNLIMITED to
    # debug indefinitely, e.g., for interactive mode. By default, equal to 3
    # times world.zeno_limit, so that batch runs will terminate.
    attr_accessor :debug_zeno_limit
    
    def initialize
      @debug_zeno       ||= $REDSHIFT_DEBUG_ZENO ## why ||= ?
      @zeno_output      ||= $stderr
      super
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
         (debug_zeno_limit == RedShift::ZENO_UNLIMITED or
          zeno_counter < debug_zeno_limit)
        report_zeno if zeno_counter >= 2*zeno_limit
      else
        super
      end
    end
    
    HEADER = '-'*10 + " Zeno step: %d; Components: %d; Active: %d " + '-'*10 + "\n"
    
    # Reports to zeno_output the list of active components.
    def report_zeno
      f = zeno_output
      active = zeno_watch_list || curr_T

      f << HEADER % [zeno_counter, components.size, curr_T.size]
      f << '  ' + active.map{|c|c.inspect}.join("\n  ") + "\n"
    end
  end
end
