module RedShift

require 'event.rb'
require 'transition.rb'
require 'flow.rb'
require 'state.rb'


Enter = State.new :Enter
Exit = State.new :Exit
  
class Component

  attr_reader :world
  attr_reader :state
  attr_reader :active_transition

  @@flows = {}
  @@transitions = {}

  @@cached_flows = {}
  @@cached_transitions = {}
  
  @@cached_states = {}
  @@cached_events = {}


  def initialize(world, &block)

    @world = world
    @active_transition = nil
    
    each_state do |s|
      each_event s do |e|
        e.unexport self
      end
    end
    
    set_defaults
    
    if block
      instance_eval(&block)
    end
    
    setup

  end
  
  
  def set_defaults
    @state = Enter
  end
  
  def setup
  end
  
  
  def Component.attach states, features
  
    if features.type != Array
      features = [features]
    end
    
    case states
      
      when State
        attach_flows [states], features
      
      when Array
        attach_flows states, features
      
      when Hash
        attach_transitions states, features
      
      else
        p states
        raise "bad state list"
    end
    
  end
  

  def Component.attach_flows states, new_flows
    flows = @@flows[self] ||= {}
    
    for state in states
      flows[state] ||= {}
      
      for f in new_flows
        flows[state][f.var] = f
        f.attach self
      end
      
      for cl, in @@flows
        if cl <= self
          if @@cached_flows[cl]
            @@cached_flows[cl][state] = nil
          end
          @@cached_states[cl] = nil
        end
      end
      
    end
    
  end
  
  
  def Component.attach_transitions states, new_transitions
    transitions = @@transitions[self] ||= {}
    
    for src, dest in states
      transitions[src] ||= {}
      
      for t in new_transitions
        transitions[src][t.name] = [t, dest]
      end
      
      for cl, in @@transitions
        if cl <= self
          if @@cached_transitions[cl]
            @@cached_transitions[cl][src] = nil
          end
          @@cached_states[cl] = nil
          @@cached_events[cl] = nil
        end
      end
      
    end
    
  end
  
  
  def Component.cache_flows cl, state
    if @@cached_flows[cl] and
       @@cached_flows[cl][state]
      return @@cached_flows[cl][state]
    end
    
    if cl == Component
      flows = {}
    else
      flows = cache_flows(cl.superclass, state).dup
    end
    
    if @@flows[cl] and @@flows[cl][state]
      flows.update @@flows[cl][state]
    end
    
    (@@cached_flows[cl] ||= {})[state] = flows
  end
  
  
  def Component.cache_transitions cl, state
    if @@cached_transitions[cl] and
       @@cached_transitions[cl][state]
      return @@cached_transitions[cl][state]
    end
    
    if cl == Component
      transitions = {}
    else
      transitions = cache_transitions(cl.superclass, state).dup
    end
    
    if @@transitions[cl] and @@transitions[cl][state]
      transitions.update @@transitions[cl][state]
    end
    
    (@@cached_transitions[cl] ||= {})[state] = transitions
  end
  
  
  def each_flow state = @state
    cl = type
    Component.cache_flows cl, state
    @@cached_flows[cl][state].each_value
  end
  
  
  def each_transition state = @state
    cl = type
    Component.cache_transitions cl, state
    @@cached_transitions[cl][state].each_value
  end
  
  
  def Component.cache_states cl
    if @@cached_states[cl]
      return @@cached_states[cl]
    end
    
    if cl == Component
      states = []
    else
      states = cache_states(cl.superclass).dup
    end
    
    if @@flows[cl]
      @@flows[cl].each_key do |s|
        states |= [s]
      end
    end
    
    if @@transitions[cl]
      @@transitions[cl].each do |s, h|
        states |= [s]
        h.each_value do |t|
          states |= [t[1]]
        end
      end
    end
    
    @@cached_states[cl] = states
  end
  
  
  def each_state
    cl = type
    Component.cache_states cl    
    @@cached_states[cl].each
  end
  
  
  def each_event state = @state
    cl = type
    if not @@cached_events[cl] or
       not @@cached_events[cl][state]
      @@cached_events[cl] ||= {}
      @@cached_events[cl][state] = []
      each_transition state do |t, d|
        @@cached_events[cl][state] |= t.events
      end
    end
    
    @@cached_events[cl][state].each
  end
  
  
  def step_continuous dt
  
    @dt = dt
  
    each_flow do |f|
      f.update self
    end
    
    each_flow do |f|
      f.eval self
    end
    
  end
  
  
  def step_discrete
  
    dormant = true

    if @active_transition
      dormant = false
      @active_transition.finish self
      @state = @active_transition_dest
      @active_transition = nil
    end

    each_transition do |t, d|
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
  
  
  attach({Exit => Exit}, Transition.new :exit, nil, [],
    proc {world.remove self})
  
end # class Component

end # module RedShift
