# Copyright (c) 2001-2, Joel VanderWerf
# Distributed under the Ruby license. See www.ruby-lang.org.

require 'mathn'
require 'cgen/cshadow'

class Object
  def pp arg  # for debugging :)
    p arg; arg
  end
  
  @@ptime = Time.times
  @@rtime = Time.now.to_f

  def show_times str
    ptime = Time.times
    rtime = Time.now.to_f
    printf "%20s %6.2f %6.2f %6.2f %6.2f %7.3f\n", str,
      ptime.utime - @@ptime.utime, ptime.stime - @@ptime.stime,
      ptime.cutime - @@ptime.cutime, ptime.cstime - @@ptime.cstime,
      rtime - @@rtime
    @@ptime = ptime
    @@rtime = rtime
  end

  class AssertionFailure < StandardError; end
  def assert(test, msg=nil)
    unless test
      if msg
        raise AssertionFailure, msg
      else
        raise AssertionFailure
      end
    end
  end
  
  def debug setting = true, &block
    if block
      begin
        save_setting = $DEBUG
        $DEBUG = setting
        block.call
      ensure
        $DEBUG = save_setting
      end
    else
      $DEBUG = setting
    end
  end
end

module RedShift
  include Math
  
  Infinity = 1.0/0.0

  def run(*args)
    if @@world
      @@world.run(*args)
    else
      raise "No world specified."
    end
  end
  module_function :run
  
  unless defined? CLibName
    CLibName =
      if $0 == "\000PWD"  # irb in ruby 1.6.5 bug
        "irb"
      else
        File.basename($0)
      end
    CLibName[/\.rb$/] = ''
    CLibName[/-/] = '_'
      # other symbols will be caught in CGenerate::Library#initialize.
    CLibName << '_clib'
  end

  class Library < CGenerator::Library
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
      super
    end
  end

  CLib = Library.new CLibName
  CLib.include '<math.h>'
  CLib.purge_source_dir = :delete

#  class Warning < Exception; end
#  
#  # Warn with string str and skipping n stack frames.
#  def warn str, n = 0
#    warning = sprintf "\nWarning: #{str}\n\t#{caller(n).join("\n\t")}\n"
#    #if $DEBUG -- in debug mode, exception is always printed ???
#      raise Warning, warning
#    #else
#    #  $stderr.print warning
#    #end
#  end
#  module_function :warn

end # module RedShift

require 'redshift/component'
require 'redshift/world'
require 'redshift/syntax'
