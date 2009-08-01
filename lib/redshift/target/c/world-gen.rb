module RedShift

class World
  include CShadow
  shadow_library RedShift.library
  shadow_library_file "World"
  shadow_library_source_file.include(Component.shadow_library_include_file)

  shadow_library_include_file.declare :cv_cache_entry => %{
    typedef struct {
      double *dbl_ptr;
      double value;
    } CVCacheEntry;
  }
  
  shadow_library_include_file.declare :link_cache_entry => %{
    typedef struct {
      ComponentShadow **link_ptr;
      VALUE           value;
    } LinkCacheEntry;
  }
  
  # Initial size for the constant value cache.
  CV_CACHE_SIZE = 64

  # Initial size for the link cache.
  LINK_CACHE_SIZE = 64
  
  World.subclasses.each do |sub|
    file_name = CGenerator.make_c_name(sub.name).to_s
    sub.shadow_library_file file_name
  end

  shadow_attr_accessor :curr_P => Array
  shadow_attr_accessor :curr_E => Array
  shadow_attr_accessor :curr_R => Array
  shadow_attr_accessor :curr_G => Array
  shadow_attr_accessor :next_P => Array
  shadow_attr_accessor :next_E => Array
  shadow_attr_accessor :next_R => Array
  shadow_attr_accessor :next_G => Array
  shadow_attr_accessor :active_E => Array
  shadow_attr_accessor :prev_active_E => Array
  shadow_attr_accessor :strict_sleep => Array
  shadow_attr_accessor :finishers => Array
  shadow_attr_accessor :inert => Array
  protected \
    :curr_P=, :curr_E=, :curr_R=, :curr_G=,
    :next_P=, :next_E=, :next_R=, :next_G=,
    :active_E=, :prev_active_E=, :strict_sleep=,
    :finishers=, :inert=
  
  shadow_attr_accessor :time_step    => "double   time_step"
  shadow_attr_accessor :zeno_limit   => "long     zeno_limit"
  shadow_attr_accessor :step_count   => "long     step_count"
  shadow_attr_accessor :clock_start  => "double   clock_start"
  shadow_attr_accessor :clock_finish => "double   clock_finish"
  shadow_attr_accessor :zeno_counter => "long     zeno_counter"
  
  shadow_attr_reader   :discrete_step   => "long  discrete_step"
  shadow_attr_reader   :discrete_phase  => Symbol

  shadow_struct.declare :constant_value_cache => %{
    CVCacheEntry *constant_value_cache;
    int cv_cache_size;
    int cv_cache_used;
  }
  new_method.attr_code %{
    shadow->constant_value_cache = 0;
    shadow->cv_cache_size = 0;
    shadow->cv_cache_used = 0;
  }
  free_function.free "free(shadow->constant_value_cache)"
  
  shadow_struct.declare :link_cache => %{
    LinkCacheEntry *link_cache;
    int link_cache_size;
    int link_cache_used;
  }
  new_method.attr_code %{
    shadow->link_cache = 0;
    shadow->link_cache_size = 0;
    shadow->link_cache_used = 0;
  }
  free_function.free "free(shadow->link_cache)"
  
  class << self
    # Redefines World#new so that a library commit happens first.
    def new(*args, &block)
      commit              # redefines World.new  
      new(*args, &block)  # which is what this line calls
    end

    alias generic_open open
    def open(*args, &block)
      commit              # defines World.alloc methods
      generic_open(*args, &block)
    end
  end
  
  define_c_method :clock do
    ## This is wrong if time_step changes.
    returns %{
      rb_float_new(shadow->step_count * shadow->time_step + shadow->clock_start)
    }
  end
  
  slif = shadow_library_include_file
  slif.declare :get_shadow => %{
    inline static ComponentShadow *get_shadow(VALUE comp)
    {
      assert(RTEST(rb_obj_is_kind_of(comp, #{slif.declare_module CShadow})));
      return (ComponentShadow *)DATA_PTR(comp);
    }
  }

  define_c_method :step_continuous do
    declare :locals => %{
      VALUE             comp_rb_ary[2], *comp_ary;
      long              len;
      long              var_count;
      ContVar          *var, *end_var;
      long              li, ci;
      ComponentShadow  *comp_shdw;
    }.tabto(0)
    body %{
      time_step = shadow->time_step;    //# assign global
      comp_rb_ary[0] = shadow->curr_G;
      comp_rb_ary[1] = shadow->inert;
      
      for (rk_level = 0; rk_level <= 4; rk_level++) { //# assign global
        for (li = 0; li < 2; li++) {
          len = RARRAY(comp_rb_ary[li])->len;
          comp_ary = RARRAY(comp_rb_ary[li])->ptr;
          for (ci = 0; ci < len; ci++) {
            Data_Get_Struct(comp_ary[ci], ComponentShadow, comp_shdw);
            var_count = comp_shdw->var_count;
            var = (ContVar *)(&FIRST_CONT_VAR(comp_shdw));
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
                  (*var->flow)((ComponentShadow *)comp_shdw);
                if (rk_level == 4) {
                  if (var->rk_level == 4)
                    var->d_tick = 1; //# var will be current in discrete_step
                  else
                    var->d_tick = 0; //# var (if alg) will need to be evaled
                }
              }
              var++;
            }
          }
        }
      }
      d_tick = 1; //# alg flows need to be recalculated
      rk_level = 0;
    } # assumed that comp_ary[i] was a Component--enforced by World#create
  end
  private :step_continuous

## define_c_function :my_instance_eval do
#  shadow_library_source_file.define(:my_instance_eval).instance_eval do
#    arguments "VALUE comp"
#    return_type "VALUE"
#    scope :static
#    returns "rb_obj_instance_eval(0, 0, comp)"
#  end
#  
#  shadow_library_source_file.define(:call_block).instance_eval do
#    arguments "VALUE arg1", "VALUE block"
#    return_type "VALUE"
#    scope :static
#    returns "rb_funcall(block, #{declare_symbol :call}, 0)"
#  end
  
  discrete_step_definer = proc do
    parent.declare :static_locals => %{
      static VALUE      ExitState, GuardWrapperClass, ExprWrapperClass;
      static VALUE      ProcClass, EventClass, ResetClass, GuardClass;
      static VALUE      DynamicEventClass;
      static VALUE      guard_phase_sym, proc_phase_sym;
      static VALUE      event_phase_sym, reset_phase_sym;
    }.tabto(0)
    
    declare :locals => %{
      VALUE             comp;
      ComponentShadow  *comp_shdw;
      VALUE            *ptr;
      long              len;
      long              i;
      long              all_were_g, all_are_g;
      int               started_events;
    }.tabto(0)
    
    insteval_proc = declare_symbol :insteval_proc
    capa = RUBY_VERSION.to_f >= 1.7 ? "aux.capa" : "capa"
    gpi = Component::GuardPhaseItem
    epi = Component::EventPhaseItem
    
    parent.declare :step_discrete_subs => %{
      inline static VALUE cur_procs(ComponentShadow *comp_shdw)
      {
        VALUE procs = RARRAY(comp_shdw->phases)->ptr[comp_shdw->cur_ph];
        assert(RBASIC(procs)->klass == ProcClass);
        return procs;
      }
      inline static VALUE cur_events(ComponentShadow *comp_shdw)
      {
        VALUE events = RARRAY(comp_shdw->phases)->ptr[comp_shdw->cur_ph];
        assert(RBASIC(events)->klass == EventClass);
        return events;
      }
      inline static VALUE cur_resets(ComponentShadow *comp_shdw)
      {
        VALUE resets = RARRAY(comp_shdw->phases)->ptr[comp_shdw->cur_ph];
        assert(RBASIC(resets)->klass == ResetClass);
        return resets;
      }
      inline static void move_comp(VALUE comp, VALUE list, VALUE next_list)
      {
        struct RArray *nl = RARRAY(next_list);
        assert(RARRAY(list)->ptr[RARRAY(list)->len-1] == comp);
        if (nl->len == nl->#{capa})
          rb_ary_store(next_list, nl->len, comp);
        else
          nl->ptr[nl->len++] = comp;
        --RARRAY(list)->len;
      }
      inline static void move_all_comps(VALUE list, VALUE next_list)
      { //## this could be faster using memcpy
        struct RArray *l = RARRAY(list);
        while (l->len)
          move_comp(l->ptr[l->len-1], list, next_list);
      }
      inline static void remove_comp(VALUE comp, VALUE list,
                                   #{World.shadow_struct.name} *shadow)
      {
        ComponentShadow *comp_shdw = get_shadow(comp);
        assert(RARRAY(list)->ptr[RARRAY(list)->len-1] == comp);
        assert(comp_shdw->world == shadow->self);
        comp_shdw->world = Qnil;
        --RARRAY(list)->len;
      }
      inline static double eval_expr(VALUE comp, VALUE expr)
      {
        double (*fn)(ComponentShadow *), rslt;
        assert(rb_obj_is_kind_of(expr, ExprWrapperClass));
        fn = ((#{RedShift::Component::ExprWrapper.shadow_struct.name} *)
               get_shadow(expr))->expr;
        rslt = (*fn)(get_shadow(comp));
        return rslt;
      }
      inline static int test_cexpr_guard(VALUE comp, VALUE guard)
      {
        int (*fn)(ComponentShadow *), rslt;
        assert(rb_obj_is_kind_of(guard, GuardWrapperClass));
        fn = ((#{RedShift::Component::GuardWrapper.shadow_struct.name} *)
               get_shadow(guard))->guard;
        rslt = (*fn)(get_shadow(comp));
        return rslt;
      }
      inline static int test_event_guard(VALUE comp, VALUE guard)
      {
        VALUE link  = RARRAY(guard)->ptr[#{gpi::LINK_OFFSET_IDX}];
        VALUE event = RARRAY(guard)->ptr[#{gpi::EVENT_INDEX_IDX}];
        int link_offset = FIX2INT(link);
        int event_idx = FIX2INT(event);
        ComponentShadow *comp_shdw = get_shadow(comp);
        ComponentShadow **link_shdw =
          (ComponentShadow **)(((char *)comp_shdw) + link_offset);
        VALUE event_value = *link_shdw ? 
          RARRAY((*link_shdw)->event_values)->ptr[event_idx] : Qnil;

        return event_value != Qnil; //# Qfalse is a valid event value.
      }
      inline static int guard_enabled(VALUE comp, VALUE guards,
                                      int started_events)
      {
        int i;
        assert(BUILTIN_TYPE(guards) == T_ARRAY);
        for (i = 0; i < RARRAY(guards)->len; i++) {
          VALUE guard = RARRAY(guards)->ptr[i];

          if (SYMBOL_P(guard)) {
            if (!RTEST(rb_funcall(comp, SYM2ID(guard), 0)))
              return 0;
          }
          else {
            switch (BUILTIN_TYPE(guard)) {
            case T_DATA:
              if (RBASIC(guard)->klass == rb_cProc) {
                if (!RTEST(rb_funcall(comp, #{insteval_proc}, 1, guard)))
                  return 0;   //## faster way to call instance_eval ???
              }
              else {
                assert(!rb_obj_is_kind_of(guard, rb_cProc));
                if (!test_cexpr_guard(comp, guard))
                  return 0;
              }
              break;

            case T_ARRAY:
              if (!started_events || !test_event_guard(comp, guard))
                return 0;
              break;

            case T_CLASS:
              assert(RTEST(rb_funcall(guard, #{declare_symbol "<"},
                1, GuardWrapperClass)));
              guard = rb_funcall(guard, #{declare_symbol :instance}, 0);
              RARRAY(guards)->ptr[i] = guard;
              if (!test_cexpr_guard(comp, guard))
                return 0;
              break;

            default:
              assert(0);
            }
          }
        }
        return 1;
      }
      inline static void update_all_alg_vars(ComponentShadow *comp_shdw)
      {
        ContVar    *vars = (ContVar *)&FIRST_CONT_VAR(comp_shdw);
        long        count = comp_shdw->var_count;
        long        i;
        for(i = 0; i < count; i++) {
          ContVar *var = &vars[i];
          if (var->algebraic &&
              (var->strict ? var->d_tick == 0 : var->d_tick != d_tick)) {
            var->flow(comp_shdw);
          }
        }
      }
      inline static void start_trans(ComponentShadow *comp_shdw,
                              #{World.shadow_struct.name} *shadow,
                              VALUE trans, VALUE dest, VALUE phases)
      {
        comp_shdw->trans  = trans;
        comp_shdw->dest   = dest;
        comp_shdw->phases = phases;
        comp_shdw->cur_ph = -1;
        //%% hook_start_transition(comp_shdw->self, trans, dest);
      }
      inline static void finish_trans(ComponentShadow *comp_shdw,
                               #{World.shadow_struct.name} *shadow)
      { //%% hook_finish_transition(comp_shdw->self, comp_shdw->trans,
        //%%                        comp_shdw->dest);
        if (comp_shdw->state != comp_shdw->dest) {
          update_all_alg_vars(comp_shdw);
          comp_shdw->state = comp_shdw->dest;
          __update_cache(comp_shdw);
        }
        comp_shdw->trans  = Qnil;
        comp_shdw->dest   = Qnil;
        comp_shdw->phases = Qnil;
        comp_shdw->checked = 0;
      }
      inline static void check_strict(ComponentShadow *comp_shdw)
      {
        ContVar    *vars = (ContVar *)&FIRST_CONT_VAR(comp_shdw);
        long        count = comp_shdw->var_count;
        long        i;
        for(i = 0; i < count; i++) {
          ContVar *var = &vars[i];
          if (var->ck_strict) {
            var->ck_strict = 0;
            (*var->flow)(comp_shdw);
            if (var->value_0 != var->value_1) {
              rb_funcall(comp_shdw->self,
                #{declare_symbol :handle_strictness_error}, 3, INT2NUM(i),
                rb_float_new(var->value_0), rb_float_new(var->value_1));
            }
          }
        }
      }
      inline static void enter_next_phase(VALUE comp, VALUE list,
                                   #{World.shadow_struct.name} *shadow)
      {
        ComponentShadow *comp_shdw = get_shadow(comp);
        struct RArray *phases = RARRAY(comp_shdw->phases);
        if (RTEST(phases)) {
          if (++comp_shdw->cur_ph < phases->len) {
            VALUE klass = RBASIC(phases->ptr[comp_shdw->cur_ph])->klass;
            if (klass == ProcClass)
              move_comp(comp, list, shadow->next_P);
            else if (klass == EventClass)
              move_comp(comp, list, shadow->next_E);
            else if (klass == ResetClass)
              move_comp(comp, list, shadow->next_R);
            else
              rb_raise(#{declare_class ScriptError}, "Bad phase type.");
          }
          else {
            if (comp_shdw->dest == ExitState)
              remove_comp(comp, list, shadow);
            else
              move_comp(comp, list, shadow->next_G);
            rb_ary_push(shadow->finishers, comp); //## optimize
          }
        }
        else {
          if (RARRAY(comp_shdw->outgoing)->len <= 1) //## strict flag
            move_comp(comp, list, shadow->inert);
          else if (comp_shdw->strict)
            move_comp(comp, list, shadow->strict_sleep);
          else
            move_comp(comp, list, shadow->next_G);
         
        }
      }
      
      static void cache_new_constant_value(
        double *dbl_ptr, double value,
               #{World.shadow_struct.name} *shadow)
      {
        CVCacheEntry *entry;
        
        if (!shadow->constant_value_cache) {
          int n = #{CV_CACHE_SIZE};
          shadow->constant_value_cache = malloc(n*sizeof(CVCacheEntry));
          shadow->cv_cache_size = n;
          shadow->cv_cache_used = 0;
        }
        if (shadow->cv_cache_used == shadow->cv_cache_size) {
          int n_bytes;
          shadow->cv_cache_size *= 2;
          n_bytes = shadow->cv_cache_size*sizeof(CVCacheEntry);
          shadow->constant_value_cache = realloc(
            shadow->constant_value_cache, n_bytes);
          if (!shadow->constant_value_cache) {
            rb_raise(#{declare_class NoMemoryError},
                "Out of memory trying to allocate %d bytes for CV cache.",
                n_bytes);
          }
        }
        entry = &shadow->constant_value_cache[shadow->cv_cache_used];
        entry->dbl_ptr = dbl_ptr;
        entry->value = value;
        shadow->cv_cache_used += 1;
      }
      static void assign_new_constant_values(
        #{World.shadow_struct.name} *shadow)
      {
        if (shadow->cv_cache_used) {
          int i;
          CVCacheEntry *entry;

          entry = shadow->constant_value_cache;
          for (i = shadow->cv_cache_used; i > 0; i--, entry++) {
            *entry->dbl_ptr = entry->value;
          }
          shadow->cv_cache_used = 0;
        }
      }
      
      static void cache_new_link(
        ComponentShadow **link_ptr, VALUE value,
               #{World.shadow_struct.name} *shadow)
      {
        LinkCacheEntry *entry;
        
        if (!shadow->link_cache) {
          int n = #{LINK_CACHE_SIZE};
          shadow->link_cache = malloc(n*sizeof(LinkCacheEntry));
          shadow->link_cache_size = n;
          shadow->link_cache_used = 0;
        }
        if (shadow->link_cache_used == shadow->link_cache_size) {
          int n_bytes;
          shadow->link_cache_size *= 2;
          n_bytes = shadow->link_cache_size*sizeof(LinkCacheEntry);
          shadow->link_cache = realloc(shadow->link_cache, n_bytes);
          if (!shadow->link_cache) {
            rb_raise(#{declare_class NoMemoryError},
                "Out of memory trying to allocate %d bytes for link cache.",
                n_bytes);
          }
        }
        entry = &shadow->link_cache[shadow->link_cache_used];
        entry->link_ptr = link_ptr;
        entry->value = value;
        shadow->link_cache_used += 1;
      }
      static void assign_new_links(
        #{World.shadow_struct.name} *shadow)
      {
        if (shadow->link_cache_used) {
          int i;
          LinkCacheEntry *entry;

          entry = shadow->link_cache;
          for (i = shadow->link_cache_used; i > 0; i--, entry++) {
            ComponentShadow *comp_shdw;
            if (NIL_P(entry->value))
              comp_shdw = 0;
            else
              comp_shdw = get_shadow(entry->value);
            *entry->link_ptr = comp_shdw;
          }
          shadow->link_cache_used = 0;
        }
      }
    }.tabto(0)
    
    declare :step_discrete_macros => '
      #define INT2BOOL(i)  (i ? Qtrue : Qfalse)

      #define SWAP_VALUE(v, w) {VALUE ___tmp = v; v = w; w = ___tmp;}

      #define EACH_COMP_DO(lc)                          \\
      for (list = RARRAY(lc), list_i = list->len - 1;   \\
           list_i >= 0 && (                             \\
             comp = list->ptr[list_i],                  \\
             comp_shdw = get_shadow(comp),              \\
             1);                                        \\
           list_i--)

      #define EACH_COMP_ADVANCE(lc)                     \\
      for (list = RARRAY(lc);                           \\
           list->len && (                               \\
             comp = list->ptr[list->len - 1],           \\
             comp_shdw = get_shadow(comp),              \\
             1);                                        \\
           enter_next_phase(comp, lc, shadow))

      int dummy;
    '.tabto(0)
    
    comp_id = declare_class RedShift::Component
    get_const = proc {|k| "rb_const_get(#{comp_id}, #{declare_symbol k})"}
    init %{
      ExitState     = #{get_const[:Exit]};
      ProcClass     = #{get_const[:ProcPhase]};
      EventClass    = #{get_const[:EventPhase]};
      ResetClass    = #{get_const[:ResetPhase]};
      GuardClass    = #{get_const[:GuardPhase]};
      GuardWrapperClass = #{get_const[:GuardWrapper]};
      ExprWrapperClass  = #{get_const[:ExprWrapper]};
      DynamicEventClass = #{get_const[:DynamicEventValue]};

      guard_phase_sym = ID2SYM(#{declare_symbol :guard});
      proc_phase_sym  = ID2SYM(#{declare_symbol :proc});
      event_phase_sym = ID2SYM(#{declare_symbol :event});
      reset_phase_sym = ID2SYM(#{declare_symbol :reset});
    }
    
    body %{
      //%% hook_begin();
      started_events = 0;
      all_were_g = 1;
      shadow->zeno_counter = 0;
      shadow->discrete_step = 0;

      //%% hook_begin_step();
      
      while (1) {
        struct RArray *list;
        int            list_i;

        //# GUARD phase. Start on phase 4 of 4, because everything's in G.
        //%% hook_enter_guard_phase();
        shadow->discrete_phase = guard_phase_sym;

        EACH_COMP_ADVANCE(shadow->curr_G) {
          if (shadow->discrete_step == 0) {
            comp_shdw->checked = 0;
          }

          len = RARRAY(comp_shdw->outgoing)->len - 1; //# last is strict flag
          ptr = RARRAY(comp_shdw->outgoing)->ptr;
          
          while (len) {
            VALUE trans, guard, phases, dest, strict;
            int enabled;
            
            assert(len >= 5);
            
            strict = ptr[--len];
            guard = ptr[--len];
            
            enabled = !RTEST(guard) ||
              ((comp_shdw->checked && RTEST(strict)) ? 0 :
               guard_enabled(comp, guard, started_events));
            
            //%% hook_eval_guard(comp, guard, INT2BOOL(enabled),
            //%%                 ptr[len-3], ptr[len-2]);
            
            if (enabled) {
              phases  = ptr[--len];
              dest    = ptr[--len];
              trans   = ptr[--len];
              start_trans(comp_shdw, shadow, trans, dest, phases);
              all_were_g = 0;
              break;
            }
            else
              len -= 3;
          }
          
          comp_shdw->checked = 1;
        }

        //%% hook_leave_guard_phase();

        //# Step finished; prepare lists for next 4-phase step.
        SWAP_VALUE(shadow->curr_P, shadow->next_P);
        SWAP_VALUE(shadow->curr_E, shadow->next_E);
        SWAP_VALUE(shadow->curr_R, shadow->next_R);
        SWAP_VALUE(shadow->curr_G, shadow->next_G);

        if (RARRAY(shadow->finishers)->len) {
          EACH_COMP_DO(shadow->finishers) {
            finish_trans(comp_shdw, shadow);
          }
          EACH_COMP_DO(shadow->finishers) {
            check_strict(comp_shdw);
            //## optimize: only keep comps with var->ck_strict on this list
            //## option to skip this check
          }
          RARRAY(shadow->finishers)->len = 0;
          d_tick++; //# In case some comp entered new state with new alg. eqns.
          //## optimize by detecting just this condition
        }
        
        //# Done stepping if no transitions happened or are about to begin.
        all_are_g = !RARRAY(shadow->curr_P)->len &&
                    !RARRAY(shadow->curr_E)->len &&
                    !RARRAY(shadow->curr_R)->len;
        //%% hook_end_step(INT2BOOL(all_were_g), INT2BOOL(all_are_g));
        if (all_were_g && all_are_g)
          break;
        all_were_g = all_are_g;
        
        //# Check for zeno problem.
        if (shadow->zeno_limit >= 0) {
          shadow->zeno_counter++;
          if (shadow->zeno_counter > shadow->zeno_limit)
            rb_funcall(shadow->self, #{declare_symbol :step_zeno}, 0);
        }
        
        //# Begin a new discrete step.
        shadow->discrete_step++;
        //%% hook_begin_step();
        
        //# PROC phase
        //%% hook_enter_proc_phase();
        shadow->discrete_phase = proc_phase_sym;
        EACH_COMP_ADVANCE(shadow->curr_P) {
          VALUE procs = cur_procs(comp_shdw);
          
          for (i = 0; i < RARRAY(procs)->len; i++) {
            //%% hook_call_proc(comp, RARRAY(procs)->ptr[i]);
            VALUE val = RARRAY(procs)->ptr[i];
            
            if (SYMBOL_P(val))
              rb_funcall(comp, SYM2ID(val), 0);
            else
              rb_funcall(comp, #{insteval_proc}, 1, val);
            //## this tech. could be applied in EVENT and RESET.
            //## also, component-gen can make use of this optimization
            //## for procs, using code similar to that for guards.
//#            rb_obj_instance_eval(1, &RARRAY(procs)->ptr[i], comp);
//# rb_iterate(my_instance_eval, comp, call_block, RARRAY(procs)->ptr[i]);
          }
        }
        //%% hook_leave_proc_phase();

        //# EVENT phase
        //%% hook_enter_event_phase();
        started_events = 1;
        shadow->discrete_phase = event_phase_sym;
        SWAP_VALUE(shadow->active_E, shadow->prev_active_E);
        EACH_COMP_ADVANCE(shadow->curr_E) {
          VALUE events = cur_events(comp_shdw);

          ptr = RARRAY(events)->ptr;
          len = RARRAY(events)->len;
          for (i = len; i > 0; i--, ptr++) {
            int   event_idx = FIX2INT(RARRAY(*ptr)->ptr[#{epi::I_IDX}]);
            VALUE event_val = RARRAY(*ptr)->ptr[#{epi::V_IDX}];
            
            //## maybe this distinction should be made clear in the array
            //## itself, with a numeric switch, say.
            if (TYPE(event_val) == T_DATA &&
                rb_obj_is_kind_of(event_val, DynamicEventClass))
              event_val = rb_funcall(comp, #{insteval_proc}, 1, event_val);
            else if (rb_obj_is_kind_of(event_val, ExprWrapperClass))
              event_val = rb_float_new(eval_expr(comp, event_val));
            
            //%% hook_export_event(comp, RARRAY(*ptr)->ptr[#{epi::E_IDX}],
            //%%   event_val);
            RARRAY(comp_shdw->next_event_values)->ptr[event_idx] = event_val;
          }

          rb_ary_push(shadow->active_E, comp); //## optimize
        }
        //%% hook_leave_event_phase();
        
        //# RESET phase
        //%% hook_enter_reset_phase();
        shadow->discrete_phase = reset_phase_sym;
        EACH_COMP_DO(shadow->curr_R) {
          ContVar  *var     = (ContVar *)&FIRST_CONT_VAR(comp_shdw);
          VALUE     resets  = cur_resets(comp_shdw);
          
          VALUE     cont_resets   = RARRAY(resets)->ptr[0]; //##check len!
          VALUE     const_resets  = RARRAY(resets)->ptr[1];
          VALUE     link_resets   = RARRAY(resets)->ptr[2];

          ptr = RARRAY(cont_resets)->ptr;
          len = RARRAY(cont_resets)->len;
          assert(len <= comp_shdw->var_count);

          for (i = 0; i < len; i++, var++, ptr++) {
            VALUE reset = *ptr;
            if (reset == Qnil) {
              var->reset = 0;
            }
            else {
              double new_value;
              
//##              if (var->algebraic)
//##                rb_raise(#{declare_class AlgebraicAssignmentError},
//##                    "reset of variable with algebraic flow"); //## do statically?
              
              switch(TYPE(reset)) {
                case T_FIXNUM:
                case T_BIGNUM:
                case T_FLOAT:
                  new_value = NUM2DBL(reset);
                  break;
                default:
                  if (RBASIC(reset)->klass == rb_cProc)
                    new_value =
                      NUM2DBL(rb_funcall(comp, #{insteval_proc}, 1, reset));
                  else
                    new_value = eval_expr(comp, reset);
              }
              
              //%% hook_do_reset(comp,
              //%%   rb_funcall(comp_shdw->cont_state->self,//
              //%%              #{declare_symbol :var_at_index},1,INT2NUM(i)),
              //%%   rb_float_new(new_value));
              var->value_1 = new_value;
              var->reset = 1;
            }
          }
          
          ptr = RARRAY(const_resets)->ptr;
          len = RARRAY(const_resets)->len;
          for (i = 0; i < len; i++) {
            VALUE   pair    = ptr[i];
            int     offset  = NUM2INT(RARRAY(pair)->ptr[0]);
            VALUE   reset   = RARRAY(pair)->ptr[1];
            double new_value;
            
            switch(TYPE(reset)) {
              case T_FIXNUM:
              case T_BIGNUM:
              case T_FLOAT:
                new_value = NUM2DBL(reset);
                break;
              default:
                if (RBASIC(reset)->klass == rb_cProc)
                  new_value =
                    NUM2DBL(rb_funcall(comp, #{insteval_proc}, 1, reset));
                else
                  new_value = eval_expr(comp, reset);
            }
            
            //%% hook_do_reset_constant(comp,
            //%%     RARRAY(pair)->ptr[2], rb_float_new(new_value));
            cache_new_constant_value(
              (double *)((char *)comp_shdw + offset),
              new_value, shadow);
          }
          
          ptr = RARRAY(link_resets)->ptr;
          len = RARRAY(link_resets)->len;
          for (i = 0; i < len; i++) {
            VALUE   pair    = ptr[i];
            int     offset  = NUM2INT(RARRAY(pair)->ptr[0]);
            VALUE   reset   = RARRAY(pair)->ptr[1];
            VALUE   new_value;
            
            if (RBASIC(reset)->klass == rb_cProc) {
              new_value =
                (VALUE)(rb_funcall(comp, #{insteval_proc}, 1, reset));
            } else
                ; //## unimpl--see component-gen.rb
            
            if (!NIL_P(new_value) &&
                rb_obj_is_kind_of(new_value, RARRAY(pair)->ptr[3]) != Qtrue) {
              VALUE to_s = #{declare_symbol :to_s};
              rb_raise(#{declare_class TypeError},
                "tried to reset %s, which is declared %s, with %s.",
                STR2CSTR(rb_funcall(RARRAY(pair)->ptr[2], to_s, 0)),
                STR2CSTR(rb_funcall(RARRAY(pair)->ptr[3], to_s, 0)),
                STR2CSTR(rb_funcall(
                  rb_funcall(new_value, #{declare_symbol :class}, 0), to_s, 0))
                );
            }

            //%% hook_do_reset_link(comp,
            //%%     RARRAY(pair)->ptr[2], (VALUE)new_value);
            cache_new_link(
              (ComponentShadow **)((char *)comp_shdw + offset),
              new_value, shadow);
          }
        }
        //%% hook_leave_reset_phase();

        //%% hook_begin_parallel_assign();
        //# Clear old event values from previous step.
        //#   (As of v1.1.32, considered as part of reset phase)
        EACH_COMP_DO(shadow->prev_active_E) {
          rb_mem_clear(RARRAY(comp_shdw->event_values)->ptr,
                       RARRAY(comp_shdw->event_values)->len);
        }
        RARRAY(shadow->prev_active_E)->len = 0;
        
        //# Export new event values.
        //#   (As of v1.1.32, considered as part of reset phase)
        EACH_COMP_DO(shadow->active_E) {
          SWAP_VALUE(comp_shdw->event_values, comp_shdw->next_event_values);
        }
        
        if (RARRAY(shadow->curr_R)->len) {
          EACH_COMP_ADVANCE(shadow->curr_R) {
            ContVar  *var     = (ContVar *)&FIRST_CONT_VAR(comp_shdw);
            VALUE     resets  = cur_resets(comp_shdw);

            VALUE     cont_resets   = RARRAY(resets)->ptr[0]; //##check len!
            VALUE     const_resets  = RARRAY(resets)->ptr[1];
            VALUE     link_resets   = RARRAY(resets)->ptr[2];

            len = RARRAY(cont_resets)->len;
            for (i = len; i > 0; i--, var++) {
              if (var->reset) {
                var->reset = 0;
                var->value_0 = var->value_1;
                if (var->algebraic) {
                  if (comp_shdw->state == comp_shdw->dest) {
                    // ### error?
                  }
                  else {
                    var->algebraic = 0;
                    // ## this is not needed in the 1-step transition model
                  }
                }
              }
            }
          }
          assign_new_constant_values(shadow);
          assign_new_links(shadow);
          d_tick++;   //# resets may invalidate algebraic flows
        }
        
        //%% hook_end_parallel_assign();
      }
      
      move_all_comps(shadow->curr_G, shadow->strict_sleep);
      SWAP_VALUE(shadow->curr_G, shadow->strict_sleep);
      //## might be more efficient to move strict_sleep to curr_G?
      
      assert(RARRAY(shadow->active_E)->len == 0);
      
      shadow->discrete_phase = Qnil;

      //%% hook_end();
    }
    
    # only call this when all defs have been added
    def parent.to_s
      @cached_output ||= super
    end
  end

  hook = /\bhook_\w+/
  world_classes = World.subclasses + [World]
  hooks = Hash.new {|h,cl| h[cl] = cl.instance_methods(true).grep(hook).sort}
  hooks[World.superclass] = nil
  known_hooks = nil
  
  world_classes.each do |cl|
    cl_hooks = hooks[cl]
    next if hooks[cl.superclass] == hooks[cl]
    
    cl.class_eval do
      shadow_library_source_file.include(Component.shadow_library_include_file)
      
      if (instance_methods(false) + protected_instance_methods(false) +
          private_instance_methods(false)).include?("step_discrete")
        warn "Redefining step_discrete in #{self}"
      end
      
      meth = define_c_method(:step_discrete, &discrete_step_definer)
      private :step_discrete
      
      before_commit do
        # at this point, we know the file is complete
        file_str = meth.parent.to_s
        
        known_hooks ||= file_str.scan(hook)
        unknown_hooks = cl_hooks - known_hooks

        unless unknown_hooks.empty?
          warn "Unknown hooks:\n  #{unknown_hooks.join("\n  ")}"
        end

        hook_pat = /\/\/%%\s*(#{cl_hooks.join("|")})\(((?:.|\n\s*\/\/%%)*)\)/
        file_str.gsub!(hook_pat) do
          hook = $1
          argstr = $2.gsub(/\/\/%%/, "")
          args = argstr.split(/,\s+/)
          args.each {|arg| arg.gsub(/\/\/.*$/, "")}
            # crude parser--no ", " within args, but may be multiline
            # and may have "//" comments, which can be used to extend an arg
            # across lines (see hook_do_reset).
          args.unshift(args.size)
          ## enclose the following in if(shadow->hook) {...}
          %{rb_funcall(shadow->self, #{meth.declare_symbol hook},
               #{args.join(", ")})}
        end
      end
    end
  end

end # class World

end # module RedShift
