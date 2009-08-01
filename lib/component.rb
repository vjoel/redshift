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
class ContinuousAssignmentError < StandardError; end
class StrictnessError < StandardError; end

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
  shadow_library RedShift.library
  
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
    "<#{self.class}#{n}#{s}#{d}>"
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
    self.var_count = self.class.var_count
    
    restore {
      @start_state = Enter
      self.cont_state = self.class.cont_state_class.new
      
      do_defaults
      instance_eval(&block) if block
      do_setup
      
      if state
        raise RuntimeError, "Can't assign to state.\n" +
          "Occurred in initialization of component of class #{self.class}."
      end ## is this a useful restriction?
      
      self.state = @start_state
    }
  end

  def restore
    yield if block_given?
    update_cache
  end

  def do_defaults
    self.class.do_defaults self
  end
  private :do_defaults
  
  def do_setup
    self.class.do_setup self
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
#          var_count = shadow->var_count;
#          vars = (ContVar *)(&shadow->cont_state->begin_vars);
#          for (i = 0; i < var_count; i++)
#            if (vars[i].algebraic)
#              (*vars[i].flow)((ComponentShadow *)shadow);
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
  
  #-- C library stuff -----------------------------------------------#
  
  library = RedShift.library
  
  class << self; protected; attr_accessor :flow_file; end
  
  def self.inherited sub
    file_name = CGenerator.make_c_name(sub.name).to_s
    sub.shadow_library_file file_name
