module RedShift

class Flow

	attr_reader :state, :setter, :derivative
	
	def initialize st, s, d
		@state, @setter, @derivative = st, s, d
	end

	def update component, time_step
		# for now, use a very simple integrator
	
		v_dot = @derivative.call
		delta = v_dot * time_step
		component.send @setter, delta
	
	end
	
end # class Flow

end # module RedShift
