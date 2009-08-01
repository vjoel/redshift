module RedShift

#require 'formula.rb'
require 'event.rb'
require 'transition.rb'
require 'flow.rb'
require 'state.rb'
#require 'variable.rb'
#require 'input.rb'


class Component

#  @@states = {Component => [Enter, Exit]}

  Enter = State.new "Enter", nil, nil
  Exit = State.new "Exit", nil, nil
  
	attr_reader :world
	attr_reader :state
	attr_reader :active_transition


	def initialize(world, &block)

		@world = world
    @state = Enter
    @active_transition = nil
    
    set_defaults
		
		if block
			instance_eval(&block)
		end
    
    setup

	end
  
  
  def set_defaults
  end
  
  def setup
  end
  
  
  def step_continuous dt
  
    @dt = dt
  
    for f in @state.flows
      f.update self
    end
    
    for f in @state.flows
     f.eval self
    end
    
  end
  
  
  def step_discrete
  
    dormant = true

    if @active_transition
      dormant = false
      @state = @active_transition.finish self
      @active_transition = nil
    end

    for t in @state.transitions
      if t.enabled? self
        dormant = false
        @active_transition = t
        t.start self
        break
      end
    end
    
    return dormant

  end
		
end # class Component

end # module RedShift
