require 'cgen/cshadow'

module RedShift

  class CompileAction
    # dest is the include/source file and can be specified by class or string
    ## not used yet
    def initialize action_spec, action_proc, dest = nil
      @action_spec = action_spec; @action_proc = action_proc; @dest = dest
    end
  end

  class Library < CShadow::Library
    @@show_times = $REDSHIFT_BUILD_TIMES

    def update_file f, template
#      template_str = template.to_s
#      file_data = f.gets(nil)
#      if file_data == template_str
#        false
#      else
#        f.rewind
#        f.print template_str
#        true
#      end
      ### check here for unchanged files using the preamble
      ### should compare current redshift version with version that is stored
      ### in preamble
      
      ### exec each compile action
      super
    end
    
    def use_work_dir dir_name
      ## this should be a utility method in cgen or somewhere...
      if File.basename(Dir.pwd) == dir_name
        yield
      else
        begin
          oldpwd = Dir.pwd
          Dir.mkdir dir_name rescue SystemCallError
          Dir.chdir dir_name
          yield
        ensure
          Dir.chdir oldpwd
        end
      end
    end
    
    def commit
      use_work_dir 'tmp' do
        if $REDSHIFT_SKIP_BUILD
          # useful for: turnkey; fast start if no changes; manual lib edits
          @committed = true
          loadlib
        else
          super
        end
      end
      ## freeze some stuff, e.g. TypeData?
      ## can cgen/cshadow freeze some stuff?
    end
  end
  
  def RedShift.library
    return @clib if @clib
    
    unless @clib_name
      @clib_name = ($REDSHIFT_CLIB_NAME || $0).dup
      @clib_name =
        if @clib_name == "\000PWD"  # irb in ruby 1.6.5 bug
          "irb"
        else
          File.basename(@clib_name)
        end
      @clib_name[/\.rb$/] = ''
      @clib_name.gsub!(/-/, '_')
      @clib_name.sub!(/^(?=\d)/, '_')
        # other symbols will be caught in CGenerate::Library#initialize.
      @clib_name << '_clib'
    end

    @clib = Library.new @clib_name
    @clib.purge_source_dir = :delete
    
    if $REDSHIFT_DEBUG
      @clib.include_file.include "<assert.h>" ### should be CompileActions
    else
      @clib.include_file.declare :assert => %{#define assert(cond) 0}
    end

    @clib.include_file.include '<math.h>'
    
    @clib
  end
  
  def RedShift.add_action a_spec, &a_proc
  
  end
  
end
