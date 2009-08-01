module RedShift

class Transition

	attr_reader :from, :to, :guard, :events, :action

	def initialize f, t, g, e, a
		@from, @to, @guard, @events, @action = f, t, g, e, a
	end
	
	def enabled? c
		@guard && c.instance_eval(&@guard)    # make this a Formula to optimize?
	end
	
  def start c
    for e in @events
      e.export c
    end 
  end
  
  def finish c
		@action && c.instance_eval(&@action)
    for e in @events
      e.unexport c
    end 
    return @to
	end

end # class Transition

end # module RedShift
