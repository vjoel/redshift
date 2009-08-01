module RedShift
  
class Component
  
  class_superhash2 :flows, :transitions
  class_superhash :exported_events, :link_type, :states
  
  class << self
    def export(*events)
      for event in events
        unless exported_events[event]
          shadow_attr_accessor :nonpersistent, event => Object
            ### should be reader only
          protected "#{event}=".intern
          exported_events[event] = true
        end
      end
    end
    
    def link vars # link :x => MyComponent, :y => :FwdRefComponent
      for var_name, var_type in vars
        var_name = var_name.intern if var_name.is_a?(String)
        link_type[var_name] = var_type ## should check < Component??
      end
      before_commit do
        for var_name, var_type in vars
          lt = link_type[var_name]
          unless lt.is_a? Class
            lt = link_type[var_name] = const_get(lt)
          end
          shadow_attr_accessor var_name => [lt]
        end
      end
    end
    ### shadow_attr won't accept redefinition, and anyway there is
    ###   the contra/co variance problem.

    def attach_state name
      const_set name, State.new(name, self)
    end

    def attach states, features
      if features.type != Array
        features = [features]
      end

      case states
        when State;  attach_flows [states], features
        when Array;  attach_flows states, features
        when Hash;   attach_transitions states, features
        else         raise SyntexError, "Bad state list: #{states.inspect}"
      end
    end

    def attach_flows states, new_flows
      for state in states
        unless state.is_a? State
          raise TypeError, "Must be a state: #{state}"
        end

        fl = flows(state)

        for f in new_flows
          fl[f.var] = f
          f.attach self, state
        end
      end
    end

    def attach_transitions states, new_transitions
      for src, dest in states
        unless src.is_a? State
          raise TypeError, "Source must be a state: #{src}"
        end

        unless dest.is_a? State
          raise TypeError, "Destination must be a state: #{dest}"
        end

        tr = transitions(src)

        for t in new_transitions
          tr[t.name] = [t, dest]
        end
      end
    end

    def cached_transitions s
      unless @cached_transitions
        assert committed?
        @cached_transitions = {}
      end
      @cached_transitions[s] ||= transitions(s).values
    end
  end

  def states
    type.states.keys
  end
  
  def flows s = state
    type.flows s
  end
  
  def transitions s = state
    type.cached_transitions s
  end
  
  ## move into C code in __update_cache?
  def outgoing_transitions
    ary = []
    strict = true
    for t, d in transitions
      ary << t << d << t.phases << t.guard
      
      ## this is inefficient
      guard_list = t.guard
      if guard_list
        guard_list.each {|g| strict &&= g.respond_to?(:strict) && g.strict }
      end
    end

    ary << strict # just a faster way to return mult. values
  end
  
  def self.define_guard guard
    guard.guard_wrapper self
  end
  
end # class Component

end # module RedShift
