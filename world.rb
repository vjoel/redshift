require 'option-block/option-block'
require 'pstore'
require 'redshift/component'
require 'enum/op'

module RedShift

class ZenoError < RuntimeError; end

class World
  include OptionBlock
  include Enumerable
  include CShadow; shadow_library Component
  
  attr_reader :components
  
# The indeterminacy of hash ordering causes the .c file to get written
# when not strictly necessary. Until deferred compile works, break
# the def up.
#  shadow_attr_accessor \
#    :curr_A => Array, :curr_R => Array, :curr_E => Array, :curr_G => Array,
#    :next_A => Array, :next_R => Array, :next_E => Array, :next_G => Array
  shadow_attr_accessor :curr_A => Array
  shadow_attr_accessor :curr_R => Array
  shadow_attr_accessor :curr_E => Array
  shadow_attr_accessor :curr_G => Array
  shadow_attr_accessor :next_A => Array
  shadow_attr_accessor :next_R => Array
  shadow_attr_accessor :next_E => Array
  shadow_attr_accessor :next_G => Array
  protected \
    :curr_A=, :curr_R=, :curr_E=, :curr_G=,
    :next_A=, :next_R=, :next_E=, :next_G=
  
  option_block_defaults \
    :name         =>  nil,
    :time_step    =>  0.1,
###    :zeno_limit   =>  -1, ## Infinity,
    :clock_start  =>  0.0,
    :clock_finish =>  Infinity
  
  @@count = 0

  attr_reader :step_count
  
  def started?; @started; end

  shadow_attr_writer   :time_step    => "double   time_step"
  shadow_attr_accessor :zeno_limit   => "long     zeno_limit"
  protected :time_step=
  ### what about dynamically changing time step?
  
  def self.new(*args, &block)
    unless Component.committed? or CLib.empty?
      Component.commit
      new(*args, &block)
    end
  end
  
  def initialize(&block)
    super ##??
    
    self.curr_A = []; self.curr_R = []; self.curr_E = []; self.curr_G = []
    self.next_A = []; self.next_R = []; self.next_E = []; self.next_G = []
    @components = EnumerableOperator.sum  \
      curr_A, curr_R, curr_E, curr_G,
      next_A, next_R, next_E, next_G

    @name           = options[:name] || "#{type} #{@@count}"
    self.time_step  = options[:time_step]
###    self.zeno_limit = options[:zeno_limit]
    self.zeno_limit = -1
    @clock_start    = options[:clock_start]
    @clock_finish   = options[:clock_finish]
    
    @step_count = 0
    
    @@count += 1

  end
  
  def do_setup
    type.do_setup self
    if @setup_procs
      for pr in @setup_procs
        instance_eval(&pr)
      end
    end
  end
  private :do_setup
  
  def self.do_setup instance
    superclass.do_setup instance if superclass.respond_to? :do_setup
    if @setup_procs
      for pr in @setup_procs
        instance.instance_eval(&pr)
      end
    end
  end

  def create(component_class, &block)
    c = component_class.new(self, &block)
    curr_G << c ## problem if occurs during guard?
    c
  end
  
