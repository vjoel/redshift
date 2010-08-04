module RedShift

class Component
  
  class_superhash2 :flows
  class_superhash :exported_events      # :event => index
  class_superhash :states
  class_superhash :continuous_variables, :constant_variables
  class_superhash :link_variables       # :link_name => [type, strictness]
  class_superhash :input_variables      # :var_name => :piecewise | :strict
  class_superhash :queues
    
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

    def queue(*var_names)
      var_names.each do |var_name|
        next if queues[var_name]
        queues[var_name] = true
        class_eval %{
          def #{var_name}
            @#{var_name} ||= Queue.new(self)
          end
        }
      end
    end
    
    def attach_link vars, strictness
      unless not strictness or strictness == :strict
        raise ArgumentError, "Strictness must be false or :strict"
      end
      unless vars.is_a? Hash
        raise SyntaxError, "Arguments to link must be of form :var => class, " +
          "where class can be either a Class or a string denoting class name"
      end
      vars.each do |var_name, var_type|
        link_variables[var_name.to_sym] = [var_type, strictness]
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
      states.each do |state|
        fl = flows(state)
        for f in new_flows
          fl[f.var] = f
        end
      end
    end

    def attach_transitions state_pairs, new_transitions
      new_transitions.delete_if {|t| t.guard && t.guard.any?{|g| g==false}}
      state_pairs.each do |src, dst|
        a = own_transitions(src)
        new_transitions.each do |t|
          name = t.name
          a.delete_if {|u,d| u.name == name}
          a << [t, dst]
        end
      end
    end
    
    # returns list of transitions from state s in evaluation order
    # (just the ones defined in this class)
    def own_transitions(s)
      @own_transitions ||= {}
      @own_transitions[s] ||= []
    end
    
    def all_transitions(s)
      if self < Component
        own_transitions(s) + superclass.all_transitions(s)
      else
        own_transitions(s)
      end
    end

    ## should be called only after generating code, to get strict right
    def outgoing_transition_data s
      ary = []
      all_strict = true
      seen = {}
      all_transitions(s).each do |t, d|
        next if seen[t.name] # overridden in subclass
        seen[t.name] = true

        t_strict = !t.sync || t.sync.empty?
        guard_list = t.guard
        guard_list and guard_list.each do |g|
          t_strict &&= g.respond_to?(:strict) && g.strict
        end
        all_strict &&= t_strict

        ary << [t, d, t.guard, t_strict]
      end

      result = []
      ary.reverse_each do |list| # since step_discrete reads them in reverse
        result.concat list
      end
      result << (all_strict ? 1 : 0) # other bits are used elsewhere
      result
    end
    
    def attach_variables(dest, kind, var_names, var_type = nil)
      if var_names.last.kind_of? Hash
        h = var_names.pop
        var_names.concat h.keys.sort_by {|n|n.to_s}
        defaults h
      end
      var_names.each do |var_name|
        dest[var_name.to_sym] = var_type ? [var_type, kind] : kind
      end
    end

    # kind is :strict, :piecewise, or :permissive
    def attach_continuous_variables(kind, var_names)
      attach_variables(continuous_variables, kind, var_names)
    end
    
    # kind is :strict, :piecewise, or :permissive
    def attach_constant_variables(kind, var_names)
      attach_variables(constant_variables, kind, var_names)
    end
    
    def attach_input(kind, var_names)
      var_names.each do |var_name|
        input_variables[var_name.to_sym] = kind
      end
    end
    
    def find_var_superhash var_name
      [continuous_variables, constant_variables,
       link_variables, input_variables].find {|sh| sh[var_name]}
    end
  end

  def states
    self.class.states.values
  end
  
  def flows s = state
    self.class.flows s
  end
  
  def transitions s = state
    self.class.all_transitions s
  end  
end # class Component

end # module RedShift
