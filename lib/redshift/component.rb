require 'singleton'
require 'superhash'
require 'accessible-index'
require 'redshift/state'
require 'redshift/meta'

module RedShift

# Can be raised with a [msg, object] pair instead of just a msg string.
# In the former case, the +object+ is accessible.
module AugmentedException
  attr_reader :object
  
  def initialize(msg)
    if defined?(msg.first)
      msg, @object = *msg
      s = ((@object.inspect rescue
            @object.to_s) rescue
            "id ##{@object.object_id} of class #{@object.class}")
      msg += " Object is: $!.object == #{s}"
    end
    super msg
  end
end

class RedShiftError < StandardError
  include AugmentedException
end

class AlgebraicAssignmentError < RedShiftError; end
class NilLinkError < RedShiftError; end
class CircularDefinitionError < RedShiftError; end
class StrictnessError < RedShiftError; end
class ConstnessError < RedShiftError; end
class TransitionError < RedShiftError; end
class SyntaxError < ::SyntaxError; end
class UnconnectedInputError < RedShiftError; end

# Raised when a component tries to perform an action that makes sense only
# during initialization.
class AlreadyStarted < RedShiftError; end

# These classes are derived from Array for efficient access to contents
# from C code.
class XArray < Array
  def inspect; "<#{self.class.name.split("::")[-1]}: #{super[1..-2]}>"; end
end

class Transition < XArray ## put this in meta?
  attr_reader :name

  extend AccessibleIndex
  G_IDX = 0; A_IDX = 1; R_IDX = 2; E_IDX = 3; P_IDX = 4
  index_accessor \
    :guard => G_IDX, :action => A_IDX, :reset => R_IDX, :event => E_IDX,
    :post => P_IDX

  def initialize n, h
    @name = n || "transition_#{object_id}".intern
    self.guard = h[:guard]; self.action = h[:action]
    self.event = h[:event]; self.reset = h[:reset]
    self.post = h[:post]
  end
end

class Flow    ## rename to equation? formula? put in meta?
  attr_reader :var, :formula
  
  # Strict flows change value only over continuous time, and not within the
  # steps of the discrete update. This can be false only for an AlgebraicFlow
  # which depends on non-strict variables. In the algebraic case, a flow is
  # strict iff the RHS of the eqn. has only strictly continuous variables.
  attr_reader :strict
  
  def initialize v, f
    @var, @formula = v, f
    @strict = true
    self.class.needed = true
  end

  class << self; attr_accessor :needed; end
end

class AlgebraicFlow < Flow; end
class EulerDifferentialFlow < Flow; end
class RK4DifferentialFlow < Flow; end

class DerivativeFlow < Flow
  attr_reader :feedback
  def initialize v, f, feedback
    super(v, f)
    @feedback = feedback
  end
end

class DelayFlow < Flow
  attr_reader :delay_by
  def initialize v, f, delay_by
    super(v, f)
    @delay_by = delay_by
  end
end

class CexprGuard < Flow; end ## Kinda funny...
class Expr < Flow; end ## Kinda funny...

Always = Transition.new :Always, :guard => nil

