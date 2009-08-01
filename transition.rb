module RedShift

class Transition

	attr_reader :from, :to, :guard, :event, :action

	def initialize f, t, g, e, a
		@from, @to, @guard, @event, @action = f, t, g, e, a
		# convert e from array to hash format
	end
	
	def enabled
		c.instance_eval &guard
		# this could be compiled...
	end
	
	def take c
		c.instance_eval &action
	end

end # class Transition

end # module RedShift
