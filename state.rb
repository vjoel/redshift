module RedShift

class State

	attr_reader :flow, :transition
	
	def initialize f, t
		@flow, @transition = f, t
	end

end # class State

end # module RedShift
