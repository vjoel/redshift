module RedShift

  # Include this module in a World class. See example in examples/zeno.rb. Has a
  # small performance cost, so don't use it in production runs. Note that, even
  # without ZenoDebugger, RedShift will still detect zeno problems by raising a
  # ZenoError when world.zeno_counter > world.zeno_limit, if zeno_limit >= 0.

  module ZenoDebugger

    # Can be used to turn on and off this module, set to $REDSHIFT_DEBUG_ZENO by
    # default.
    attr_accessor :debug_zeno

    # Zeno output goes to this writable IO, $stderr by default.
    attr_accessor :zeno_io

    # Can be used to see which components are causing trouble.
    attr_accessor :zeno_watch_list
    
    # How many zeno steps before the debugger gives up. Set to Infinity to debug
    # indefinitely, e.g., for interactive mode.
    attr_accessor :debug_zeno_limit

    def initialize
      @debug_zeno = $REDSHIFT_DEBUG_ZENO
      @zeno_io = $stderr
      @zeno_watch_list = []
      
      super
    end

    def step_discrete
      super
      zeno_watch_list.clear
    end

    # This method is called for each discrete step after the zeno_limit has been
    # exceeded. This implementation is just one possibility, useful for
    # debugging. One useful behavior might be to shuffle guards in the active
    # components.
    def step_zeno
      self.debug_zeno_limit ||= zeno_limit*3
      if debug_zeno and zeno_counter < debug_zeno_limit
        self.zeno_watch_list |= select {|c| c.trans}
        report_zeno if zeno_counter >= 2*zeno_limit

      else
        super # raise ZenoError
      end
    end
    
    ## bug: doesn't detect an active component that has no phases (other
    ## than the guard, if any) in its transition. This could be fixed by
    ## using fine-grained instrumentation of setp_discrete.
    def report_zeno
      f = zeno_io

      active_G = zeno_watch_list & curr_G
      f.puts '-'*30 + " Zeno step: #{zeno_counter} " + '-'*30
      f.puts "    active component counts: P: #{curr_P.size}," +
             " E: #{curr_E.size}, R: #{curr_R.size}, G: #{active_G.size}"
      f.puts 'P:  ' + curr_P.map{|c|c.inspect}.join("\n    ")
      f.puts 'E:  ' + curr_E.map{|c|c.inspect}.join("\n    ")
      f.puts 'R:  ' + curr_R.map{|c|c.inspect}.join("\n    ")
      f.puts 'G:  ' + active_G.map{|c|c.inspect}.join("\n    ")
    end

  end

end
