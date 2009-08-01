module RedShift

class Flow

	attr_reader :setter, :formula
	
	def initialize s, f
		@setter, @formula = s, f
	end
	
end # class Flow


class AlgebraicFlow < Flow

	def update c, dt
    result = @formula.feval c
  	c.send @setter, result
	end
	
end # class AlgebraicFlow


class EulerDifferentialFlow < Flow

	def update c, dt
		f = @formula.feval c
		c.send @setter, f * dt
	end
	
end # class EulerDifferentialFlow

end # module RedShift
