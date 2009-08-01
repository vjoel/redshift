module RedShift

class Component
  
  class_superhash2 :flows, :transitions
  class_superhash :exported_events      # :event => index
  class_superhash :link_type, :states
  class_superhash :continuous_variables, :constant_variables ## bad name
  
  @subclasses = []

  class << self
    # Component is abstract, and not included in subclasses. This returns nil
    # when called on subs.
    attr_reader :subclasses

    def inherited(sub)
      Component.subclasses << sub
    end
    
    # Declare +events+ to be exported (optional). Returns array of corresponding
    # event indexes which can be used in code generation.
    def export(*events)
      events.map do |event|
        exported_events[event.to_sym] ||= exported_events.size
      end
    end

    # link :x => MyComponent, :y => :FwdRefComponent
    def link vars
      vars.each do |var_name, var_type|
        link_type[var_name.to_sym] = var_type
      end
    end

    def attach_state name
      state = State.new(name, self)
      const_set(name, state)
      states[name] = state
    end

    def attach states, features
      if features.class != Array
        features = [features]
      end

      case states
        when Array;  attach_flows states, features
        when Hash;   attach_transitions states, features
        else         raise SyntaxError, "Bad state list: #{states.inspect}"
      end
    end

    def attach_flows states, new_flows
      for state in states.sort_by {|s| s.to_s}
        unless state.is_a? State
          state = const_get(state.to_s)
        end
        
        unless state.is_a? State
          raise TypeError, "Must be a state: #{state.inspect}"
        end

        fl = flows(state)

        for f in new_flows
          fl[f.var] = f
        end
      end
    end

    def attach_transitions states, new_transitions
      for src, dest in states.sort_by {|s| s.to_s}
        unless src.is_a? State
          src = const_get(src.to_s)
        end
        unless src.is_a? State
          raise TypeError, "Source must be a state: #{src.inspect}"
        end

        unless dest.is_a? State
          dest = const_get(dest.to_s)
        end
        unless dest.is_a? State
          raise TypeError, "Destination must be a state: #{dest.inspect}"
        end

        @cached_transitions = nil
        tr = transitions(src)

        for t in new_transitions
          tr[t.name] = [t, dest]
        end
      end
    end

    def cached_transitions s
      @cached_transitions ||= {}
      @cached_transitions[s] ||= transitions(s).values
    end
    
    # kind is :strict, :piecewise, or :permissive
    def attach_continuous_variables(kind, var_names)
      var_names.each do |var_name|
        continuous_variables[var_name] = kind
      end
    end
    
    # kind is :strict, :piecewise, or :permissive
    def attach_constant_variables(kind, var_names)
      var_names.each do |var_name|
        constant_variables[var_name] = kind
      end
    end
  end

  def states
    self.class.states.values
  end
  
  def flows s = state
    self.class.flows s
  end
  
  def transitions s = state
    self.class.cached_transitions s
  end
  
  ## move into C code in __update_cache?
  ## can't this be cached in some per-class location?
  ## This seems to be a major bottleneck.
  def outgoing_transitions
    ary = []
    strict = true
    for t, d in transitions
      ary << t << d << t.phases << t.guard
      
      ## this is inefficient -- cache by state?
      guard_list = t.guard
      if guard_list
        guard_list.each {|g| strict &&= g.respond_to?(:strict) && g.strict }
      end
    end

    ary << strict # just a faster way to return mult. values
  end
  
end # class Component

end # module RedShift
