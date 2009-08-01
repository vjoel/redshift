module RedShift

class State

	attr_reader :name, :flows, :transitions
	
	def initialize n, f, t
		@name, @flows, @transitions = n, f, t
	end

end # class State

end # module RedShift