###    sub.define_c_class_method :resolve_offsets do
###      ## in deferred compiler, this gets defined only if have events/links
###      declare :ary => "VALUE ary"
###      body %{
###        ary = rb_ary_new();
###        
###      }
###      returns "ary"
###    end
  end
  
  library.declare_extern :typedefs => %{
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
  
  class SingletonShadowClass
    include Singleton
    include CShadow; shadow_library Component
    persistent false
    def self._load str; instance; end # may be provided in future versions
    def _dump depth; ""; end          # of Singleton
  end

  class FunctionWrapper < SingletonShadowClass
    def initialize
      calc_function_pointer
    end
    def self.make_subclass(file_name, &bl)
      cl = Class.new(self)
      cl.shadow_library_file file_name
      clname = file_name.sub /^#{@tag}/i, @tag
      Object.const_set clname, cl
      before_commit {cl.class_eval &bl}
        # this is deferred to commit time to resolve forward refs
        ## this would be more elegant with defer.rb
      cl
    end
  end
  
  class FlowWrapper < FunctionWrapper
    shadow_attr :flow => "Flow flow"
    shadow_attr :algebraic => "int algebraic"
    @tag = "Flow"
  end

  class GuardWrapper < FunctionWrapper
    shadow_attr :guard => "Guard guard"
    @tag = "Guard"

    def self.strict; @strict; end
    def strict; @strict ||= self.class.strict; end
  end

  # one per variable, shared by subclasses which inherit it
  # not a run-time object, except for introspection
  class ContVar   ## name shouldn't be same as C class
    attr_reader :name, :writable
    def initialize name, index_delta, cont_state, writable
      @name = name  ## name needed?
      @index_delta = index_delta
      @cont_state = cont_state
      @writable = writable
    end
    def index
      @cont_state.inherited_var_count + @index_delta
    end
  end
  
  # one subclass per component subclass; one instance per component
  # must have only ContVar struct members
  class ContState
    include CShadow; shadow_library Component
    
    shadow_struct.declare :begin_vars =>
      "struct {} begin_vars __attribute__ ((aligned (8)))"
      # could conceivably have to be >8, or simply ((aligned)) on some platforms
      # but this seems to work for x86 and sparc
    
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
          file_name =
            component_class.shadow_library_source_file.name[/.*(?=\.c$)/] +
            "_ContState"     ## a bit hacky
          shadow_library_file file_name
          component_class.shadow_library_include_file.include(
            shadow_library_include_file)
        end
        cl
      end
      
      def find_var var_name
        @vars[var_name] ||
          (superclass.find_var var_name if superclass != ContState)
      end

      def add_var var_name, writable    # yields to block only if var was added
        var = find_var var_name
        if var
          unless writable == :permissive or var.writable == writable
            raise StrictnessError,
              "\nVariable #{var_name} redefined with different strictness."
          end
        else
          var = @vars[var_name] =
            ContVar.new(var_name, @vars.size, self, writable)
          shadow_attr var_name => "ContVar #{var_name}"
          yield if block_given?
        end
        var
      end

      def inherited_var_count
        unless @inherited_var_count
          raise Library::CommitError unless committed?
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
  
  _load_data_method.post_code %{
    rb_funcall(shadow->self, #{library.declare_symbol :restore}, 0);
  }
  
  ### need to protect these globals somehow
  
  # global rk_level, time_step (not used outside continuous update)
  library.declare :rk_level   => "long    rk_level"
  library.declare :time_step  => "double  time_step"
  library.include_file.declare :rk_level   => "extern long     rk_level"
  library.include_file.declare :time_step  => "extern double   time_step"

  # global d_tick (used only outside continuous update)
  library.declare :d_tick => "long d_tick"
  library.include_file.declare :d_tick => "extern long d_tick"
  
  library.setup :rk_level => "rk_level = 0"
  library.setup :d_tick   => "d_tick   = 1"  # alg flows need to be recalculated
  
  shadow_attr_accessor :cont_state   => [ContState]
  protected :cont_state, :cont_state=
  
  shadow_attr_accessor :state        => State
  protected :state=
  
  shadow_attr_accessor :var_count    => "long var_count"
    ## needn't be persistent
  protected :var_count=
  
  shadow_attr_reader :nonpersistent, :outgoing     => Array
  shadow_attr_reader :nonpersistent, :trans        => Transition
  shadow_attr_reader :nonpersistent, :phases       => Array
  shadow_attr_reader :nonpersistent, :dest         => State
  
  def active_transition; trans; end # for instrospection
  
  ## these should be short, or bitfield
  shadow_attr :nonpersistent, :cur_ph => "long cur_ph"
  shadow_attr :nonpersistent, :strict => "long strict" # = is cur state strict?
  
  class << self
  
    # The flow hash contains flows contributed (not inherited) by this
    # class. The flow table is the cumulative hash (by state) of arrays
    # (by var) of flows.

    def flow_hash
      @flow_hash ||= {}
    end
    
    def add_flow h      # [state, var] => flow_wrapper_subclass, ...
      flow_hash.update h
    end

    def flow_table
      unless @flow_table
        assert committed?
        ft = {}
        if defined? superclass.flow_table
          for k, v in superclass.flow_table
            ft[k] = v.dup
          end
        end
        for (state, var), flow_class in flow_hash
          (ft[state] ||= [])[var.index] = flow_class.instance
        end
        @flow_table = ft
      end
      @flow_table
    end
    
    def var_count
      @var_count ||= cont_state_class.cumulative_var_count
    end
    
    def cont_state_class
      @cont_state_class ||= ContState.make_subclass_for(self)
    end
    
    def permissively_continuous(*var_names)
      _continuous(:permissive, var_names)
    end
    
    def strictly_continuous(*var_names)
      _continuous(false, var_names)
    end
    alias constant strictly_continuous ### should also prohibit LHS use
    
    def continuous(*var_names)
      _continuous(true, var_names)
    end
    
    def _continuous(writable, var_names)
      var_names.collect do |var_name|
        var_name = var_name.intern if var_name.is_a? String
        ssn = cont_state_class.shadow_struct.name
        exc = shadow_library.declare_class AlgebraicAssignmentError
        msg = "\\\\nCannot set #{var_name}; it is defined algebraically."
        
        cont_state_class.add_var var_name, writable do
          class_eval %{
            define_c_method :#{var_name} do
              declare :cont_state => "#{ssn} *cont_state"
              body %{
                cont_state = (#{ssn} *)shadow->cont_state;
                if (cont_state->#{var_name}.algebraic &&
                    cont_state->#{var_name}.d_tick != d_tick)
                  (*cont_state->#{var_name}.flow)((ComponentShadow *)shadow);
              }
              returns "rb_float_new(cont_state->#{var_name}.value_0)"
            end
          }
          
          if writable
            class_eval %{
              define_c_method :#{var_name}= do
                arguments :value
                declare :cont_state => "#{ssn} *cont_state"
                body %{
                  cont_state = (#{ssn} *)shadow->cont_state;
                  if (cont_state->#{var_name}.algebraic)
                    rb_raise(#{exc}, #{msg.inspect});
                  cont_state->#{var_name}.value_0 = NUM2DBL(value);
                  d_tick++;
                }
                returns "value"
              end
            }
          else
            exc2 = shadow_library.declare_class ContinuousAssignmentError
            msg2 = "\\\\nCannot set #{var_name}; it is strictly continuous."
            class_eval %{
              define_c_method :#{var_name}= do
                arguments :value
                declare :cont_state => "#{ssn} *cont_state"
                body %{
                  cont_state = (#{ssn} *)shadow->cont_state;
                  if (cont_state->#{var_name}.algebraic)
                    rb_raise(#{exc}, #{msg.inspect});
                  if (!NIL_P(shadow->state))
                    rb_raise(#{exc2}, #{msg2.inspect});
                  cont_state->#{var_name}.value_0 = NUM2DBL(value);
                  d_tick++;
                }
                returns "value"
              end
            }
          end
        end
      end
    end
    alias number continuous
      ## eventually, number values could be stored as ordinary shadow_attrs
      ## to save space and time during continuous step. (Will need to
      ## change Flow#translate.)
  
  end
  
  define_c_method :update_cache do body "__update_cache(shadow)" end
  
  library.define(:__update_cache).instance_eval do
    flow_wrapper_type = RedShift::Component::FlowWrapper.shadow_struct.name
    scope :extern ## might be better to keep static and put in world.c
    arguments "struct #{RedShift::Component.shadow_struct.name} *shadow"
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
      VALUE       strict;
    }.tabto(0)
    
    body %{
      //# Cache outgoing transitions as [t, g, [phase0, phase1, ...], dest, ...]
      shadow->outgoing = rb_funcall(shadow->self,
                         #{declare_symbol :outgoing_transitions}, 0);
      
      strict = rb_funcall(shadow->outgoing, #{declare_symbol :pop}, 0);
      shadow->strict = RTEST(strict);

      //# Cache flows.
      var_count = shadow->var_count;
      vars = (ContVar *)(&shadow->cont_state->begin_vars);
      
      for (i = 0; i < var_count; i++) {
        vars[i].flow = 0;
        vars[i].algebraic = 0;
        vars[i].d_tick = 0;
      }
      
      flow_table = rb_funcall(rb_obj_class(shadow->self),
                   #{declare_symbol :flow_table}, 0);
        //## could use after_commit to cache this method call
      flow_array = rb_hash_aref(flow_table, shadow->state);
      
      if (flow_array != Qnil) {
        Check_Type(flow_array, T_ARRAY);

        count = RARRAY(flow_array)->len;
        flows = RARRAY(flow_array)->ptr;

        if (count > var_count)
          rb_raise(#{declare_module IndexError},
                 "Index into continuous variable list out of range: %d > %d.",
                 count, var_count);

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
    
  define_c_method :__set__world do
    arguments :world
    body "shadow->world = world"
  end
  protected :__set__world
  
#if false
#  define_c_method :recalc_alg_flows do ### need this?
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
#          (*vars[i].flow)((ComponentShadow *)shadow);
#    }
#  end
#
#  define_c_method :increment_d_tick do
#    body "d_tick++"
#  end
#end
end # class Component

end # module RedShift
