module RedShift

class InputSpec

	def initialize(name, init_value = nil)
	
		@name = name
		@init_value = init_value
	
	end
	
	attr_reader :name, :init_value

end # class InputSpec


class InputSpecSet < Hash

	def names
		keys
	end

end # class InputSpecSet


end # module RedShift
