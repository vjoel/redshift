module RedShift

def run *args
	if @@world
		@@world.run *args
	else
		raise "No world specified."
	end
end

require 'world.rb'
require 'component.rb'

end # module RedShift
