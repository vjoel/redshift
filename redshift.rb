# Copyright (c) 2001, Joel VanderWerf
# Distributed under the Ruby license. See www.ruby-lang.org.

require 'mathn'

require 'redshift/clib'
require 'redshift/world'
require 'redshift/component'
require 'redshift/syntax'

module RedShift
  include Math

  def run(*args)
    if @@world
      @@world.run(*args)
    else
      raise "No world specified."
    end
  end
  module_function :run
  
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