##  def remove c
##    components.delete c
##  end
  
  def run(steps = 1)
  
    unless @started
      do_setup
      @started = true
    end
    
    step_discrete
    while (steps -= 1) >= 0 ## faster to use '(1..steps).each do' ?
      break if clock > @clock_finish
      @step_count += 1
      step_continuous
      step_discrete
      yield self if block_given?
    end
    
    self
  end

  define_method :step_continuous do
    declare :locals => %{
      VALUE             comp_rb_ary, *comp_ary;
      long              len;
      long              var_count;
      ContVar          *var, *end_var;
      long              ci;
      ComponentShadow  *comp_shdw;
    }.tabto(0)
    declare :step_continuous_subs => %{
      inline ComponentShadow *get_shadow(VALUE comp)
      {
        return (ComponentShadow *)DATA_PTR(comp);
      }
    } ## get_shadow is same as below -- make it a static fn
    body %{
      time_step = shadow->time_step;    //# assign global
      comp_rb_ary = shadow->curr_G;

      len = RARRAY(comp_rb_ary)->len;
      comp_ary = RARRAY(comp_rb_ary)->ptr;
      
      for (rk_level = 0; rk_level <= 4; rk_level++) { //# assign global
        for (ci = 0; ci < len; ci++) {
          Data_Get_Struct(comp_ary[ci], ComponentShadow, comp_shdw);
          var_count = comp_shdw->type_data->var_count;
          var = (ContVar *)(&comp_shdw->cont_state->begin_vars);
          end_var = &var[var_count];

          while (var < end_var) {
            if (rk_level == 0) {
              var->rk_level = 0;
              if (!var->flow)
                var->value_1 = var->value_2 = var->value_3 = var->value_0;
            }
            else {
              if (var->flow &&
                  var->rk_level < rk_level &&
                  !var->algebraic)
                (*var->flow)(comp_shdw);
              if (rk_level == 4)
                var->d_tick = 0;      //# for next step_discrete
            }
            var++;
          }
        }
      }
      d_tick = 1; //# alg flows need to be recalculated
      rk_level = 0;
    } ## assumed that comp_ary[i] was a Component
  end
  private :step_continuous

  define_method :step_discrete do ##:discrete_update do
    c_array_args {  ## performance cost? DEBUG only?
      optional :step_count
      default :step_count => "INT2FIX(-1)"
    }
    declare :locals => %{
      VALUE             comp;
      ComponentShadow  *comp_shdw;
      VALUE            *ptr;
      long              len;
      long              i;
      long              sc;
      long              all_were_g, all_are_g;
      long              zeno_counter;
      long              zeno_limit;
      static VALUE      ExitState, GuardWrapperClass;
      static VALUE      ActionClass, ResetClass, EventClass, GuardClass;
    }.tabto(0)
    insteval_proc = declare_symbol :insteval_proc
    test_event    = declare_symbol :test_event
    declare :step_discrete_subs => %{
      inline ComponentShadow *get_shadow(VALUE comp)
      { //## assert type check?
        return (ComponentShadow *)DATA_PTR(comp);
      }
      inline VALUE cur_actions(ComponentShadow *comp_shdw)
      {
        VALUE actions = RARRAY(comp_shdw->phases)->ptr[comp_shdw->cur_ph];
        assert(RBASIC(actions)->klass == ActionClass);
        return actions;
      }
      inline VALUE cur_resets(ComponentShadow *comp_shdw)
      {
        VALUE resets = RARRAY(comp_shdw->phases)->ptr[comp_shdw->cur_ph];
        assert(RBASIC(resets)->klass == ResetClass);
        return resets;
      }
      inline VALUE cur_events(ComponentShadow *comp_shdw)
      {
        VALUE events = RARRAY(comp_shdw->phases)->ptr[comp_shdw->cur_ph];
        assert(RBASIC(events)->klass == EventClass);
        return events;
      }
      inline void move_comp(VALUE comp, VALUE list, VALUE next_list)
      {
        struct RArray *nl = RARRAY(next_list);
        if (nl->len == nl->capa)
          rb_ary_store(next_list, nl->len, comp);
        else
          nl->ptr[nl->len++] = comp;
        --RARRAY(list)->len;
      }
      inline void remove_comp(VALUE comp, VALUE list)
      {
        ComponentShadow *comp_shdw = get_shadow(comp);
        assert(comp_shdw->world == shadow->self);
        comp_shdw->world = Qnil;
        --RARRAY(list)->len;
      }
      inline int test_cexpr_guard(VALUE comp, VALUE guard)
      {
        int (*fn)(ComponentShadow *), rslt;
        assert(RTEST(rb_obj_is_kind_of(guard, GuardWrapperClass)));
        fn = ((#{RedShift::Component::GuardWrapper.shadow_struct.name} *)
               get_shadow(guard))->guard;
        rslt = (*fn)(get_shadow(comp));
        return rslt;
      }
      inline int test_event_guard(VALUE comp, VALUE guard)
      {
        VALUE link  = RARRAY(guard)->ptr[0];
        VALUE event = RARRAY(guard)->ptr[1];
        return RTEST(rb_funcall(comp, #{test_event}, 2, link, event));
      }
      inline int guard_enabled(VALUE comp, VALUE guards)
      {
        int i;
        assert(BUILTIN_TYPE(guards) == T_ARRAY);
        for (i = 0; i < RARRAY(guards)->len; i++) {
          VALUE guard = RARRAY(guards)->ptr[i];

          switch (BUILTIN_TYPE(guard)) {
          case T_DATA:
            if (RBASIC(guard)->klass == rb_cProc) {
              if (!RTEST(rb_funcall(comp, #{insteval_proc}, 1, guard)))
                return 0;   //### faster way to call instance_eval ???
            }
            else {
              assert(!RTEST(rb_obj_is_kind_of(guard, rb_cProc)));
              if (!test_cexpr_guard(comp, guard))
                return 0;
            }
            break;
          case T_ARRAY:
            assert(RARRAY(guard)->len == 2); //## Future: allow 3: [l,e,value]
            if (!zeno_counter || !test_event_guard(comp, guard))
              return 0; //## should use different var than zeno_counter
            break;
          case T_CLASS:
            assert(RTEST(rb_mod_lt(guard, GuardWrapperClass)));
            guard = rb_funcall(guard, #{declare_symbol :instance}, 0);
            RARRAY(guards)->ptr[i] = guard;
            if (!test_cexpr_guard(comp, guard))
              return 0;
            break;
          default:
            assert(0);
          }
        }
        return 1;
      }
      inline void start_trans(ComponentShadow  *comp_shdw,
                              VALUE trans, VALUE dest, VALUE phases)
      {
        comp_shdw->trans  = trans;
        comp_shdw->dest   = dest;
        comp_shdw->phases = phases;
        comp_shdw->cur_ph = -1;
      }
      inline void finish_trans(ComponentShadow  *comp_shdw)
      { //## should this be deferred to end of step? (in case alg flow
        //## changes discretely)
        if (comp_shdw->state != comp_shdw->dest) {
          comp_shdw->state = comp_shdw->dest;
          __update_cache(comp_shdw);
        }
        else
          comp_shdw->state = comp_shdw->dest;
        comp_shdw->trans  = Qnil;
        comp_shdw->dest   = Qnil;
        comp_shdw->phases = Qnil;
      }
      inline void enter_next_phase(VALUE comp, VALUE list)
      {
        ComponentShadow *comp_shdw = get_shadow(comp);
        struct RArray *phases = RARRAY(comp_shdw->phases);
        if (RTEST(phases)) {
          if (++comp_shdw->cur_ph < phases->len) {
            VALUE klass = RBASIC(phases->ptr[comp_shdw->cur_ph])->klass;
            if (klass == ActionClass)
              move_comp(comp, list, shadow->next_A);
            else if (klass == ResetClass)
              move_comp(comp, list, shadow->next_R);
            else if (klass == EventClass)
              move_comp(comp, list, shadow->next_E);
            else
              rb_raise(#{declare_class ScriptError},
                "\\nBad phase type.\\n");
          }
          else {
            if (comp_shdw->dest == ExitState)
              remove_comp(comp, list);
            else
              move_comp(comp, list, shadow->next_G);
            finish_trans(comp_shdw);
          }
        }
        else
          move_comp(comp, list, shadow->next_G);
      }
    }.tabto(0)
    declare :step_discrete_macros => '
      #define SWAP_VALUE(v, w) {VALUE ___tmp = v; v = w; w = ___tmp;}
      #define EACH_COMP(lc)                             \\
      for (list = RARRAY(lc);                           \\
           list->len ? (                                \\
             comp = list->ptr[list->len - 1],           \\
             comp_shdw = get_shadow(comp),              \\
             1)                                         \\
             : 0;                                       \\
           enter_next_phase(comp, lc))
      int dummy;
    '.tabto(0)
    comp_id = declare_class RedShift::Component
    init %{
      ExitState     = rb_const_get(#{comp_id}, #{declare_symbol :Exit});
      ActionClass   = rb_const_get(#{comp_id}, #{declare_symbol :Action});
      ResetClass    = rb_const_get(#{comp_id}, #{declare_symbol :Reset});
      EventClass    = rb_const_get(#{comp_id}, #{declare_symbol :Event});
      GuardClass    = rb_const_get(#{comp_id}, #{declare_symbol :Guard});
      GuardWrapperClass
                    = rb_const_get(#{comp_id}, #{declare_symbol :GuardWrapper});
    }
    body %{
      all_were_g = 1;
      zeno_counter = 0;
      zeno_limit = shadow->zeno_limit;
      sc = NUM2INT(step_count);
      
      while (sc-- != 0) {
        struct RArray *list;

        //# GUARD phase. Start on phase 4 of 4, because everything's in G.
        EACH_COMP(shadow->curr_G) {
          len = RARRAY(comp_shdw->outgoing)->len;
          ptr = RARRAY(comp_shdw->outgoing)->ptr;
          //# outgoing = [ trans, guard, [action, reset, event, ...], dest, ...]
          
          while (len) {
            VALUE trans, guard, phases, dest;
            assert(len >= 4);
            
            guard = ptr[--len];
            
            if (!RTEST(guard) || guard_enabled(comp, guard)) {
              phases  = ptr[--len];
              dest    = ptr[--len];
              trans   = ptr[--len];
              start_trans(comp_shdw, trans, dest, phases);
              all_were_g = 0;
              break;
            }
            else
              len -= 3;
          }
        }

        //# Step finished; prepare lists for next 4-phase step.
        SWAP_VALUE(shadow->curr_A, shadow->next_A);
        SWAP_VALUE(shadow->curr_R, shadow->next_R);
        SWAP_VALUE(shadow->curr_E, shadow->next_E);
        SWAP_VALUE(shadow->curr_G, shadow->next_G);
        
        //# Done stepping if no transitions happened or are about to begin.
        all_are_g = !RARRAY(shadow->curr_A)->len &&
                    !RARRAY(shadow->curr_R)->len &&
                    !RARRAY(shadow->curr_E)->len;
        if (all_were_g && all_are_g)
          break;
        all_were_g = all_are_g;
        
        //# Check for zeno problem.
        zeno_counter++;
        if (2 * zeno_counter > zeno_limit && zeno_limit >= 0)
          if (zeno_counter > zeno_limit)
            rb_raise(#{declare_class RedShift::ZenoError},
                     "\\nExceeded zeno limit of %d.\\n", zeno_limit);
          else
            rb_funcall(shadow->self, #{declare_symbol :step_zeno},
                       1, INT2NUM(zeno_counter));
        
        //# Begin a new step, starting with ACTION phase
        EACH_COMP(shadow->curr_A) {
          VALUE actions = cur_actions(comp_shdw);
          
          for (i = 0; i < RARRAY(actions)->len; i++) {
            rb_funcall(comp, #{insteval_proc}, 1, RARRAY(actions)->ptr[i]);
//#            rb_obj_instance_eval(1, &RARRAY(actions)->ptr[i], comp);
            d_tick++;   //# each action may invalidate algebraic flows
            //## should set flag so that alg flows always update during action
          }
        }
        
        //# RESET phase
        EACH_COMP(shadow->curr_R) {
          VALUE resets = cur_resets(comp_shdw);
          rb_funcall(comp, #{declare_symbol :do_resets}, 1, resets);
        }
        d_tick++;   //# resets may (in parallel) invalidate algebraic flows
        //## optimization: don't incr if no resets? Change name of d_tick!
        
        //# EVENT phase
        EACH_COMP(shadow->curr_E) {
          VALUE events = cur_events(comp_shdw);
          rb_funcall(comp, #{declare_symbol :do_events}, 1, events);
        } 
      }
    }
  end
  private :step_discrete
  
  def step_zeno zeno_counter
    puts "Zeno step: #{zeno_counter} / #{zeno_limit}"
    ## print out the active components and their transitions if $DEBUG_ZENO?
  end
  
  ## move to C
  def clock
    @step_count * time_step + @clock_start
  end
  
  
###  def garbage_collect
###    self.components.clear
###    GC.start
###    ObjectSpace.each_object(Component) do |c|
###      if c.world == self
###        components << c
###      end
###    end
###  end
## another thing we can do: compress the various component arrays
  
  def each(&b)
    @components.each(&b)
  end
  
  def size
    @components.size
  end
  
  def include? component
    component.world == self
  end
  alias member? include?
  
  def inspect
    if @started
      sprintf "<%s: %d step%s, %s second%s, %d component%s>",
        @name,
        @step_count, ("s" if @step_count != 1),
        clock, ("s" if clock != 1),
        size, ("s" if size != 1)
    else
      sprintf "<%s: not started. Do 'run 0' to setup, or 'run n' to run.>",
        @name
    end
  end
  
  
  def save filename = @name
    each { |c|
      c.instance_eval {
        @trans_cache_state = nil
        @cache_transitions = nil
      }
    } ## can get rid of this after moving discrete behavior into C code
    File.delete filename rescue SystemCallError
    store = PStore.new filename
    store.transaction do
      store['world'] = self
      yield store if block_given?
    end
  end
  
  
  def World.open filename
    world = nil
    store = PStore.new filename
    store.transaction do
      if store.root? 'world'
        world = store['world']
        yield store if block_given?
      end
    end
    if world
      world.each { |c| c.restore }
    end
    world
  end
  
end # class World

end # module RedShift
