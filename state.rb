module RedShift

class State

	attr_reader :name
	
	def initialize n
		@name = n || "[State #{id}]".intern
	end

end # class State

end # module RedShift
