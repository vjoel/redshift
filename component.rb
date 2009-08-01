require 'redshift/event.rb'
require 'redshift/transition.rb'
require 'redshift/flow.rb'
require 'redshift/state.rb'
require 'redshift/meta.rb'

module RedShift

Enter = State.new :Enter, "RedShift"
Exit = State.new :Exit, "RedShift"
Always = Transition.new :Always, nil, [], nil
  
class Component

  # see also clib.rb
  
  attr_reader :world
  attr_reader :state
  attr_reader :active_transition
  attr_reader :start_state

  Enter = RedShift::Enter
  Exit = RedShift::Exit

  def initialize(world, &block)

    if $DEBUG
      unless caller[1] =~ /redshift\/world.*`create'\z/ or
             caller[0] =~ /`initialize'\z/
        puts caller[1]; puts
        puts caller.join("\n"); exit
        raise "\nComponents can be created only using " +
              "the create method of a world.\n"
      end
    end

    @world = world
    
    restore {
      @start_state = Enter
      do_defaults
      instance_eval(&block) if block
      do_setup
      raise RuntimeError if @state
        ## remove this eventually? Or add to test_discrete.
      @state = @start_state
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
  
  
  def do_defaults
    type.do_defaults self
  end
  private :do_defaults
  
  def do_setup
    type.do_setup self    ## inline these?
  end
  private :do_setup
  
  def self.do_defaults instance
    superclass.do_defaults instance if superclass.respond_to? :do_defaults
    if @defaults_procs
      for pr in @defaults_procs
        instance.instance_eval(&pr)
      end
    end
  end
  
  def self.do_setup instance
    superclass.do_setup instance if superclass.respond_to? :do_setup
    if @setup_procs
      for pr in @setup_procs
        instance.instance_eval(&pr)
      end
    end
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
    proc {world.remove self; @world = nil})
  
  def inspect data = nil
    n = " #{@name}" if @name
    d = ". #{data}" if data
    "<#{type}#{n}: #{@state.name}#{d}>"
  end
  
end # class Component

end # module RedShift
