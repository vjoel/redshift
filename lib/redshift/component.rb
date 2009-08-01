require 'singleton'
require 'superhash'
require 'accessible-index'
require 'redshift/state'
require 'redshift/meta'

module RedShift

class AlgebraicAssignmentError < StandardError; end
class NilLinkError < StandardError; end
class CircularDefinitionError < StandardError; end
class StrictnessError < StandardError; end
class ConstnessError < StandardError; end
class TransitionError < StandardError; end
class SyntaxError < ::SyntaxError; end

# Raised when a component tries to perform an action that makes sense only
# during initialization.
class AlreadyStarted < StandardError; end

# These classes are derived from Array for efficient access to contents
# from C code.
class XArray < Array
  def inspect; "<#{self.class.name.split("::")[-1]}: #{super[1..-2]}>"; end
end

class Transition < XArray ## put this in meta?
  attr_reader :name

  extend AccessibleIndex
  G_IDX = 0; A_IDX = 1; R_IDX = 2; E_IDX = 3
  index_accessor \
    :guard => G_IDX, :action => A_IDX, :reset => R_IDX, :event => E_IDX

  def initialize n, h
    @name = n || "transition_#{object_id}".intern
    self.guard = h[:guard]; self.action = h[:action]
    self.event = h[:event]; self.reset = h[:reset]
  end
end

class Flow    ## rename to equation? formula? put in meta?
  attr_reader :var, :formula
  
  def initialize v, f
    @var, @formula = v, f
  end
  
  # Strict flows change value only over continuous time, and not within the
  # steps of the discrete update. This can be false only for an AlgebraicFlow
  # which depends on non-strict variables.
  def strict; true; end
end

class AlgebraicFlow < Flow
  attr_reader :strict   # true iff the RHS of the eqn. has only strictly
                        # continuous variables.
end

class EulerDifferentialFlow < Flow; end
class RK4DifferentialFlow < Flow; end

Always = Transition.new :Always, :guard => nil

class Component
  
  attr_reader :start_state
  attr_accessor :name

  attach_state(:Enter)
  attach_state(:Exit)

  class GuardPhase  < XArray; end
  class ActionPhase < XArray; end
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

  def inspect data = nil
    items = []
    items << state if state
    
    var_types = [:constant_variables, :continuous_variables, :link_variables]
    var_types.each do |var_type|
      var_list = self.class.send(var_type)
      unless var_list.empty?
        strs = var_list.map {|name,info| name.to_s}.sort.map do |name|
          begin
            "#{name} = #{send(name) || "nil"}"
          rescue RedShift::CircularDefinitionError
            "#{name}: CIRCULAR"
          rescue => ex
            "#{name}: #{ex.inspect}"
          end
        end
        items << strs.join(", ")
      end
    end
    
    items << data if data
    return "<#{[self, items.join("; ")].join(": ")}>"
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
        instance.instance_eval(&pr) ## should be pr.call(instance) ?
      end
    end
  end
  
  ## shouldn't be necessary
  def insteval_proc pr
    instance_eval(&pr)
  end
  
end # class Component

# The asymmetry between these two states is that components in Enter are active
# in the continuous and discrete updates. Components in Exit do not evolve.
Enter = Component::Enter
Exit = Component::Exit

end # module RedShift
