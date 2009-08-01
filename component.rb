require 'singleton'
require 'superhash'
require 'redshift/flow'
require 'redshift/state'
require 'redshift/meta'

=begin

==To do.
 
marshalling: write out enough metadata to check for differing version of component layout.

=end

module RedShift

class AlgebraicAssignmentError < StandardError; end
  
class Transition
  attr_reader :name, :guard, :phases
  def initialize n, g, p
    @name = n || "transition_#{id}".intern
    @guard, @phases = g, p
  end
end

Enter = State.new :Enter, RedShift
Exit = State.new :Exit, RedShift
Always = Transition.new :Always, nil, []

class World; end

class Component
  include CShadow
  shadow_library CLib
  
  attr_reader :start_state

  Enter = RedShift::Enter
  Exit = RedShift::Exit

  # Phase classes
  class Action < Array; end   ## rename these to ActionPhase, etc.
  class Reset  < Array; end
  class Event  < Array; end
  class Guard  < Array; end

  class DynamicEventValue < Proc; end
  
  def inspect data = nil
    n = " #{@name}" if @name
    s = ": #{state}" if state
    d = "; #{data}" if data
    "<#{type}#{n}#{s}#{d}>"
  end
  
  def initialize(world, &block)
    if $REDSHIFT_DEBUG
      unless caller[1] =~ /redshift\/world.*`create'\z/ or
             caller[0] =~ /`initialize'\z/
        puts caller[1]; puts
        puts caller.join("\n"); exit
        raise "\nComponents can be created only using " +
              "the create method of a world.\n"
      end
    end

    __set__world world
    
    restore {
      @start_state = Enter
      self.type_data = type.type_data
      self.cont_state = type.cont_state_class.new
      
      do_defaults
      instance_eval(&block) if block
      do_setup
      
      raise RuntimeError if state
      self.state = @start_state
    }
  end

  def restore
    yield if block_given?
    update_cache
  end

  def do_defaults
    type.do_defaults self
  end
  private :do_defaults
  
  def do_setup
    type.do_setup self
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
    ## should be possible to turn off superclass's setup so that 
    ## it can be overridden. 'nosupersetup'? explicit 'super'?
    superclass.do_setup instance if superclass.respond_to? :do_setup
    if @setup_procs
      for pr in @setup_procs
        instance.instance_eval(&pr)
      end
    end
  end
  
  ## move to C
  # is it right to return false when link is nil?
  def test_event link_sym, event
    link = send link_sym
    link && link.send(event)
  end
  
  ## move to C
  def do_events events
    for writer, value in events  
      v = value.is_a?(DynamicEventValue) ? instance_eval(&value) : value
      send writer, v
    end
  end
  
  ## move to C
  def do_resets resets
