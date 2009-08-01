module RedShift

class Transition

  attr_reader :name, :guard, :events, :action

  def initialize n, g, e, a
    @name, @guard, @events, @action = n, g, e, a
    @name ||= "[transition #{id}]".intern
  end
  
  def enabled? c
    @guard == nil || c.instance_eval(&@guard)
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
  end

end # class Transition

end # module RedShift
