$CGEN_VERBOSE = $REDSHIFT_CGEN_VERBOSE ## ugh.

require 'ftools'
require 'cgen/cshadow'

module RedShift

  def RedShift.library
    @clib ||= Library.new($REDSHIFT_CLIB_NAME)
  end
  
  class Library < CShadow::Library
    def initialize(*args)
      super
      
      self.purge_source_dir = :delete
      self.show_times_flag = $REDSHIFT_BUILD_TIMES

      if $REDSHIFT_DEBUG
        include_file.include "<assert.h>"
        ## better to use something that raises a ruby exception
      else
        include_file.declare :assert => %{#define assert(cond) 0}
      end

      include_file.include '<math.h>'

      define_redshift_globals
    end
    
    def commit
      return if committed?
      precommit

      ## this makes it a little trickier to use gdb
      use_work_dir $REDSHIFT_WORK_DIR do
        # $REDSHIFT_SKIP_BUILD is normally handled in redshift/target/c.rb.
        # useful for: turnkey; fast start if no changes; manual lib edits
        super(!$REDSHIFT_SKIP_BUILD)
      end
      ## freeze metadata in comp classes?
      ## can cgen/cshadow freeze some stuff?
    end
    
    # Return list of all subclasses of Component (including Component).
    def component_classes
      return @component_classes if @component_classes

      cc = Library.sort_class_tree(Component.subclasses)
      @component_classes = cc if committed?
        
      return cc
    end
    
    # Operate on Component class specifications gathered by meta.rb,
    # and stored in the component classes.
    def precommit
      ## no need to precommit Component? Other abstract classes?
      component_classes.each {|cl| cl.precommit}
      ## optimization?
      ## check if changed
    end

    def define_redshift_globals
      ## need to protect these globals somehow
      ## need to insulate different world's use of them from each other
      ## currently, not threadsafe, unless each discrete/continuous step
      ## is protected with a mutex.

      # global rk_level, time_step (not used outside continuous update)
      declare :rk_level   => "long    rk_level"
      declare :time_step  => "double  time_step"
      include_file.declare :rk_level   => "extern long     rk_level"
      include_file.declare :time_step  => "extern double   time_step"

      # global d_tick (used only outside continuous update)
      declare :d_tick => "long d_tick"
      include_file.declare :d_tick => "extern long d_tick"

      setup :rk_level => "rk_level = 0"
      setup :d_tick   => "d_tick   = 1"  # alg flows need to be recalculated
    end

  end
  
end
