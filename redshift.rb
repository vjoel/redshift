# Copyright (c) 2001-2, Joel VanderWerf
# Distributed under the Ruby license. See www.ruby-lang.org.

require 'mathn'

## read from .redshiftrc (in site dir, home dir, local dir)

# Read all environment variables related to RedShift and store in globals
ENV.keys.grep(/RedShift/i) do |key|
  eval "$#{key} = #{ENV[key].inspect} unless defined? $#{key}"
end

## parse command line args

if $REDSHIFT_DEBUG
  puts "  ----------------------------------------------------------------- "
  puts " |RedShift debugging information enabled by env var REDSHIFT_DEBUG.|"
  puts " |    Please ignore error messages that do not halt the progam.    |"
  puts "  ----------------------------------------------------------------- "
  puts "\n   debug level = #{$REDSHIFT_DEBUG}\n\n" if $REDSHIFT_DEBUG != true
end

if $REDSHIFT_VERBOSE
  $CGEN_VERBOSE = true
end

class Object
  def pp arg  # for debugging :)
    p arg; arg
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
end

module RedShift
  include Math
  
  Infinity = 1.0/0.0

  def debug setting = true, &block
    if block
      begin
        save_setting = $REDSHIFT_DEBUG
        $REDSHIFT_DEBUG = setting
        block.call
      ensure
        $REDSHIFT_DEBUG = save_setting
      end
    else
      $REDSHIFT_DEBUG = setting
    end
  end

#  def run(*args)
#    if @@world
#      @@world.run(*args)
#    else
#      raise "No world specified."
#    end
#  end
#  module_function :run
  
#  class Warning < Exception; end
#  
#  # Warn with string str and skipping n stack frames.
#  def warn str, n = 0
#    warning = sprintf "\nWarning: #{str}\n\t#{caller(n).join("\n\t")}\n"
#    #if $REDSHIFT_DEBUG -- in debug mode, exception is always printed ???
#      raise Warning, warning
#    #else
#    #  $stderr.print warning
#    #end
#  end
#  module_function :warn

end # module RedShift

require 'redshift/clib.rb'
require 'redshift/component'
require 'redshift/world'
require 'redshift/syntax'
