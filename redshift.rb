# Copyright (c) 2001, Joel VanderWerf
# Distributed under the Ruby license. See www.ruby-lang.org.

require 'redshift/clib'
require 'redshift/world'
require 'redshift/component'
require 'redshift/syntax'

module RedShift

  def run(*args)
    if @@world
      @@world.run(*args)
    else
      raise "No world specified."
    end
  end
  module_function :run

  def warn str
    $stderr.printf "Warning: #{str}\n\tFile %s, line %d\n", __FILE__, __LINE__
  end
  module_function :warn

end # module RedShift
