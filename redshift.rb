# Copyright (c) 2001-2, Joel VanderWerf
# Distributed under the Ruby license. See www.ruby-lang.org.

require 'mathn'
require 'cgen/cshadow'

class Object
  def pp arg  # for debugging :)
    p arg; arg
  end
  
  class AssertionFailure < StandardError; end
  def assert(msg=nil,&bl)
    unless bl.call
      if msg
        raise AssertionFailure, msg
      else
        raise AssertionFailure
      end
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

  CLib = CGenerator::Library.new CLibName
  CLib.include '<math.h>'

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
