# Copyright (c) 2001, Joel VanderWerf
# Distributed under the Ruby license. See www.ruby-lang.org.

require 'redshift/world.rb'
require 'redshift/component.rb'
require 'redshift/syntax.rb'

module RedShift

def run(*args)
	if @@world
		@@world.run(*args)
	else
		raise "No world specified."
	end
end

def warn str
  $stderr.printf "Warning: #{str}\n\tFile %s, line %d\n", __FILE__, __LINE__
end

end # module RedShift
