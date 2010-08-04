$CGEN_VERBOSE = $REDSHIFT_CGEN_VERBOSE ## ugh.

require 'cgen/cshadow'

module RedShift
  def RedShift.library
    @clib ||= Library.new($REDSHIFT_CLIB_NAME)
  end
  
  class Library < CShadow::Library
    def initialize(*args)
      super
      
      self.purge_source_dir = :delete
      
      self.show_times_flag =
        case $REDSHIFT_BUILD_TIMES
        when nil, false, /\A(false|0*)\z/i
          false
        else
          true
        end

      if $REDSHIFT_DEBUG
        include_file.include "<assert.h>"
        ## better to use something that raises a ruby exception
      else
        include_file.declare :assert => %{#define assert(cond) 0}
      end

      include_file.include '<math.h>'
    end
    
    # Call this to link with external libraries. See examples/external-lib.rb.
    def link_with *libs
      (@link_libs ||= []) << libs
    end
    
    def declare_external_constant *vars
      @external_constants ||= {}
      vars.each do |var|
        @external_constants[var.to_s] = true
      end
    end
    
    def external_constant? var
      @external_constants and @external_constants.key?(var.to_s)
    end
    
    def extconf
      super do |lines|
        if @link_libs
          libstr = " " + @link_libs.flatten.join(" ")
          lines << %{$LOCAL_LIBS << "#{libstr}"}
        end
      end
    end
    
    def make arg=nil
      super [$REDSHIFT_MAKE_ARGS, arg].join(" ")
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
      component_classes.each {|cl| cl.generate_wrappers}
      ## optimization?
      ## check if changed
    end
  end
end
