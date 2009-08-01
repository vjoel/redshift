require 'redshift/event.rb'
require 'redshift/transition.rb'
require 'redshift/flow.rb'
require 'redshift/state.rb'
require 'redshift/meta.rb'
require 'cgen/shadow'

module RedShift

Enter = State.new :Enter, "RedShift"
Exit = State.new :Exit, "RedShift"
Always = Transition.new :Always, nil, [], nil
  
class Component
  include CShadow

  attr_reader :world
  attr_reader :state
  attr_reader :active_transition

  Enter = RedShift::Enter
  Exit = RedShift::Exit

  def initialize(world, &block)

    @world = world
    @active_transition = nil
    
    restore {
      @state = Enter
      defaults
      if block
        instance_eval(&block)
      end
      setup
    }

  end


  def restore
    for s in states
      for e in events s
        e.unexport self
      end
    end
    
    yield if block_given?
    
    arrive
  end
  
  
  def defaults
  end
  
  def setup
  end
  
    
  def step_continuous dt
  
    @dt = dt
  
    for f in flows
      f.update self
    end
    
    for f in flows
      f.eval self
    end
    
  end
  
  
  def step_discrete
  
    dormant = true

    if @active_transition
      dormant = false
      @active_transition.finish self
      unless @state == @active_transition_dest
        depart
        @state = @active_transition_dest
        arrive
      end
      @active_transition = nil
    end

    for t, d in transitions
      if t.enabled? self
        dormant = false
        @active_transition = t
        @active_transition_dest = d
        t.start self
        break
      end
    end
    
    return dormant

  end
  
  
  def arrive
    for f in flows
      f.arrive self, @state
    end
  end 
  
  def depart
    for f in flows
      f.depart self, @state
    end
  end
    
  def discard_singleton_methods
    sm = singleton_methods
    (class <<self; self; end).class_eval {
      for m in sm
        remove_method m.intern
      end
    }
  end
  
  attach({Exit => Exit}, Transition.new :exit, nil, [],
    proc {world.remove self})
  
end # class Component

end # module RedShift
