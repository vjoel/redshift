# Copyright (c) 2001, Joel VanderWerf
# Distributed under the Ruby license. See www.ruby-lang.org.

require 'world.rb'
require 'component.rb'

module RedShift

def run(*args)
	if @@world
		@@world.run(*args)
	else
		raise "No world specified."
	end
end

end # module RedShift
