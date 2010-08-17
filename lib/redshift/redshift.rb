# Copyright (C) 2001-2010, Joel VanderWerf
# Distributed under the Ruby license. See www.ruby-lang.org.

# RedShift has no command line interface, since it is a library. But it does
# let you pass in options with any env var named REDSHIFT_*. The variable
# is accessible as a global $REDSHIFT_*.
#
# Some standard env vars recognized by redshift itself:
#
# REDSHIFT_BUILD_TIMES  : boolean - show times of each build step
# REDSHIFT_CGEN_VERBOSE : boolean - passed on to cgen via $CGEN_VERBOSE
# REDSHIFT_CLIB_NAME    : string  - used as based for dir and .so names
# REDSHIFT_DEBUG        : int     - debug level (false, 0, or empty to disable)
# REDSHIFT_DEBUG_ZENO   : boolean - turn on Zeno debugging in zeno-debugger.rb
# REDSHIFT_MAKE_ARGS    : string  - arguments passed on to make (-j is nice)
# REDSHIFT_SKIP_BUILD   : boolean - just load .so and run program
# REDSHIFT_TARGET       : string  - (future) which kind of build
# REDSHIFT_WORK_DIR     : string  - where to build C lib (default is ./tmp/)

convert_val = proc do |var, val|
  case var
  when /\AREDSHIFT_(?:BUILD_TIMES|CGEN_VERBOSE|DEBUG_ZENO|SKIP_BUILD)\z/
    case val
    when /\A\s*(false|off|nil|0*)\s*\z/i
      false
    else
      true
    end
  when /\AREDSHIFT_DEBUG\z/
    case val
    when /\A\s*(false|off|nil|0*)\s*\z/i
      false
    when /\A\s*(true|on)\s*\z/i
      1
    else
      val.to_i rescue 1
    end
  else
    val
  end
end

ENV.keys.grep(/RedShift/i) do |key|
  next unless /\A[\w]+\z/ =~ key
  val = ENV[key] # make eval safe
  val = convert_val[key, val]
  eval "$#{key} = val unless defined? $#{key}"
end

if $REDSHIFT_DEBUG
  $stderr.puts <<-EOS
   -----------------------------------------------------------------
  |RedShift debugging information enabled by env var REDSHIFT_DEBUG.|
   -----------------------------------------------------------------
   REDSHIFT_DEBUG = #{$REDSHIFT_DEBUG}
  EOS
end

class AssertionFailure < StandardError; end
class Object ## get rid of this?
  def assert(test, *msg)
    raise AssertionFailure, *msg unless test
  end
end

module Math
  Infinity = 1.0/0.0 unless defined? Infinity
end

module RedShift
  include Math
  
  VERSION = '1.3.23'

  Infinity = Math::Infinity

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
  
  # Returns a list of all worlds (instances of RedShift::World and subclasses),
  # or just those descending from +world_class+.
  # Not very efficient, since it uses <tt>ObjectSpace.each_object</tt>, but
  # useful in irb.
  def self.worlds(world_class = World)
    worlds = []
    ObjectSpace.each_object(world_class) {|w| worlds << w}
    worlds
  end

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

  @library_calls = []
  
  # Defer a block until just after the library ruby code is loaded, but before
  # commit. Necessary for defining inline C functions or shadow_attrs. Note that
  # a whole require statement could be placed inside the with_library block.
  def RedShift.with_library(&block) # :yields: library
    @library_calls << block
  end

  def RedShift.do_library_calls
    @library_calls.each do |block|
      block[library]
    end
  end

  def RedShift.require_target
    require $REDSHIFT_TARGET
  end

end # module RedShift

case $REDSHIFT_TARGET
when nil, /^c$/i
  $REDSHIFT_TARGET = 'redshift/target/c'
when /^spec$/i
  $REDSHIFT_TARGET = 'redshift/target/spec'
when /^dot$/i
  $REDSHIFT_TARGET = 'redshift/target/dot'
end

# There could be other things here... Java, YAML, HSIF, Teja, pure ruby
# reference impl. etc. (but procs are a problem for all but ruby)

require 'redshift/syntax'