#          var_count = shadow->type_data->var_count;
#          vars = (ContVar *)(&shadow->cont_state->begin_vars);
#          for (i = 0; i < var_count; i++)
#            if (vars[i].algebraic)
#              (*vars[i].flow)(shadow);
#        for each comp on curr_R
#          if reset
#            for each var in comp
#              error if algebraic
#              if var is reset
#                compute reset
#                store in value_1 of var
#              else
#                copy from value_0 to value_1
  end
  
  ## shouldn't be necessary
  def insteval_proc pr
    instance_eval &pr
  end
  
  #-- CLib stuff -----------------------------------------------#
  
  class << self; protected; attr_accessor :flow_file; end
  
  def self.inherited sub
    file_name = CGenerator.make_c_name(sub.name).to_s
    sub.shadow_library_file file_name
  end
  
  CLib.declare_extern :typedefs => %{
    typedef struct #{shadow_struct_name} ComponentShadow;
    typedef void (*Flow)(ComponentShadow *);  // evaluates one variable
    typedef int (*Guard)(ComponentShadow *);  // evaluates a guard expr
    typedef struct {
      unsigned    d_tick    : 16; // last discrete tick at which flow computed
      unsigned    rk_level  :  3; // last rk level at which flow was computed
      unsigned    algebraic :  1; // should compute flow when inputs change?
      unsigned    nested    :  1; // to catch circular evaluation
      Flow        flow;           // cached flow function of current state
      double      value_0;        // value during discrete step
      double      value_1;        // value at steps of Runge-Kutta
      double      value_2;
      double      value_3;
    } ContVar;
  }.tabto(0)
  
  class FlowAttribute < CNativeAttribute
    @pattern = /\A(Flow)\s+(\w+)\z/
  end
  
  class GuardAttribute < CNativeAttribute
    @pattern = /\A(Guard)\s+(\w+)\z/
  end
  
  class ContVarAttribute < CNativeAttribute
    @pattern = /\A(ContVar)\s+(\w+)\z/
    
    def initialize(*args)
      super
      # serialize value_0
      @dump = "rb_ary_push(result, rb_float_new(shadow->#{@cvar}.value_0))"
      @load = "shadow->#{@cvar}.value_0 = NUM2DBL(rb_ary_shift(from_array))"
    end
  end

  # one subclass and one instance per flow equation
  # generated by flow classes; compiled at commit; instantiated after commit
  class FlowWrapper
    include Singleton
    include CShadow; shadow_library Component
    shadow_attr :flow => "Flow flow"
    shadow_attr :algebraic => "int algebraic"
    def initialize
      calc_function_pointer
    end
    def self._load str
      instance  ## why isn't this the default behavior of Singleton
    end
    def _dump depth
      "" ## or nil?
    end
    @@count = 0
    class << self
      def make_subclass(file_name, &bl)
        cl = Class.new(self)
        cl.shadow_library_file file_name
        clname = file_name.sub /^flow/, "Flow"
        Object.const_set clname, cl
        @@count += 1
        cl.instance_eval {@source_code = bl}
        cl
      end
      def before_commit
        # this is deferred to commit time to resolve forward refs
        class_eval &@source_code if self != FlowWrapper
      end
    end
  end

  ## unify with above
  # one subclass and one instance per guard expr
  # generated by guard class; compiled at commit; instantiated after commit
  class GuardWrapper
    include Singleton
    include CShadow; shadow_library Component
    shadow_attr :guard => "Guard guard"
    def initialize
      calc_function_pointer
    end
    def self._load str
      instance  ## why isn't this the default behavior of Singleton
    end
    def _dump depth
      "" ## or nil?
    end
    @@count = 0
    class << self
      def make_subclass(file_name, &bl)
        cl = Class.new(self)
        cl.shadow_library_file file_name
        clname = file_name.sub /^guard/, "Guard"
        Object.const_set clname, cl
        @@count += 1
        cl.instance_eval {@source_code = bl}
        cl
      end
      def before_commit
        # this is deferred to commit time to resolve forward refs
        class_eval &@source_code if self != GuardWrapper
      end
    end
  end

  # one subclass and one instance per component class
  # the flow hash contains flows contributed (not inherited) by this class
  # the flow table is the cumulative hash (by state) of arrays (by var) of flows
  class TypeData
    include Singleton
    include CShadow; shadow_library Component  ## does it need to be?
    shadow_attr_accessor :flow_table => Hash  ## can be ordinary ruby attr
    shadow_attr_accessor :var_count  => "long var_count"
    protected :flow_table=, :var_count=
    
    class << self
      attr_reader :flow_hash, :component_class
      
      def make_subclass_for component_class
        if component_class == Component
          cl = TypeData
        else
          cl = Class.new(component_class.superclass.type_data_class)
          component_class.const_set("TypeData", cl)
        end
        cl.instance_eval do
          @component_class = component_class
          @flow_hash = {}
        end
        cl
      end
      
      def add_flow h      # [state, var] => flow_wrapper_subclass, ...
        @flow_hash.update h
      end
    end
    
    def initialize
      cc = type.component_class
      self.var_count  = cc.cont_state_class.cumulative_var_count
      self.flow_table = ft = {}
      unless cc == Component
        type.superclass.instance.flow_table.each do |k, v|
          ft[k] = v.dup
        end
      end

      for (state, var), flow_class in type.flow_hash
        (ft[state] ||= [])[var.index] = flow_class.instance
      end
    end
  end
  
  # one per variable, shared by subclasses which inherit it
  # not a run-time object, except for introspection
  class ContVar   ## name shouldn't be same as C class
    attr_reader :name
    def initialize name, index_delta, cont_state
      @name = name  ## name needed?
      @index_delta = index_delta
      @cont_state = cont_state
    end
    def index
      @cont_state.inherited_var_count + @index_delta
    end
  end
  
  # one subclass per component subclass; one instance per component
  # must have only ContVar struct members
  class ContState
    include CShadow; shadow_library Component
    
    shadow_struct.declare :begin_vars => "struct {} begin_vars"
    
    class << self
      def make_subclass_for component_class
        if component_class == Component
          cl = ContState
        else
          sup = component_class.superclass.cont_state_class
          cl = component_class.const_set("ContState", Class.new(sup))
        end
        cl.instance_eval do
          @component_class = component_class
          @vars = {}
        end
        cl
      end
      
      def find_var var_name
        @vars[var_name] ||
          (superclass.find_var var_name if superclass != ContState)
      end

      def add_var var_name    # yields to block only if var was added
        var = find_var var_name
        unless var
          var = @vars[var_name] = ContVar.new(var_name, @vars.size, self)
          shadow_attr var_name => "ContVar #{var_name}"
          yield if block_given?
        end
        var
      end

      def inherited_var_count
        unless @inherited_var_count
          raise CommitError unless committed?
          if self == ContState
            @inherited_var_count = 0
          else
            @inherited_var_count = superclass.cumulative_var_count
          end
        end
        @inherited_var_count
      end

      def cumulative_var_count
        @vars.size + inherited_var_count
      end
    end
  end
  
  # global rk_level, time_step (not used outside continuous update)
  CLib.declare :rk_level   => "long    rk_level"
  CLib.declare :time_step  => "double  time_step"
  CLib.include_file.declare :rk_level   => "extern long     rk_level"
  CLib.include_file.declare :time_step  => "extern double   time_step"

  # global d_tick (used only outside continuous update)
  CLib.declare :d_tick => "long d_tick"
  CLib.include_file.declare :d_tick => "extern long d_tick"
  
  CLib.setup :rk_level => "rk_level = 0"
  CLib.setup :d_tick   => "d_tick   = 1"  # alg flows need to be recalculated
  
  shadow_attr_accessor :type_data    => [TypeData]
  shadow_attr_accessor :cont_state   => [ContState]
  protected :type_data, :type_data=, :cont_state, :cont_state=
  
  shadow_attr_accessor :state        => State
  protected :state=
  
  shadow_attr_reader :outgoing     => Array
  shadow_attr_reader :trans        => Transition
  shadow_attr_reader :phases       => Array
  shadow_attr_reader :dest         => State
  
  def active_transition; trans; end
  
  shadow_attr :cur_ph => "long cur_ph"
  
  class << self
  
    def type_data
      @type_data ||= type_data_class.instance
    end
    
    def type_data_class 
      @type_data_class ||= TypeData.make_subclass_for(self)
    end
    
    def cont_state_class
      @cont_state_class ||= ContState.make_subclass_for(self)
    end
    
    def continuous(*var_names) # continuous :v1, :v2, ...
      var_names.collect do |var_name|
        var_name = var_name.intern if var_name.is_a? String
        ssn = cont_state_class.shadow_struct.name
        exc = CLib.declare_class AlgebraicAssignmentError
        msg = "\\\\nCannot set #{var_name}; it is defined algebraically."
        cont_state_class.add_var var_name do
          class_eval %{
          
            define_method :#{var_name} do
              declare :cont_state => "#{ssn} *cont_state"
              body %{
                cont_state = (#{ssn} *)shadow->cont_state;
                if (cont_state->#{var_name}.algebraic &&
                    cont_state->#{var_name}.d_tick != d_tick)
                  (*cont_state->#{var_name}.flow)(shadow);
              }
              returns "rb_float_new(cont_state->#{var_name}.value_0)"
            end
            
            define_method :#{var_name}= do
              arguments :value
              declare :cont_state => "#{ssn} *cont_state"
              body %{
                cont_state = (#{ssn} *)shadow->cont_state;
                if (cont_state->#{var_name}.algebraic)
                  rb_raise(#{exc}, #{msg.inspect});
                cont_state->#{var_name}.value_0 = NUM2DBL(value);
              }
              returns "value"
            end
            
          }
        end
      end
    end
    
    ### fwd ref doesn't work
    def link vars # link :x => MyComponent, :y => :FwdRefComponent
      for var_name, var_type in vars
        shadow_attr_accessor var_name => [var_type]
        (@link_vars ||= {}).update vars
      end
    end
    ### shadow_attr won't accept redefinition, and anyway there is
    ###   the contra/co variance problem.
  
    def link_type var
      t = @link_vars[var] ### not inherited!!!
      case t
      when nil;   superclass.link_type var if defined? superclass.link_type
      when Class; t
      else        const_get t
      end
    end
    
    def exported_events
      @exported_events ||= 
        if self == Component
          Hash.new
        else
          SuperHash.new(superclass.exported_events)
        end
    end
    
    def export(*events)
      for event in events
        unless exported_events[event]
          shadow_attr_accessor event => Object
          protected "#{event}=".intern
          exported_events[event] = true
        end
      end
    end
  end
  
  define_method :update_cache do body "__update_cache(shadow)" end
  
  CLib.define(:__update_cache).instance_eval do
    flow_wrapper_type = RedShift::Component::FlowWrapper.shadow_struct.name
    arguments "#{RedShift::Component.shadow_struct.name} *shadow"
    declare :locals => %{
      #{flow_wrapper_type} *flow_wrapper;

      VALUE       flow_table;       // Hash
      VALUE       flow_array;       // Array
      VALUE       outgoing;
      long        var_count;
      ContVar    *vars;
      long        i;
      long        count;
      VALUE      *flows;
    }.tabto(0)
    
    body %{
      //# Cache outgoing transitions as [t, g, [phase0, phase1, ...], dest, ...]
      shadow->outgoing = rb_funcall(shadow->self,
                         #{declare_symbol :outgoing_transitions}, 0);
      
      //# Cache flows.
      var_count = shadow->type_data->var_count;
      vars = (ContVar *)(&shadow->cont_state->begin_vars);
      
      for (i = 0; i < var_count; i++) {
        vars[i].flow = 0;
        vars[i].algebraic = 0;
        vars[i].d_tick = 0;
      }
      
      flow_table = shadow->type_data->flow_table;
      flow_array = rb_hash_aref(flow_table, shadow->state);
      
      if (flow_array != Qnil) {
        Check_Type(flow_array, T_ARRAY);

        count = RARRAY(flow_array)->len;
        flows = RARRAY(flow_array)->ptr;

        if (count > var_count)
          rb_raise(#{declare_module IndexError},
                   "Index into continuous variable list out of range.");

        for (i = 0; i < count; i++)
          if (flows[i] != Qnil) {
            Data_Get_Struct(flows[i], #{flow_wrapper_type}, flow_wrapper);
            vars[i].flow      = flow_wrapper->flow;
            vars[i].algebraic = flow_wrapper->algebraic;
          }
      }
    }
  end

  shadow_attr_reader :world => World
    
  define_method :__set__world do
    arguments :world
    body "shadow->world = world"
  end
  protected :__set__world
  
#if false
#  define_method :recalc_alg_flows do ### need this?
#    declare :locals => %{
#      ContVar    *vars;
#      long        i;
#      long        var_count;
#    }.tabto(0)
#    
#    body %{
#      var_count = shadow->type_data->var_count;
#      vars = (ContVar *)(&shadow->cont_state->begin_vars);
#      for (i = 0; i < var_count; i++)
#        if (vars[i].algebraic)
## also check d_tick
#          (*vars[i].flow)(shadow);
#    }
#  end
#
#  define_method :increment_d_tick do
#    body "d_tick++"
#  end
#end
end # class Component

end # module RedShift
