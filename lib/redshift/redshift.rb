# Copyright (C) 2001-2004, Joel VanderWerf
# Distributed under the Ruby license. See www.ruby-lang.org.

require 'mathn'

# Read all environment variables related to RedShift and store in globals
## see importenv.rb for a way to keep these in sync
ENV.keys.grep(/RedShift/i) do |key|
  val = ENV[key] # make eval safe
  eval "$#{key} = val unless defined? $#{key}"
end

## parse command line args

if $REDSHIFT_DEBUG
  puts "  ----------------------------------------------------------------- "
  puts " |RedShift debugging information enabled by env var REDSHIFT_DEBUG.|"
  puts " |    Please ignore error messages that do not halt the progam.    |"
  puts "  ----------------------------------------------------------------- "
  puts "\n   debug level = #{$REDSHIFT_DEBUG}\n\n" if $REDSHIFT_DEBUG != true
  
  $REDSHIFT_DEBUG = $REDSHIFT_DEBUG.to_i
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

  @library_calls = []
  
  # Defer a block until just after the library ruby code is loaded, but before
  # commit. Necessary for defining inline C functions. Note that a whole
  # require statement could be placed inside the with_library block.
  def RedShift.with_library(&block)
    @library_calls << block
  end

  def RedShift.do_library_calls(library)
    @library_calls.each do |block|
      block[library]
    end
  end

  def RedShift.require_target
    require $REDSHIFT_TARGET
  end

  autoload(:ZenoDebugger, "redshift/mixins/zeno-debugger")

end # module RedShift

case $REDSHIFT_TARGET
when nil, /^c$/i
  $REDSHIFT_TARGET = 'redshift/target/c'
when /spec/i
  $REDSHIFT_TARGET = 'redshift/target/spec'
end

# There could be other things here... YAML, HSIF, Teja, pure ruby reference
# impl. etc. (but procs are a problem for all but ruby)

require 'redshift/syntax'