class Component
  
  attr_reader :start_state
  attr_accessor :name

  attach_state(:Enter)
  attach_state(:Exit)

  class GuardPhase  < XArray; end
  class ActionPhase < XArray; end
  class PostPhase   < XArray; end
  class EventPhase  < XArray; end
  class ResetPhase  < XArray
    attr_accessor :value_map
    def inspect
      "<ResetPhase: #{value_map.inspect}>"
    end
  end
  
  class PhaseItem < XArray; extend AccessibleIndex; end
  
  class EventPhaseItem < PhaseItem
    E_IDX = 0; V_IDX = 1; I_IDX = 2
    index_accessor :event => E_IDX, :value => V_IDX, :index => I_IDX

    def value=(val)
      self[V_IDX] = case val
      when Proc
        DynamicEventValue.new(&val)
      when String
        ExprEventValue.new val
      when Literal # e.g., literal "x", or literal {...}
        val.literal_value
      else
        val
      end
    end

    def inspect; "<Event #{event}: #{value.inspect}>"; end
  end
  
  class GuardPhaseItem < PhaseItem
    LINK_OFFSET_IDX = 0; EVENT_INDEX_IDX = 1; LINK_IDX = 2; EVENT_IDX = 3
    index_accessor :link_offset => LINK_OFFSET_IDX,
                   :event_index => EVENT_INDEX_IDX,
                   :link => LINK_IDX, :event => EVENT_IDX
    def inspect; "<Guard #{link}.#{event}>"; end
  end

  class DynamicEventValue < Proc; end
  class ExprEventValue < String; end
  
  class Literal
    attr_accessor :literal_value
    def initialize val; self.literal_value = val; end
  end
  def Component.literal val
    Literal.new val
  end
  
  # Unique across all Worlds and Components in the process. Components are
  # numbered in the order which this method was called on them and not
  # necessarily in order of creation.
  def comp_id
    @comp_id ||= Component.next_comp_id
  end
  
  @next_comp_id = -1
  def Component.next_comp_id
    @next_comp_id += 1
  end
  
  def to_s
    "<#{self.class} #{name || comp_id}>"
  end

  VAR_TYPES = [:constant_variables, :continuous_variables, :link_variables,
    :input_variables]
  
  def inspect data = nil
    old_inspecting = Thread.current[:inspecting]
    Thread.current[:inspecting] = self
    
    items = []
    
    unless old_inspecting == self
      # avoids inf. recursion when send(name) raises exception that
      # calls inspect again.

      items << state if state

      VAR_TYPES.each do |var_type|
        var_list = self.class.send(var_type)
        unless var_list.empty?
          strs = var_list.map {|vname,info| vname.to_s}.sort.map do |vname|
            begin
              "#{vname} = #{send(vname) || "nil"}"
            rescue CircularDefinitionError
              "#{vname}: CIRCULAR"
            rescue UnconnectedInputError
              "#{vname}: UNCONNECTED"
            rescue NilLinkError
              "#{vname}: NIL LINK"
            rescue => ex
              "#{vname}: #{ex.inspect}"
            end
          end
          items << strs.join(", ")
        end
      end

      items << data if data
    end
    
    return "<#{[self, items.join("; ")].join(": ")}>"
  
  ensure
    Thread.current[:inspecting] = old_inspecting
  end
  
  def initialize(world)
    if $REDSHIFT_DEBUG
      unless caller[1] =~ /redshift\/world.*`create'\z/ or
             caller[0] =~ /`initialize'\z/
        raise ArgumentError, "Components can be created only using " +
              "the create method of a world.", caller
      end
    end

    __set__world world
    self.var_count = self.class.var_count
    
    restore {
      @start_state = Enter
      self.cont_state = self.class.cont_state_class.new
      
      do_defaults
      yield self if block_given?
      do_setup
      
      if state
        raise RuntimeError, "Can't assign to state.\n" +
          "Occurred in initialization of component of class #{self.class}."
      end ## is this a useful restriction?
      
      self.state = @start_state
    }
  end

  def restore
    if respond_to?(:event_values)
      event_count = self.class.exported_events.size
        ## should cache this size, since it can't change
      self.event_values = Array.new(event_count)
      self.next_event_values = Array.new(event_count)

      event_values.freeze
      next_event_values.freeze ## should do this deeply?
    end

    yield if block_given?

    init_flags
    update_cache
    clear_ck_strict # update_cache leaves these set assuming finishing a trans
  end

  def do_defaults
    self.class.do_defaults self
  end
  private :do_defaults
  
  def do_setup
    self.class.do_setup self
  end
  private :do_setup
  
  def self.do_assignment_map instance, h
    ## could be done in c code
    h.each do |writer, val|
      instance.send writer, val
    end
  end
  
  def self.do_defaults instance
    superclass.do_defaults instance if superclass.respond_to? :do_defaults
    do_assignment_map instance, @defaults_map if @defaults_map
    if @defaults_procs
      @defaults_procs.each do |pr|
        instance.instance_eval(&pr)
      end
    end
  end
  
  def self.do_setup instance
    ## should be possible to turn off superclass's setup so that 
    ## it can be overridden. 'nosupersetup'? explicit 'super'?
    superclass.do_setup instance if superclass.respond_to? :do_setup
    do_assignment_map instance, @setup_map if @setup_map
    if @setup_procs
      @setup_procs.each do |pr|
        instance.instance_eval(&pr)
      end
    end
  end
  
  ## shouldn't be necessary
  def insteval_proc pr
    instance_eval(&pr)
  end
  
  def disconnect input_var
    connect(input_var, nil, nil)
  end
  
  # +var_name+ can be a input var, a continuous var, or a constant var.
  def port var_name
    return nil unless var_name
    @ports ||= {}
    @ports[var_name] ||= begin
      var_name = var_name.to_sym
      
      if self.class.input_variables.key? var_name
        Port.new(self, var_name, true)
      elsif self.class.continuous_variables.key? var_name or
            self.class.constant_variables.key? var_name
        Port.new(self, var_name, false)
      else
        raise "No variable #{var_name.inspect} in #{self.class.inspect}"
      end
    end
  end
  
  class Port
    attr_reader :component, :variable, :connectable
    
    def initialize component, variable, connectable
      @component, @variable, @connectable = component, variable, connectable
    end
    
    # Convenience method to get source port rather than component/var pair.
    def source
      source_component && source_component.port(source_variable)
    end
    
    def check_connectable
      unless connectable
        raise TypeError, "Not connectable: #{variable} in #{component.class}"
      end
    end
    
    def connect port
      check_connectable
      component.connect(variable, port && port.component, port && port.variable)
    end
    
    def <<(other)
      connect(other)
      ##return other
    end
    
    def >>(other)
      other.connect(self)
      ##return other
    end
    
    def disconnect
      connect nil
    end
    
    def source_component
      check_connectable
      component.source_component_for(variable)
    end
    
    def source_variable
      check_connectable
      component.source_variable_for(variable)
    end
  end
  
end # class Component

# The asymmetry between these two states is that components in Enter are active
# in the continuous and discrete updates. Components in Exit do not evolve.
Enter = Component::Enter
Exit = Component::Exit

end # module RedShift
