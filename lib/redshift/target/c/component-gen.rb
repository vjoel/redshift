module RedShift
  class World
    include CShadow
    # just so we can call shadow_struct_name on it
  end

  HAVE_DEFINE_METHOD = Module.private_instance_methods.include?("define_method")
  
  class Component
    include CShadow
    shadow_library RedShift.library
    shadow_library_file "Component"
    library = RedShift.library
    
    subclasses.each do |sub|
      file_name = CGenerator.make_c_name(sub.name).to_s
      sub.shadow_library_file file_name
    end
    
    after_commit do
      # This is necessary because cont_state_class is lazy. ContState classes
      # not defined at this point don't need to be committed.
      subclasses.each {|cl| cl.cont_state_class}
    end

    library.declare_extern :typedefs => %{
      typedef struct #{shadow_struct_name} ComponentShadow;
      typedef void (*Flow)(ComponentShadow *);  // evaluates one variable
      typedef int (*Guard)(ComponentShadow *);  // evaluates a guard expr
      typedef double (*Expr)(ComponentShadow *);// evaluates a numerical expr
      #ifdef WIN32
      #pragma pack(push, 1)
      #endif
      typedef struct {
        unsigned    d_tick    : 16; // last d_tick at which alg flow computed
        unsigned    rk_level  :  3; // last rk level at which flow was computed
        unsigned    algebraic :  1; // should compute flow when inputs change?
        unsigned    strict    :  1; // never changes discretely
        unsigned    ck_strict :  1; // should check strict at end of phase
        unsigned    reset     :  1; // var is being reset
        Flow        flow;           // cached flow function of current state
        double      value_0;        // value during discrete step
        double      value_1;        // value at steps of Runge-Kutta
        double      value_2;
        double      value_3;
      } ContVar;
      #ifdef WIN32
      #pragma pack(pop)
      #endif
    }.tabto(0)

    INPUT_NONE     = 0
    INPUT_CONT_VAR = 1
    INPUT_CONST    = 2
    INPUT_INP_VAR  = 3

    Component.shadow_library_include_file.declare :InputVar => %{
      #define INPUT_NONE     #{INPUT_NONE}
      #define INPUT_CONT_VAR #{INPUT_CONT_VAR}
      #define INPUT_CONST    #{INPUT_CONST}
      #define INPUT_INP_VAR  #{INPUT_INP_VAR}
    }.tabto(0)

    class FlowAttribute < CNativeAttribute
      @pattern = /\A(Flow)\s+(\w+)\z/
    end

    class GuardAttribute < CNativeAttribute
      @pattern = /\A(Guard)\s+(\w+)\z/
    end

    class ExprAttribute < CNativeAttribute
      @pattern = /\A(Expr)\s+(\w+)\z/
    end

    class ContVarAttribute < CNativeAttribute
      @pattern = /\A(ContVar)\s+(\w+)\z/

      def initialize(*args)
        super
        # value_0 is the relevant state outside of continuous update
        @dump = "rb_ary_push(result, rb_float_new(shadow->#{@cvar}.value_0))"
        @load = "shadow->#{@cvar}.value_0 = NUM2DBL(rb_ary_shift(from_array))"
      end
    end

    # Useful way to represent an object that has compile time (pre-commit) and
    # run-time (post-commit) bevahior. The compile time behavior is in the
    # class, and the run time behavior is in the unique instance.
    class SingletonShadowClass
      include Singleton
      include CShadow; shadow_library Component
      persistent false
      def inspect; self.class.inspect_str; end
      class << self; attr_reader :inspect_str; end
    end

    # FunctionWrappers wrap function pointers for access from ruby.
    class FunctionWrapper < SingletonShadowClass
      def initialize
        calc_function_pointer
      end
      
      class << self
        attr_accessor :constructor
        
        def construct
          class_eval &constructor
        rescue => ex
          ex.message << " While defining #{inspect_str}."
          raise
        end
        
        def make_subclass(file_name, &bl)
          cl = Class.new(self)
          cl.constructor = bl
          cl.shadow_library_file file_name
          clname = file_name.sub /^#{@tag}/i, @tag
          Object.const_set clname, cl ## maybe put in other namespace?
          before_commit {cl.construct}
            # this is deferred to commit time to resolve forward refs
            ## this would be more elegant with defer.rb
            ## maybe precommit should be used for this now?
          cl
        end
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
    
    class ExprWrapper < FunctionWrapper
      shadow_attr :expr => "Expr expr"
      @tag = "Expr"
    end
    
    # one per variable, shared by subclasses which inherit it
    # not a run-time object, except for introspection
    class ContVarDescriptor
      attr_reader :name, :kind
      def initialize name, index_delta, cont_state, kind
        @name = name
        @index_delta = index_delta
        @cont_state = cont_state
        @kind = kind
      end
      def strict?; @kind == :strict; end
      def index
        @cont_state.inherited_var_count + @index_delta
      end
    end

    # One subclass per component subclass; one instance per component.
    # Must have only ContVars in the shadow struct.
    class ContState
      include CShadow; shadow_library Component

      ## maybe this should be in cgen as "shadow_aligned N"
      if /mswin/i =~ RUBY_PLATFORM
        shadow_struct.declare :begin_vars =>
          "ContVar begin_vars[1]" ## wasted
        
        Component.shadow_library_include_file.declare :first_cont_var => '
          #define FIRST_CONT_VAR(shadow) ((shadow)->cont_state->begin_vars[1])
        '
      else
        shadow_struct.declare :begin_vars =>
          "struct {} begin_vars __attribute__ ((aligned (8)))"
          # could conceivably have to be >8, or simply ((aligned)) on some
          # platforms but this seems to work for x86 and sparc

        Component.shadow_library_include_file.declare :first_cont_var => '
          #define FIRST_CONT_VAR(shadow) ((shadow)->cont_state->begin_vars)
        '
      end
      
      class_superhash :vars
      
      def vars
        self.class.vars
      end
      
      def var_at_index(idx)
        self.class.var_at_index(idx)
      end

      def strict_var_indexes
        self.class.strict_var_indexes
      end
     
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
            file_name =
              component_class.shadow_library_source_file.name[/.*(?=\.c$)/] +
              "_ContState"     ## a bit hacky
            shadow_library_file file_name
            component_class.shadow_library_include_file.include(
              shadow_library_include_file)
          end
          cl
        end

        # yields to block only if var was added
        def add_var var_name, kind
          var = vars[var_name]
          if var
            unless kind == :permissive or var.kind == kind
              raise StrictnessError,
                "\nVariable #{var_name} redefined with different strictness."
            end
          else
            var = vars[var_name] =
              ContVarDescriptor.new(var_name, vars.own.size, self, kind)
            shadow_attr var_name => "ContVar #{var_name}"
            yield if block_given?
          end
          var
        end

        def inherited_var_count
          unless @inherited_var_count
            raise Library::CommitError unless committed?
            @inherited_var_count = superclass.vars.size
          end
          @inherited_var_count
        end
        
        def cumulative_var_count
          unless @cumulative_var_count
            raise Library::CommitError unless committed?
            @cumulative_var_count = vars.size
            if @cumulative_var_count > 32767
              raise "overflow in cumulative_var_count: #{@cumulative_var_count}"
            end
          end
          @cumulative_var_count
        end
        
        def var_at_index(idx)
          @var_at_index ||= {}
          @var_at_index[idx] ||= vars.values.find {|var| var.index == idx}
        end

        def strict_var_indexes
          unless @strict_var_indexes
            raise Library::CommitError unless committed?
            @strict_var_indexes = vars.
              select {|name, var| var.strict?}.
              map {|name, var| var.index}
          end
          @strict_var_indexes
        end
      end
    end

    _load_data_method.post_code %{
      rb_funcall(shadow->self, #{library.declare_symbol :restore}, 0);
    }

    shadow_attr_accessor :cont_state   => [ContState]
    protected :cont_state, :cont_state=

    shadow_attr_accessor :state        => State
    protected :state=

    shadow_attr_reader :nonpersistent, :outgoing    => Array
    shadow_attr_reader :nonpersistent, :trans       => Transition
    shadow_attr_reader :nonpersistent, :dest        => State

    # The values of each event currently being emitted, indexed by event ID.
    # If not emitted, nil. We consider false to be an emitted value.
    shadow_attr_accessor :nonpersistent, :event_values      => Array
    shadow_attr_accessor :nonpersistent, :next_event_values => Array
    protected :event_values=, :next_event_values=

    def active_transition; trans; end # for introspection

    shadow_attr_accessor :var_count    => "short var_count"
      ## needn't be persistent
    protected :var_count=

    shadow_struct.declare :bits => %{\
      unsigned    strict    : 1; //# is cur state strict?
      unsigned    checked   : 1; //# have the guards been checked?
      unsigned    has_diff  : 1; //# cur state has diff flows?
      unsigned    diff_list : 1; //# on diff_list of comps with diff flows?
    }

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
      
      # Add a scratch variable of type double to the component's
      # shadow. Returns the var name. The scratch var is nonpersistent and
      # not accessible. The scratch var may be read/written by whatever flow
      # controls +var_name+; the value is preserved during the continuous step.
      def scratch_for var_name
        scratch_name = "#{var_name}_scratch"
        shadow_attr :nonpersistent, scratch_name => "double #{scratch_name}"
        scratch_name
      end

      def define_continuous(kind, var_names)
        var_names.collect do |var_name|
          var_name = var_name.intern if var_name.is_a? String
          
          cont_state_class.add_var var_name, kind do
            ssn = cont_state_class.shadow_struct.name
            exc = shadow_library.declare_class(AlgebraicAssignmentError)
            msg = "Cannot set #{var_name}; it is defined algebraically."

            class_eval %{
              define_c_method :#{var_name} do
                declare :cont_state => "#{ssn} *cont_state"
                declare :var        => "ContVar *var"
                body %{
                  cont_state = (#{ssn} *)shadow->cont_state;
                  var = &cont_state->#{var_name};
                  if (var->algebraic &&
                      (var->strict ? !var->d_tick :
                       var->d_tick != shadow->world->d_tick)) {
                    (*var->flow)((ComponentShadow *)shadow);
                  }
                  else {
                    if (shadow->world)
                      var->d_tick = shadow->world->d_tick;
                  }
                }
                # The d_tick assign above is because we now know that the
                # current-ness of the value has been relied upon (possibly to
                # go to strict sleep), and so the ck_strict flag must be set
                # later, so strictness will get checked at the end of any
                # transitions (but only if someone has relied on it).
                
                returns "rb_float_new(cont_state->#{var_name}.value_0)"
              end
            }
            
            ## the .strict ? check can be done statically (but cost is
            ## recompile if strict decl changes).

            if kind == :strict
              exc2 = shadow_library.declare_class StrictnessError
              msg2 = "Cannot reset strictly continuous #{var_name} in #{self}."
              class_eval %{
                define_c_method :#{var_name}= do
                  arguments :value
                  declare :cont_state => "#{ssn} *cont_state"
                  body %{
                    cont_state = (#{ssn} *)shadow->cont_state;
                    cont_state->#{var_name}.value_0 = NUM2DBL(value);
                    if (shadow->world)
                      shadow->world->d_tick++;
                    if (cont_state->#{var_name}.algebraic)
                      rs_raise(#{exc}, shadow->self, #{msg.inspect});
                    if (!NIL_P(shadow->state))
                      rs_raise(#{exc2}, shadow->self, #{msg2.inspect});
                  }
                  returns "value"
                end
              }

            else
              class_eval %{
                define_c_method :#{var_name}= do
                  arguments :value
                  declare :cont_state => "#{ssn} *cont_state"
                  body %{
                    cont_state = (#{ssn} *)shadow->cont_state;
                    cont_state->#{var_name}.value_0 = NUM2DBL(value);
                    if (shadow->world) 
                      shadow->world->d_tick++;
                    if (cont_state->#{var_name}.algebraic)
                      rs_raise(#{exc}, shadow->self, #{msg.inspect});
                  }
                  returns "value"
                end
              }
            end
          end
        end
      end

      def define_constant(kind, var_names)
        var_names.collect do |var_name|
          var_name = var_name.intern if var_name.is_a? String
          add_var_to_offset_table(var_name)
          
          (r,w), = shadow_attr_accessor var_name => "double #{var_name}"
          w.body "if (shadow->world) shadow->world->d_tick++"

          if kind == :strict
            exc = shadow_library.declare_class StrictnessError
            msg = "Cannot reset strictly constant #{var_name} in #{self}."
            w.body %{
              if (!NIL_P(shadow->state))
                rs_raise(#{exc}, shadow->self, #{msg.inspect});
            }
          end
        end
      end
      
      def src_comp var_name
        "#{var_name}_src_comp"
      end

      def src_type var_name
        "#{var_name}_src_type"
      end
      
      def src_offset var_name
        "#{var_name}_src_offset"
      end
      
      def input_target_struct
        unless @input_target_struct
          sf = shadow_library_source_file
          st = @input_target_struct = sf.declare_extern_struct(:target)
          st.declare :psh    => "char    *psh"
          st.declare :type   => "short   type"
          st.declare :offset => "short   offset"
          ## will this always have the same layout as the struct members
          ## in ComponentShadow?
        end
      end
      
      def define_input(kind, var_names)
        Component.input_target_struct
        
        var_names.collect do |var_name|
          var_name = var_name.intern if var_name.is_a? String
          
          src_comp    = src_comp(var_name)
          src_type    = src_type(var_name)
          src_offset  = src_offset(var_name)
          
          add_var_to_offset_table(src_comp)

          ## readers only?
          shadow_attr_accessor src_comp   => [Component]
          shadow_attr_accessor src_type   => "short #{src_type}"
          shadow_attr_accessor src_offset => "short #{src_offset}"
          
          exc = shadow_library.declare_class UnconnectedInputError
          msg = "Input #{var_name.inspect} is not connected."
          
          exc_circ = shadow_library.declare_class CircularDefinitionError
          msg_circ = "Circularity in input variable #{var_name} " +
                "of class #{name}."

          define_c_method(var_name) do
            declare :value => "double           value"
            declare :tgt   => "struct target    *tgt"
            declare :sh    => "ComponentShadow  *sh"
            declare :depth => "int              depth"
            
            returns "rb_float_new(value)"
            
            body %{
              depth = 0;
              tgt = (struct target *)&shadow->#{src_comp};
            
            recurse:
              if (!tgt->psh || tgt->type == INPUT_NONE) {
                rs_raise(#{exc}, shadow->self, #{msg.inspect});
              }
              
              sh = (ComponentShadow *)tgt->psh;

              switch (tgt->type) {
              case INPUT_CONT_VAR: {
                ContVar *var = (ContVar *)&FIRST_CONT_VAR(sh);
                var += tgt->offset;
                
                if (var->algebraic &&
                    (var->strict ? !var->d_tick :
                     var->d_tick != sh->world->d_tick)) {
                  (*var->flow)(sh);
                }
                else {
                  if (sh->world)
                    var->d_tick = sh->world->d_tick;
                }
                value = var->value_0;
                break;
              }
                
              case INPUT_CONST:
                value = *(double *)(tgt->psh + tgt->offset);
                break;
                
              case INPUT_INP_VAR:
                tgt = (struct target *)(tgt->psh + tgt->offset);
                if (depth++ > 100) {
                  rs_raise(#{exc_circ}, shadow->self, #{msg_circ.inspect});
                }
                goto recurse;
              
              default:
                assert(0);
              }
            }
          end
        end
      end

      def precommit
        define_events
        define_links
        define_continuous_variables
        define_constant_variables
        define_input_variables

        states.values.sort_by{|s|s.to_s}.each do |state|
          define_flows(state)
          define_transitions(state)
        end

        check_variables
      end
    
      def define_events
        exported_events.own.each do |event, index|
          define_method event do
            event_values.at(index) ## is it worth doing this in C?
          end                      ## or at least use eval instead of closure
        end
      end
    
      def _offset_table
        {}
      end
      
      def offset_table
        @offset_table ||= _offset_table
      end
      
      def inv_offset_table
        @inv_offset_table ||= offset_table.invert
      end
      
      # Note: for constant and link vars. Offset is in bytes.
      def offset_of_var var_name
        offset_table[var_name.to_sym] or
          raise "#{var_name.inspect} is not a valid constant or link in #{self}"
      end
      
      # Note: for constant and link vars. Offset is in bytes.
      def var_at_offset offset
        inv_offset_table[offset] or
          raise "#{offset} is not a constant or link offset in #{self}"
      end
      
      def offset_table_method
        @offset_table_method ||= define_c_class_method :_offset_table do
            declare :table  => "VALUE table"
            returns "table"
            body %{
              table = rb_call_super(0, 0);
            }
          end
      end
      
      def add_var_to_offset_table var_name
        ssn = shadow_struct.name
        offset_table_method.body %{\
          rb_hash_aset(table, #{shadow_library.literal_symbol(var_name)},
            INT2FIX((char *)&(((struct #{ssn} *)0)->#{var_name}) - (char *)0));
        } ## can we just use offsetof() ?
      end

      def define_links
        own_links = link_variables.own
        return if own_links.empty?
        
        ssn = shadow_struct.name
        
        own_links.keys.sort_by{|k|k.to_s}.each do |var_name|
          var_type, strictness = link_variables[var_name]

          unless var_type.is_a? Class
            var_type = var_type.to_s.split(/::/).inject(self) do |p, n|
              p.const_get(n)
            end
            link_variables[var_name] = [var_type, strictness]
          end

          unless var_type <= Component
            raise TypeError,
            "Linked type must be a subclass of Component: #{var_name}"
          end

          (r,w), = shadow_attr_accessor(var_name => [var_type])
          w.body "if (shadow->world) shadow->world->d_tick++"

          if strictness == :strict
            exc = shadow_library.declare_class StrictnessError
            msg = "Cannot reset strict link #{var_name} in #{self}."
            w.body %{
              if (!NIL_P(shadow->state))
                rs_raise(#{exc}, shadow->self, #{msg.inspect});
            }
          end

          shadow_library_include_file.include(
            var_type.shadow_library_include_file)
          
          add_var_to_offset_table(var_name)
        end
      end
      
      def check_variables
        bad = constant_variables.keys & continuous_variables.keys
        unless bad.empty?
          raise ConstnessError,
            "In class #{self}, the following variables are " +
            "each defined as both constant and continuous: #{bad.join(", ")}."
        end
      end
      
      def define_continuous_variables
        continuous_variables.own.keys.sort_by{|k|k.to_s}.each do |var_name|
          define_continuous(continuous_variables[var_name], [var_name])
        end
      end
      
      def define_constant_variables
        constant_variables.own.keys.sort_by{|k|k.to_s}.each do |var_name|
          define_constant(constant_variables[var_name], [var_name])
        end
      end
      
      def define_input_variables
        input_variables.own.keys.sort_by{|k|k.to_s}.each do |var_name|
          define_input(input_variables[var_name], [var_name])
        end
      end
      
      def define_flows(state)
        own_flows = flows(state).own
        own_flows.keys.sort_by{|sym|sym.to_s}.each do |var|
          flow = own_flows[var]

          cont_var = cont_state_class.vars[var]
          unless cont_var
            attach_continuous_variables(:permissive, [var])
            cont_var = define_continuous(:permissive, [var])[0]
          end
          
          add_flow([state, cont_var] => flow.flow_wrapper(self, state))

          after_commit do
            ## a pity to use after_commit, when "just_before_commit" would be ok
            ## use the defer mechanism from teja2hsif
            if not flow.strict and cont_var.strict?
              raise StrictnessError,
                "Strict variable '#{cont_var.name}' in #{self} " +
                "redefined with non-strict flow.", []
            end
          end
        end
      end

      def define_guard(expr)
        @guard_wrapper_hash ||= {} ## could be a superhash?
        @guard_wrapper_hash[expr] ||=
          CexprGuard.new(expr).guard_wrapper(self)
      end

      def make_guard_method_name
        @guard_ids ||= 0
        @guard_ids += 1
        "__guard_method_impl__#{@guard_ids}".intern
      end

      def define_guards(guards)
        guards.map! do |g|
          case g
          when GuardPhaseItem, Symbol
            # already saw this guard, as in: transition [S, T] => U
            g
          
          when Proc
            if HAVE_DEFINE_METHOD
              meth = Component.make_guard_method_name
              class_eval do
                define_method(meth, &g)
              end
              ## Currently, methods defined with define_method are a little
              ## slower to invoke in ruby.
              meth
            else
              g # a proc is slower than a method when called from step_discrete
            end
          
          when Class
            if g < GuardWrapper
              g
            else
              raise "What is #{g.inspect}?"
            end

          when String
            define_guard(g)
          
          when Array
            var_name, event_name = g

            var_type, strictness = link_variables[var_name]
            event_idx = var_type.exported_events[event_name]
            
            unless event_idx
              raise "Can't find event #{event_name.inspect} in events of" +
                    " #{var_type}, linked from #{self} as #{var_name.inspect}."
            end

            item = GuardPhaseItem.new
            item.event_index = event_idx
            item.link = var_name
            item.event = event_name

            after_commit do
              item.link_offset = offset_of_var(var_name)
            end

            item

          else
            raise "What is #{g.inspect}?"
          end
        end
      end
      
      def define_reset(expr)
        @expr_wrapper_hash ||= {} ## could be a superhash?
        @expr_wrapper_hash[expr] ||=
          Expr.new(expr).wrapper(self)
      end
      
      def define_resets(phase)
        h = phase.value_map
        h.keys.sort_by{|k|k.to_s}.each do |var|
          expr = h[var]
          
          case
          when (cont_var = cont_state_class.vars[var])
            define_reset_continuous(cont_var, expr, (phase[0]||=[]))
          when constant_variables[var]
            define_reset_constant(var, expr, (phase[1]||=[]))
          when link_variables[var]
            define_reset_link(var, expr, (phase[2]||=[]))
          else
            raise "No such variable, #{var}"
          end
        end
      end
      
      def define_reset_continuous cont_var, expr, phase
        if cont_var.strict?
          raise StrictnessError,
            "Cannot reset strictly continuous '#{cont_var.name}' in #{self}.",
           []
        end

        case expr
        when String
          reset = define_reset(expr)

          after_commit do
            phase[cont_var.index] = reset.instance
          end
        
        when Numeric
          after_commit do
            phase[cont_var.index] = expr.to_f
          end

        else
          after_commit do
            phase[cont_var.index] = expr
          end
        end
      end
      
      def define_reset_constant var, expr, phase
        if constant_variables[var] == :strict
          raise StrictnessError,
            "Cannot reset strictly constant #{var} in #{self}.", []
        end
        
        case expr
        when String
          reset = define_reset(expr)

          after_commit do
            phase << [offset_of_var(var), reset.instance, var]
          end

        when Numeric
          after_commit do
            phase << [offset_of_var(var), expr.to_f, var]
          end

        else
          after_commit do
            phase << [offset_of_var(var), expr, var]
          end
        end
      end

      def define_reset_link var, expr, phase
        type, strictness = link_variables[var]
        if strictness == :strict
          raise StrictnessError,
            "Cannot reset strict link #{var} in #{self}.", []
        end
        
        case expr
        when String
          raise "Unimplemented" ## does this make sense?
          reset = define_reset(expr)

          after_commit do
            phase << [offset_of_var(var), reset.instance, var, type]
          end

        when Proc
          after_commit do
            phase << [offset_of_var(var), expr, var, type]
          end
        end
      end
      
      def define_event_phase phase
        phase.each do |item|
          case item.value
          when ExprEventValue
            wrapper_mod = define_reset(item.value)
            after_commit do
              item.value = wrapper_mod.instance
            end
          end
        end
      end

      def define_transitions(state)
        # transitions don't usually have names, so the following (insertion
        # order) is better than sorting by name.
        own_transitions(state).each do |trans, dst|
          define_guards(trans.guard) if trans.guard
          define_resets(trans.reset) if trans.reset
          define_event_phase(trans.event) if trans.event
        end
      end

    end

    define_c_method :init_flags do
      declare :locals => %{
        ContVar    *vars;
        long        var_count;
        VALUE       idx_ary;
        VALUE      *indexes;
        long        count;
        long        i;
        long        idx;
      }
      svi = declare_symbol :strict_var_indexes
        ## really only need to call this once (per class)
      body %{
        shadow->has_diff  = 0;
        shadow->diff_list = 0;

        vars = (ContVar *)&FIRST_CONT_VAR(shadow);
        var_count = shadow->var_count;

        idx_ary = rb_funcall(shadow->cont_state->self, #{svi}, 0);
        Check_Type(idx_ary, T_ARRAY); //## debug only

        count = RARRAY(idx_ary)->len;
        indexes = RARRAY(idx_ary)->ptr;
        
        for (i = 0; i < count; i++) {
          idx = NUM2INT(indexes[i]);
          if (idx > var_count-1)
            rs_raise(#{declare_class IndexError}, shadow->self,
                   "Index into continuous variable list out of range: %d > %d.",
                   idx, var_count-1);
          vars[idx].strict = 1;
        }
      }
    end
    
    ## optimizations:
    ##   class-level caching
    ##   define connect in C?
    ##   if need_connect...
    def connect input_variable, other_component, other_var
      src_comp    = self.class.src_comp(input_variable)
      src_type    = self.class.src_type(input_variable)
      src_offset  = self.class.src_offset(input_variable)

      ivs = self.class.input_variables
      unless ivs.key? input_variable
        raise TypeError, "Cannot connect non-input var: #{input_variable}."
      end
      
      strict = (ivs[input_variable] == :strict)
      connected_comp = send(src_comp)
      connected_var  = source_variable_for(input_variable)
      
      if strict and connected_comp and
          (connected_comp != other_component or
           connected_var.to_sym != other_var.to_sym)
        
        if other_component
          connected_val = connected_comp.send(connected_var)
          other_val = other_component.send(other_var)

          unless connected_val == other_val
            raise StrictnessError,
              "Cannot reconnect strict input: #{input_variable}."
          end
        
        else
          raise StrictnessError,
            "Cannot disconnect strict input: #{input_variable}."
        
        end
      end
      
      if other_var and other_component
        other_class = other_component.class
        
        case
        when other_class.continuous_variables.key?(other_var)
          other_strict = other_class.continuous_variables[other_var] == :strict
          
          type    = INPUT_CONT_VAR
          offset  = other_class.cont_state_class.vars.each {|v, desc|
            break desc.index if v.to_sym == other_var} ## table?

        when other_class.constant_variables.key?(other_var)
          other_strict = other_class.constant_variables[other_var] == :strict
          
          type    = INPUT_CONST
          offset  = other_class.offset_of_var(other_var)

        when other_class.input_variables.key?(other_var)
          other_strict = other_class.input_variables[other_var] == :strict

          type    = INPUT_INP_VAR
          offset  = other_class.offset_of_var(other_class.src_comp(other_var))

        else
          raise ArgumentError,
            "No such variable, #{other_var}, in #{other_class}."
        end
        
        if strict and not other_strict
          raise StrictnessError,
            "Cannot connect strict input, #{input_variable}, to non-strict " +
            "source: #{other_var} in #{other_component.class}."
        end

      else
        type    = INPUT_NONE
        offset  = 0
      end
      
      ## if this was in C, wouldn't need writer methods
      send("#{src_comp}=", other_component)
      send("#{src_type}=", type)
      send("#{src_offset}=", offset)
      
      ## if this was in C, wouldn't need bump_d_tick
      world.bump_d_tick
    end

    def source_component_for(input_variable)
      send(self.class.src_comp(input_variable))
    end
    
    def source_variable_for(input_variable)
      comp = send(self.class.src_comp(input_variable))
      type = send(self.class.src_type(input_variable))
      offset = send(self.class.src_offset(input_variable))
      
      case type
      when INPUT_CONT_VAR
        comp.class.cont_state_class.var_at_index(offset).name
      when INPUT_CONST
        comp.class.var_at_offset(offset)
      when INPUT_INP_VAR
        src_comp_basename = self.class.src_comp("").to_s
        varname = comp.class.var_at_offset(offset).to_s
        varname.gsub(src_comp_basename, "").intern
          ## hacky?
      else
        nil
      end
    end
    ## end # if need connect
    
    define_c_method :clear_ck_strict do
      declare :locals => %{
        ContVar    *vars;
        long        var_count;
        long        i;
      }
      body %{
        vars = (ContVar *)&FIRST_CONT_VAR(shadow);
        var_count = shadow->var_count;

        for (i = 0; i < var_count; i++) {
          vars[i].ck_strict = 0;
        }
      }
    end
    
    # Called by World#step_discrete.
    # Only for certain kinds of strictness errors.
    def handle_strictness_error var_idx, new_val, old_val
      var_name = cont_state.var_at_index(var_idx).name
      raise StrictnessError,
        "Transition violated strictness: var #{var_name}:" +
        " new value #{new_val} != #{old_val} in #{self.inspect}"
    end
    
    def self.cached_outgoing_transition_data s
      raise Library::CommitError if $REDSHIFT_DEBUG and not committed?
      @cached_outgoing_transition_data ||= {}
      @cached_outgoing_transition_data[s] ||= outgoing_transition_data(s)
    end
    
    def outgoing_transition_data
      self.class.cached_outgoing_transition_data state
    end

    define_c_method :update_cache do body "__update_cache(shadow)" end

    library.define(:__update_cache).instance_eval do
      flow_wrapper_type = Component::FlowWrapper.shadow_struct.name
      scope :extern ## might be better to keep static and put in world.c
      arguments "struct #{Component.shadow_struct.name} *shadow"
      declare :locals => %{
        #{flow_wrapper_type} *flow_wrapper;

        VALUE       flow_table;       //# Hash
        VALUE       flow_array;       //# Array
        VALUE       outgoing;
        long        var_count;
        ContVar    *vars;
        ContVar    *var;
        long        i;
        long        count;
        VALUE      *flows;
        VALUE       strict;
        int         has_diff;
      }.tabto(0)

      body %{
        var_count = shadow->var_count;
        vars = (ContVar *)&FIRST_CONT_VAR(shadow);

        //# Cache outgoing transitions.
        shadow->outgoing = rb_funcall(shadow->self,
                           #{declare_symbol :outgoing_transition_data}, 0);

        strict = rb_funcall(shadow->outgoing, #{declare_symbol :last}, 0);
        shadow->strict = RTEST(strict);

        //# Cache flows.
        flow_table = rb_funcall(rb_obj_class(shadow->self),
                     #{declare_symbol :flow_table}, 0);
          //## could use after_commit to cache this method call
        flow_array = rb_hash_aref(flow_table, shadow->state);
        has_diff = 0;

        if (flow_array != Qnil) {
          #{"Check_Type(flow_array, T_ARRAY);\n" if $REDSHIFT_DEBUG}
          count = RARRAY(flow_array)->len;
          flows = RARRAY(flow_array)->ptr;

          if (count > var_count)
            rs_raise(#{declare_class IndexError}, shadow->self,
                   "Index into continuous variable list out of range: %d > %d.",
                   count, var_count);

          for (i = 0; i < count; i++) {
            var = &vars[i];
            if (flows[i] != Qnil) {
              Data_Get_Struct(flows[i], #{flow_wrapper_type}, flow_wrapper);
              var->flow         = flow_wrapper->flow;
              var->algebraic    = flow_wrapper->algebraic;
              if (!var->algebraic)
                has_diff = 1;
              if (var->flow && var->algebraic && var->strict &&
                  var->d_tick > 0) { //# did anyone rely on the strictness?
                var->value_1    = var->value_0;
                var->ck_strict  = 1;
              }
              else {
                var->ck_strict  = 0;
              }
            }
            else {
              var->flow       = 0;
              var->algebraic  = 0;
              var->d_tick     = 0;
            }
          }
          
          for (; i < var_count; i++) {
            var = &vars[i];
            var->flow       = 0;
            var->algebraic  = 0;
            var->d_tick     = 0;
          }
        }
        else {
          for (i = 0; i < var_count; i++) {
            var = &vars[i];
            var->flow       = 0;
            var->algebraic  = 0;
            var->d_tick     = 0;
          }
        }
        
        if (has_diff && !shadow->has_diff) {
          if (!shadow->diff_list) {
            if (shadow->world->diff_list) { //# 0 if loading
              rb_ary_push(shadow->world->diff_list, shadow->self);
            }
            shadow->diff_list = 1;
          }
          shadow->has_diff = 1;
        }
        else if (!has_diff && shadow->has_diff) {
          //# defer taking comp off the diff_list
          shadow->has_diff = 0;
        }
      }
    end
    ## optimization: 
    ## if (var->flow != old_flow && ...)

    shadow_library_source_file.include "<stdarg.h>"
    shadow_library_source_file.define(:rs_raise).instance_eval do
      scope :extern
      arguments "VALUE exc, VALUE obj, const char *fmt, ..."
      return_type "void"
      body %{\
        va_list args;
        char buf[BUFSIZ];
        VALUE ex, ary;

        va_start(args, fmt);
        vsnprintf(buf, BUFSIZ, fmt, args);
        va_end(args);

        ary = rb_ary_new3(2, rb_str_new2(buf), obj);
        ex = rb_funcall(exc, #{declare_symbol :new}, 1, ary);
        rb_exc_raise(ex);\
      }
    end
  end
end
