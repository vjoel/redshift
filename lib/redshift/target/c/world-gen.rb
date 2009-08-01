module RedShift

class World
  include CShadow
  shadow_library RedShift.library
  shadow_library_file "World"
  shadow_library_source_file.include(Component.shadow_library_include_file)

  shadow_library_include_file.declare :step_discrete_macros => '
    #define INT2BOOL(i)  (i ? Qtrue : Qfalse)

    #define SWAP_VALUE(v, w) {VALUE ___tmp = v; v = w; w = ___tmp;}

    #define EACH_COMP_DO(lc)                          \\
    for (list = RARRAY(lc), list_i = list->len - 1;   \\
          list_i >= 0 && (                             \\
            comp = list->ptr[list_i],                  \\
            comp_shdw = get_shadow(comp),              \\
            1);                                        \\
          list_i--)

    int dummy;
  '.tabto(0)
  # Note: EACH_COMP_DO(lc) block may use move_comp and remove_comp
  # but it should (re)move none or all. Must have declarations for comp
  # comp_shdw, list, and list_i in scope.

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
  
  shadow_library_include_file.declare :port_cache_entry => %{
    typedef struct {
      VALUE           input_port;
      VALUE           other_port;
    } PortCacheEntry;
  }
  
  # Initial size for the constant value cache.
  CV_CACHE_SIZE = 64

  # Initial size for the link cache.
  LINK_CACHE_SIZE = 64
  
  # Initial size for the port cache.
  PORT_CACHE_SIZE = 64
  
  World.subclasses.each do |sub|
    file_name = CGenerator.make_c_name(sub.name).to_s
    sub.shadow_library_file file_name
  end

  shadow_attr_accessor :curr_A => Array
  shadow_attr_accessor :curr_P => Array
  shadow_attr_accessor :curr_CR => Array
  shadow_attr_accessor :curr_S => Array
  shadow_attr_accessor :next_S => Array
  shadow_attr_accessor :curr_T => Array
  shadow_attr_accessor :active_E => Array
  shadow_attr_accessor :prev_active_E => Array
  shadow_attr_accessor :awake => Array
  shadow_attr_accessor :prev_awake => Array
  shadow_attr_accessor :strict_sleep => Array
  shadow_attr_accessor :inert => Array
  shadow_attr_accessor :diff_list => Array
  shadow_attr_accessor :queue_sleep => Hash
  protected \
    :curr_A, :curr_P, :curr_CR, :curr_T,
    :active_E=, :prev_active_E=, :awake=,
    :strict_sleep=, :inert=, :diff_list=,
    :queue_sleep=
  
  shadow_attr_reader   :time_step     => "double   time_step"
  shadow_attr_accessor :zeno_limit    => "long     zeno_limit"
  shadow_attr_accessor :step_count    => "long     step_count"
  shadow_attr_accessor :clock_start   => "double   clock_start"
  shadow_attr_accessor :clock_finish  => "double   clock_finish"
  shadow_attr_accessor :zeno_counter  => "long     zeno_counter"
  shadow_attr_reader   :discrete_step => "long     discrete_step"
  shadow_attr_accessor :rk_level      => "long     rk_level"
  shadow_attr_accessor :d_tick        => "long     d_tick"
  shadow_attr_accessor :alg_nest      => "long     alg_nest"
  
  shadow_attr_accessor :base_clock    => "double   base_clock"
  shadow_attr_accessor :base_step_count =>
                                         "long     base_step_count"
  protected :base_clock=, :base_step_count=

  new_method.attr_code %{
    shadow->rk_level = 0;
    shadow->d_tick   = 1;
    shadow->alg_nest = 0;
  } # d_tick=1 means alg flows need to be recalculated

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
  ##should non-persist things like these get initialized in the alloc func, too?
  new_method.attr_code %{
    shadow->link_cache = 0;
    shadow->link_cache_size = 0;
    shadow->link_cache_used = 0;
  }
  free_function.free "free(shadow->link_cache)"
  
  shadow_struct.declare :port_cache => %{
    PortCacheEntry *port_cache;
    int port_cache_size;
    int port_cache_used;
  }
  new_method.attr_code %{
    shadow->port_cache = 0;
    shadow->port_cache_size = 0;
    shadow->port_cache_used = 0;
  }
  free_function.free "free(shadow->port_cache)"
  
  class << self
    # Redefines World#new so that a library commit happens first.
    def new(*args, &block)
      commit              # redefines World.new  
      new(*args, &block)  # which is what this line calls
    end
  end
  
  define_c_method :time_step= do
    arguments :time_step
    body %{
      double new_time_step = NUM2DBL(time_step);
      shadow->base_clock = shadow->base_clock +
       (shadow->step_count - shadow->base_step_count) * shadow->time_step;
      shadow->base_step_count = shadow->step_count;
      shadow->time_step = new_time_step;
    }
    returns "shadow->time_step" ## needed?
  end
  
  define_c_method :clock do
    returns %{
      rb_float_new(
       shadow->base_clock +
       (shadow->step_count - shadow->base_step_count) * shadow->time_step)
    }
  end
  
  define_c_method :bump_d_tick do
    body "shadow->d_tick++"
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
      comp_rb_ary[0] = shadow->awake;
      comp_rb_ary[1] = shadow->inert;
      for (li = 0; li < 2; li++) {
        len = RARRAY(comp_rb_ary[li])->len;
        comp_ary = RARRAY(comp_rb_ary[li])->ptr;
        for (ci = 0; ci < len; ci++) {
          Data_Get_Struct(comp_ary[ci], ComponentShadow, comp_shdw);
          var_count = comp_shdw->var_count;
          var = (ContVar *)(&FIRST_CONT_VAR(comp_shdw));
          end_var = &var[var_count];

          while (var < end_var) {
            var->rk_level = 0;
            if (!var->flow) {
              var->value_1 = var->value_2 = var->value_3 = var->value_0;
            }
            var++;
          }
        }
      }
      
      for (shadow->rk_level = 1; shadow->rk_level <= 3; shadow->rk_level++) {
        len = RARRAY(shadow->diff_list)->len;
        comp_ary = RARRAY(shadow->diff_list)->ptr;
        for (ci = 0; ci < len; ci++) {
          Data_Get_Struct(comp_ary[ci], ComponentShadow, comp_shdw);
          
          if (shadow->rk_level == 1 && !comp_shdw->has_diff) {
            if (ci < len-1) {
              comp_ary[ci] = comp_ary[len-1];
              ci--;
            }
            len = RARRAY(shadow->diff_list)->len = len-1;
            comp_shdw->diff_list = 0;
          }
          else {
            var_count = comp_shdw->var_count;
            var = (ContVar *)(&FIRST_CONT_VAR(comp_shdw));
            end_var = &var[var_count];

            while (var < end_var) {
              if (var->flow &&
                  var->rk_level < shadow->rk_level &&
                  !var->algebraic)
                (*var->flow)((ComponentShadow *)comp_shdw);
              var++;
            }
          }
        }
      }
      
      shadow->rk_level = 4;
      for (li = 0; li < 2; li++) {
        len = RARRAY(comp_rb_ary[li])->len;
        comp_ary = RARRAY(comp_rb_ary[li])->ptr;
        for (ci = 0; ci < len; ci++) {
          Data_Get_Struct(comp_ary[ci], ComponentShadow, comp_shdw);
          var_count = comp_shdw->var_count;
          var = (ContVar *)(&FIRST_CONT_VAR(comp_shdw));
          end_var = &var[var_count];

          while (var < end_var) {
            if (var->flow &&
                var->rk_level < shadow->rk_level &&
                !var->algebraic)
              (*var->flow)((ComponentShadow *)comp_shdw);
            
            if (var->rk_level == 4)
              var->d_tick = 1; //# var will be current in discrete_step
            else
              var->d_tick = 0; //# var (if alg) will need to be evaled
            var++;
          }
        }
      }

      shadow->d_tick = 1; //# alg flows need to be recalculated
      shadow->rk_level = 0;
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
      static VALUE      ActionClass, EventClass, ResetClass, GuardClass;
      static VALUE      QMatchClass, ConnectClass;
      static VALUE      PostClass, DynamicEventClass, SyncClass;
    }.tabto(0)
    
    declare :locals => %{
      VALUE             comp;
      ComponentShadow  *comp_shdw;
      VALUE            *ptr;
      long              len;
      long              i;
      struct RArray    *list;
      int               list_i;
      int               did_reset;
    }.tabto(0)
    
    insteval_proc = declare_symbol :insteval_proc
    capa = RUBY_VERSION.to_f >= 1.7 ? "aux.capa" : "capa"
    epi = Component::EventPhaseItem
    spi = Component::SyncPhaseItem
    
    parent.declare :step_discrete_subs => %{
      inline static VALUE cur_syncs(ComponentShadow *comp_shdw)
      {
        VALUE syncs = RARRAY(comp_shdw->trans)->ptr[#{Transition::S_IDX}];
        assert(syncs == Qnil || RBASIC(syncs)->klass == SyncClass);
        return syncs;
      }
      inline static VALUE cur_actions(ComponentShadow *comp_shdw)
      {
        VALUE actions = RARRAY(comp_shdw->trans)->ptr[#{Transition::A_IDX}];
        assert(actions == Qnil || RBASIC(actions)->klass == ActionClass);
        return actions;
      }
      inline static VALUE cur_posts(ComponentShadow *comp_shdw)
      {
        VALUE posts = RARRAY(comp_shdw->trans)->ptr[#{Transition::P_IDX}];
        assert(posts == Qnil || RBASIC(posts)->klass == PostClass);
        return posts;
      }
      inline static VALUE cur_events(ComponentShadow *comp_shdw)
      {
        VALUE events = RARRAY(comp_shdw->trans)->ptr[#{Transition::E_IDX}];
        assert(events == Qnil || RBASIC(events)->klass == EventClass);
        return events;
      }
      inline static VALUE cur_resets(ComponentShadow *comp_shdw)
      {
        VALUE resets = RARRAY(comp_shdw->trans)->ptr[#{Transition::R_IDX}];
        assert(resets == Qnil || RBASIC(resets)->klass == ResetClass);
        return resets;
      }
      inline static VALUE cur_connects(ComponentShadow *comp_shdw)
      {
        VALUE connects = RARRAY(comp_shdw->trans)->ptr[#{Transition::C_IDX}];
        assert(connects == Qnil || RBASIC(connects)->klass == ConnectClass);
        return connects;
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
      inline static void move_comp_to_hash(VALUE comp, VALUE list, VALUE hash)
      {
        struct RArray *l = RARRAY(list);
        assert(l->ptr[l->len-1] == comp);
        rb_hash_aset(hash, comp, Qtrue);
        --l->len;
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
        assert(comp_shdw->world == shadow);
        comp_shdw->world = 0;
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
      inline static ComponentShadow *eval_comp_expr(VALUE comp, VALUE expr)
      {
        ComponentShadow *(*fn)(ComponentShadow *);
        ComponentShadow *rslt;
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
      inline static int guard_enabled(VALUE comp, VALUE guards,
                                      int discrete_step)
      {
        int i;
        VALUE kl;
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
              kl = RBASIC(guard)->klass;
              if (kl == QMatchClass) {
                int len = RARRAY(guard)->len;
                VALUE *ptr = RARRAY(guard)->ptr;
                assert(len > 0);
                VALUE queue_name = ptr[0];
                VALUE queue = rb_funcall(comp, SYM2ID(queue_name), 0);
                if (!RTEST(rb_funcall2(queue, #{declare_symbol :head_matches},
                    len-1, &ptr[1])))
                  return 0;
              }
              else {
                rb_raise(#{declare_class StandardError},
                  "Bad array class in guard_enabled().");
              }
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
      
      inline static int comp_can_sync(ComponentShadow *comp_shdw,
               #{World.shadow_struct.name} *shadow)
      {
        int i, j;
        int can_sync = 1;
        VALUE syncs = cur_syncs(comp_shdw);
        assert(RTEST(syncs));
        
        for (i = RARRAY(syncs)->len - 1; i >= 0; i--) {
          VALUE sync = RARRAY(syncs)->ptr[i];
          assert(RARRAY(sync)->len == 3);
          int link_offset = FIX2INT(RARRAY(sync)->ptr[#{spi::LINK_OFFSET_IDX}]);
          VALUE event = RARRAY(sync)->ptr[#{spi::EVENT_IDX}];
          ComponentShadow *link_shdw =
            *(ComponentShadow **)(((char *)comp_shdw) + link_offset);
          
          if (!link_shdw || !RTEST(link_shdw->trans)) {
            can_sync = 0;
            break;
          }
          
          int found = 0;
          VALUE link_events = cur_events(link_shdw);
          if (RTEST(link_events)) {
            VALUE  *ptr   = RARRAY(link_events)->ptr;
            long    len   = RARRAY(link_events)->len;
      
            for (j = len; j > 0; j--, ptr++) {
              VALUE link_event = RARRAY(*ptr)->ptr[#{epi::E_IDX}];
              if (link_event == event) {
                found = 1;
                break;
              }
            }
          }
          
          if (!found) {
            can_sync = 0;
            break;
          }
        }
        
        //%% hook_can_sync(comp_shdw->self, INT2BOOL(can_sync));
        return can_sync;
      }
      
      inline static int eval_events(ComponentShadow *comp_shdw,
               #{World.shadow_struct.name} *shadow)
      {
        VALUE events = cur_events(comp_shdw);
        int has_events = RTEST(events);
        
        if (has_events) {
          VALUE  *ptr   = RARRAY(events)->ptr;
          long    len   = RARRAY(events)->len;
          int     i;
          VALUE   comp  = comp_shdw->self;

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

            //%% hook_eval_event(comp, RARRAY(*ptr)->ptr[#{epi::E_IDX}],
            //%%   event_val);
            RARRAY(comp_shdw->next_event_values)->ptr[event_idx] = event_val;
          }
        }

        return has_events;
      }
      
      inline static void cache_new_constant_value(
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
      
      inline static int assign_new_constant_values(
        #{World.shadow_struct.name} *shadow)
      {
        int did_reset = shadow->cv_cache_used;

        if (shadow->cv_cache_used) {
          int i;
          CVCacheEntry *entry;

          entry = shadow->constant_value_cache;
          for (i = shadow->cv_cache_used; i > 0; i--, entry++) {
            *entry->dbl_ptr = entry->value;
          }
          shadow->cv_cache_used = 0;
        }
        
        return did_reset;
      }
      
      inline static void cache_new_link(
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
      
      inline static int assign_new_links(
        #{World.shadow_struct.name} *shadow)
      {
        int did_reset = shadow->link_cache_used;
        
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
        
        return did_reset;
      }
      
      inline static void cache_new_port(VALUE input_port, VALUE other_port,
               #{World.shadow_struct.name} *shadow)
      {
        PortCacheEntry *entry;
        
        if (!shadow->port_cache) {
          int n = #{PORT_CACHE_SIZE};
          shadow->port_cache = malloc(n*sizeof(PortCacheEntry));
          shadow->port_cache_size = n;
          shadow->port_cache_used = 0;
        }
        if (shadow->port_cache_used == shadow->port_cache_size) {
          int n_bytes;
          shadow->port_cache_size *= 2;
          n_bytes = shadow->port_cache_size*sizeof(PortCacheEntry);
          shadow->port_cache = realloc(shadow->port_cache, n_bytes);
          if (!shadow->port_cache) {
            rb_raise(#{declare_class NoMemoryError},
                "Out of memory trying to allocate %d bytes for port cache.",
                n_bytes);
          }
        }
        entry = &shadow->port_cache[shadow->port_cache_used];
        entry->input_port = input_port;
        entry->other_port = other_port;
        shadow->port_cache_used += 1;
      }
      
      inline static int assign_new_ports(
        #{World.shadow_struct.name} *shadow)
      {
        int did_reset = shadow->port_cache_used;
        
        if (shadow->port_cache_used) {
          int i;
          PortCacheEntry *entry;

          entry = shadow->port_cache;
          for (i = shadow->port_cache_used; i > 0; i--, entry++) {
            rb_funcall(entry->input_port, #{declare_symbol :_connect}, 1,
              entry->other_port);
          }
          shadow->port_cache_used = 0;
        }
        
        return did_reset;
      }
      
      inline static int eval_continuous_resets(ComponentShadow *comp_shdw,
                              #{World.shadow_struct.name} *shadow)
      {
        VALUE   resets          = cur_resets(comp_shdw);
        VALUE   cont_resets;
        int     has_cont_resets;

        if (!RTEST(resets))
          return 0;

        cont_resets     = RARRAY(resets)->ptr[0];
        has_cont_resets = RTEST(cont_resets);

        if (has_cont_resets) {
          VALUE   *ptr = RARRAY(cont_resets)->ptr;
          long    len  = RARRAY(cont_resets)->len;
          int     i;
          VALUE   comp = comp_shdw->self;
          ContVar *var = (ContVar *)&FIRST_CONT_VAR(comp_shdw);
          assert(len <= comp_shdw->var_count);

          for (i = 0; i < len; i++, var++, ptr++) {
            VALUE reset = *ptr;
            if (reset == Qnil) {
              var->reset = 0;
            }
            else {
              double new_value;

//##        if (var->algebraic)
//##          rb_raise(#{declare_class AlgebraicAssignmentError},
//##              "reset of variable with algebraic flow"); //## do statically?

              switch(TYPE(reset)) {
                case T_FLOAT:
                  new_value = RFLOAT(reset)->value;
                  break;
                default:
                  if (RBASIC(reset)->klass == rb_cProc) {
                    VALUE val = rb_funcall(comp, #{insteval_proc}, 1, reset);
                    switch(TYPE(val)) {
                      case T_FLOAT:
                        new_value = RFLOAT(val)->value;
                        break;
                      case T_FIXNUM:
                        new_value = FIX2INT(val);
                        break;
                      default:
                        rs_raise(#{declare_class VarTypeError}, comp,
                          "tried to reset cont var with %s.",
                          STR2CSTR(rb_funcall(
                            rb_funcall(val, #{declare_symbol :class}, 0),
                            #{declare_symbol :to_s},
                            0))
                        );
                    }
                  }
                  else
                    new_value = eval_expr(comp, reset);
              }

              //%% hook_eval_reset_continuous(comp,
              //%%   rb_funcall(comp_shdw->cont_state->self,//
              //%%              #{declare_symbol :var_at_index},1,INT2NUM(i)),
              //%%   rb_float_new(new_value));
              var->value_1 = new_value;
              var->reset = 1;
            }
          }
        }
        
        return has_cont_resets;
      }

      inline static int eval_constant_resets(ComponentShadow *comp_shdw,
               #{World.shadow_struct.name} *shadow)
      {
        VALUE     resets            = cur_resets(comp_shdw);
        VALUE     const_resets;
        VALUE     link_resets;
        int       has_const_resets;
        int       has_link_resets;
        int       i;
        VALUE     comp;

        if (!RTEST(resets))
          return 0;

        const_resets      = RARRAY(resets)->ptr[1];
        link_resets       = RARRAY(resets)->ptr[2];
        has_const_resets  = RTEST(const_resets);
        has_link_resets   = RTEST(link_resets);
        comp              = comp_shdw->self;

        if (has_const_resets) {
          VALUE   *ptr = RARRAY(const_resets)->ptr;
          long    len  = RARRAY(const_resets)->len;

          for (i = 0; i < len; i++) {
            VALUE   pair    = ptr[i];
            int     offset  = NUM2INT(RARRAY(pair)->ptr[0]);
            VALUE   reset   = RARRAY(pair)->ptr[1];
            double new_value;

            switch(TYPE(reset)) {
              case T_FLOAT:
                new_value = RFLOAT(reset)->value;
                break;
              default:
                if (RBASIC(reset)->klass == rb_cProc)
                  new_value =
                    NUM2DBL(rb_funcall(comp, #{insteval_proc}, 1, reset));
                else
                  new_value = eval_expr(comp, reset);
            }

            //%% hook_eval_reset_constant(comp,
            //%%     RARRAY(pair)->ptr[2], rb_float_new(new_value));
            cache_new_constant_value(
              (double *)((char *)comp_shdw + offset),
              new_value, shadow);
          }
        }
        
        if (has_link_resets) {
          VALUE   *ptr = RARRAY(link_resets)->ptr;
          long    len  = RARRAY(link_resets)->len;
          
          for (i = 0; i < len; i++) {
            VALUE   pair    = ptr[i];
            int     offset  = NUM2INT(RARRAY(pair)->ptr[0]);
            VALUE   reset   = RARRAY(pair)->ptr[1];
            VALUE   new_value;

            if (rb_obj_is_kind_of(reset, ExprWrapperClass)) {
              ComponentShadow *new_sh;
              new_sh = (ComponentShadow *) eval_comp_expr(comp, reset);
              new_value = new_sh ? new_sh->self : Qnil;
            }
            else if (reset == Qnil) {
              new_value = reset;
            }
            else if (RBASIC(reset)->klass == rb_cProc) {
              new_value =
                (VALUE)(rb_funcall(comp, #{insteval_proc}, 1, reset));
            }
            else {
              new_value = reset; // will raise exception below
            }

            if (!NIL_P(new_value) &&
                rb_obj_is_kind_of(new_value, RARRAY(pair)->ptr[3]) != Qtrue) {
              VALUE to_s = #{declare_symbol :to_s};
              rs_raise(#{declare_class LinkTypeError}, comp_shdw->self,
                "tried to reset %s, which is declared %s, with %s.",
                STR2CSTR(rb_funcall(RARRAY(pair)->ptr[2], to_s, 0)),
                STR2CSTR(rb_funcall(RARRAY(pair)->ptr[3], to_s, 0)),
                STR2CSTR(rb_funcall(
                  rb_funcall(new_value, #{declare_symbol :class}, 0), to_s, 0))
                );
            }

            //%% hook_eval_reset_link(comp,
            //%%     RARRAY(pair)->ptr[2], (VALUE)new_value);
            cache_new_link(
              (ComponentShadow **)((char *)comp_shdw + offset),
              new_value, shadow);
          }
        }
        
        return has_const_resets || has_link_resets;
      }
      
      inline static int eval_port_connects(ComponentShadow *comp_shdw,
               #{World.shadow_struct.name} *shadow)
      {
        VALUE     connects    = cur_connects(comp_shdw);

        if (!RTEST(connects))
          return 0;
        else {
          int     i;
          VALUE   comp = comp_shdw->self;
          VALUE   *ptr = RARRAY(connects)->ptr;
          long    len  = RARRAY(connects)->len;

          for (i = 0; i < len; i++) {
            VALUE   pair      = ptr[i];
            VALUE   input_var = RARRAY(pair)->ptr[0];
            VALUE   connect_spec = RARRAY(pair)->ptr[1];
            VALUE   input_port;
            VALUE   other_port;
            
            input_port = rb_funcall(comp, #{declare_symbol :port}, 1, input_var);
            if (connect_spec == Qnil) {
              other_port = Qnil;
            }
            else if (RBASIC(connect_spec)->klass == rb_cProc) {
              other_port = rb_funcall(comp, #{insteval_proc}, 1, connect_spec);
            }
            else {
              // ## unimpl.
            }

            //%% hook_eval_port_connect(comp,
            //%%     input_port, other_port);
            cache_new_port(input_port, other_port, shadow);
          }
          return 1;
        }
      }
      
      inline static int assign_new_cont_values(ComponentShadow *comp_shdw)
      {
        VALUE     resets        = cur_resets(comp_shdw);
        VALUE     cont_resets;
        ContVar  *var;
        int       did_reset;
        long      len;
        long      i;

        if (!RTEST(resets))
          return 0;

        cont_resets   = RARRAY(resets)->ptr[0];
        var           = (ContVar *)&FIRST_CONT_VAR(comp_shdw);
        did_reset     = 0;

        len = RARRAY(cont_resets)->len;
        for (i = len; i > 0; i--, var++) {
          if (var->reset) {
            var->reset = 0;
            var->value_0 = var->value_1;
            did_reset = 1;
          }
        }
        return did_reset;
      }

      inline static void do_actions(ComponentShadow *comp_shdw, VALUE actions,
                              #{World.shadow_struct.name} *shadow)
      {
        long  i;
        VALUE comp    = comp_shdw->self;
        
        assert(RTEST(actions));

        for (i = 0; i < RARRAY(actions)->len; i++) {
          VALUE val = RARRAY(actions)->ptr[i];
          //%% hook_call_action(comp, val);

          if (SYMBOL_P(val))
            rb_funcall(comp, SYM2ID(val), 0);
          else
            rb_funcall(comp, #{insteval_proc}, 1, val);
          //## this tech. could be applied in EVENT and RESET.
          //## also, component-gen can make use of this optimization
          //## for procs, using code similar to that for guards.
//#            rb_obj_instance_eval(1, &RARRAY(actions)->ptr[i], comp);
//# rb_iterate(my_instance_eval, comp, call_block, RARRAY(actions)->ptr[i]);
        }
      }

      inline static void update_all_alg_vars(ComponentShadow *comp_shdw,
                              #{World.shadow_struct.name} *shadow)
      {
        ContVar    *vars = (ContVar *)&FIRST_CONT_VAR(comp_shdw);
        long        count = comp_shdw->var_count;
        long        i;
        for(i = 0; i < count; i++) {
          ContVar *var = &vars[i];
          if (var->algebraic &&
              (var->strict ? var->d_tick == 0 :
               var->d_tick != shadow->d_tick)) {
            var->flow(comp_shdw);
          }
        }
      }
      
      inline static void start_trans(ComponentShadow *comp_shdw,
                              #{World.shadow_struct.name} *shadow,
                              VALUE trans, VALUE dest)
      {
        comp_shdw->trans  = trans;
        comp_shdw->dest   = dest;
        //%% hook_start_transition(comp_shdw->self, trans, dest);
      }
      
      inline static void finish_trans(ComponentShadow *comp_shdw,
                               #{World.shadow_struct.name} *shadow)
      { //%% hook_finish_transition(comp_shdw->self, comp_shdw->trans,
        //%%                        comp_shdw->dest);
        if (comp_shdw->state != comp_shdw->dest) {
          update_all_alg_vars(comp_shdw, shadow);
          comp_shdw->state = comp_shdw->dest;
          rs_update_cache(comp_shdw);
          comp_shdw->checked  = 0;
        }
        comp_shdw->trans    = Qnil;
        comp_shdw->dest     = Qnil;
      }
      
      inline static void abort_trans(ComponentShadow *comp_shdw)
      {
        comp_shdw->trans    = Qnil;
        comp_shdw->dest     = Qnil;
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
      
      inline static void check_guards(#{World.shadow_struct.name} *shadow,
            int sync_retry)
      {
        VALUE             comp;
        ComponentShadow  *comp_shdw;
        struct RArray    *list;
        int               list_i;
        VALUE            *ptr;
        long              len, cur;
        
        EACH_COMP_DO(shadow->prev_awake) {
          int enabled = 0;
          
          if (shadow->discrete_step == 0)
            comp_shdw->checked = 0;
          
          len = RARRAY(comp_shdw->outgoing)->len - 1; //# last is flags
          cur = len;

          if (len == 0) {
            move_comp(comp, shadow->prev_awake, shadow->inert);
            continue;
          }

          ptr = RARRAY(comp_shdw->outgoing)->ptr;
          if (sync_retry)
            cur -= 4 * comp_shdw->tmp.trans.idx;
          else
            comp_shdw->tmp.trans.idx = 0;
          
          while (cur >= 4) {
            VALUE trans, dest, guard, strict;
            
            strict = ptr[--cur];
            guard = ptr[--cur];
            
            enabled = !RTEST(guard) ||
              ((comp_shdw->checked && RTEST(strict)) ? 0 :
               guard_enabled(comp, guard, shadow->discrete_step));
            
            //%% hook_eval_guard(comp, guard, INT2BOOL(enabled),
            //%%                 ptr[cur-2], ptr[cur-1]);
            
            if (enabled) {
              dest    = ptr[--cur];
              trans   = ptr[--cur];
              start_trans(comp_shdw, shadow, trans, dest);
              if (RTEST(cur_syncs(comp_shdw))) {
                move_comp(comp, shadow->prev_awake, shadow->curr_S);
                comp_shdw->tmp.trans.idx = (len - cur)/4;
              }
              else
                move_comp(comp, shadow->prev_awake, shadow->curr_T);
              break;
            }
            else
              cur -= 2;
          }
          
          if (!enabled) {
            VALUE qrc;
            if (comp_shdw->strict)
              move_comp(comp, shadow->prev_awake, shadow->strict_sleep);
            else if (comp_shdw->sleepable &&
                (qrc = rb_ivar_get(comp, #{declare_symbol :@queue_ready_count}),
                 qrc == Qnil || qrc == INT2FIX(0))) {
              move_comp_to_hash(comp, shadow->prev_awake, shadow->queue_sleep);
            }
            else
              move_comp(comp, shadow->prev_awake, shadow->awake);
            comp_shdw->checked = 1;
          }
        }
        assert(RARRAY(shadow->prev_awake)->len == 0);
      }
      
      inline static void do_sync_phase(#{World.shadow_struct.name} *shadow)
      {
        VALUE             comp;
        ComponentShadow  *comp_shdw;
        struct RArray    *list;
        int               list_i;
        int               changed;
        
        do {
          changed = 0;
          EACH_COMP_DO(shadow->curr_S) {
            if (comp_can_sync(comp_shdw, shadow)) {
              move_comp(comp, shadow->curr_S, shadow->next_S);
            }
            else {
              changed = 1;
              abort_trans(comp_shdw);
              move_comp(comp, shadow->curr_S, shadow->prev_awake);
            }
          }
          
          assert(RARRAY(shadow->curr_S)->len == 0);
          SWAP_VALUE(shadow->curr_S, shadow->next_S);
          //%% hook_sync_step(shadow->curr_S, INT2BOOL(changed));
        } while (changed);
      
        move_all_comps(shadow->curr_S, shadow->curr_T);
      }
    
    }.tabto(0)
    
    comp_id = declare_class RedShift::Component
    get_const = proc {|k| "rb_const_get(#{comp_id}, #{declare_symbol k})"}
    init %{
      ExitState     = #{get_const[:Exit]};
      ActionClass   = #{get_const[:ActionPhase]};
      PostClass     = #{get_const[:PostPhase]};
      EventClass    = #{get_const[:EventPhase]};
      ResetClass    = #{get_const[:ResetPhase]};
      ConnectClass  = #{get_const[:ConnectPhase]};
      GuardClass    = #{get_const[:GuardPhase]};
      SyncClass     = #{get_const[:SyncPhase]};
      QMatchClass   = #{get_const[:QMatch]};
      GuardWrapperClass = #{get_const[:GuardWrapper]};
      ExprWrapperClass  = #{get_const[:ExprWrapper]};
      DynamicEventClass = #{get_const[:DynamicEventValue]};
    }
    
    body %{
      //%% hook_begin();
      shadow->zeno_counter = 0;

      for (shadow->discrete_step = 0 ;; shadow->discrete_step++) {
        //%% hook_begin_step();
        int sync_retry = 0;
        
        SWAP_VALUE(shadow->prev_awake, shadow->awake);
        
        while (RARRAY(shadow->prev_awake)->len) {
          //%% hook_enter_guard_phase();
          check_guards(shadow, sync_retry);
          //%% hook_leave_guard_phase();

          //%% hook_enter_sync_phase();
          do_sync_phase(shadow);
          //%% hook_leave_sync_phase();
          sync_retry = 1;
        }
        
        if (!RARRAY(shadow->curr_T)->len) {
          //%% hook_end_step();
          break; //# out of main loop
        }

        EACH_COMP_DO(shadow->curr_T) {
          //%% hook_begin_eval_events(comp);
          if (eval_events(comp_shdw, shadow))
            rb_ary_push(shadow->active_E, comp);
          //%% hook_end_eval_events(comp);
        }
        
        //# Export new event values.
        EACH_COMP_DO(shadow->active_E) {
          SWAP_VALUE(comp_shdw->event_values, comp_shdw->next_event_values);
          //%% hook_export_events(comp, comp_shdw->event_values);
        }
        SWAP_VALUE(shadow->active_E, shadow->prev_active_E);
        assert(RARRAY(shadow->active_E)->len == 0);
        
        //%% hook_enter_eval_phase();
        EACH_COMP_DO(shadow->curr_T) {
          //%% hook_begin_eval_resets(comp);
          if (eval_continuous_resets(comp_shdw, shadow))
            rb_ary_push(shadow->curr_CR, comp);
          eval_constant_resets(comp_shdw, shadow);
          eval_port_connects(comp_shdw, shadow);
          //%% hook_end_eval_resets(comp);
          
          if (RTEST(cur_actions(comp_shdw)))
            rb_ary_push(shadow->curr_A, comp);
          
          if (RTEST(cur_posts(comp_shdw)))
            rb_ary_push(shadow->curr_P, comp);
        }
        //%% hook_leave_eval_phase();

        //%% hook_enter_action_phase();
        EACH_COMP_DO(shadow->curr_A) {
          do_actions(comp_shdw, cur_actions(comp_shdw), shadow);
        }
        RARRAY(shadow->curr_A)->len = 0;
        //%% hook_leave_action_phase();

        //%% hook_begin_parallel_assign();
        did_reset = 0;
        EACH_COMP_DO(shadow->curr_CR) {
          did_reset = assign_new_cont_values(comp_shdw) || did_reset;
        }
        RARRAY(shadow->curr_CR)->len = 0;
        did_reset = assign_new_constant_values(shadow) || did_reset;
        did_reset = assign_new_links(shadow) || did_reset;
        did_reset = assign_new_ports(shadow) || did_reset;
        //%% hook_end_parallel_assign();

        //%% hook_enter_post_phase();
        EACH_COMP_DO(shadow->curr_P) {
          do_actions(comp_shdw, cur_posts(comp_shdw), shadow);
        }
        RARRAY(shadow->curr_P)->len = 0;
        //%% hook_leave_post_phase();
        
        EACH_COMP_DO(shadow->curr_T) {
          finish_trans(comp_shdw, shadow);
        }

        if (did_reset || 1)
          shadow->d_tick++;
          //## replace "1" with "some comp entered new
          //## state with new alg. eqs"
        
        EACH_COMP_DO(shadow->curr_T) {
          check_strict(comp_shdw);
          //## optimize: only keep comps with var->ck_strict on this list
          //## option to skip this check
        }
        
        //# Check for zeno problem.
        if (shadow->zeno_limit >= 0) {
          shadow->zeno_counter++;
          if (shadow->zeno_counter > shadow->zeno_limit)
            rb_funcall(shadow->self, #{declare_symbol :step_zeno}, 0);
        }
        
        EACH_COMP_DO(shadow->curr_T) {
          if (comp_shdw->state == ExitState)
            remove_comp(comp, shadow->curr_T, shadow);
          else
            move_comp(comp, shadow->curr_T, shadow->awake);
        }
        assert(RARRAY(shadow->curr_T)->len == 0);
        assert(RARRAY(shadow->prev_awake)->len == 0);

        //# Clear event values.
        EACH_COMP_DO(shadow->prev_active_E) {
          rb_mem_clear(RARRAY(comp_shdw->event_values)->ptr,
                       RARRAY(comp_shdw->event_values)->len);
        }
        RARRAY(shadow->prev_active_E)->len = 0;
        
        //%% hook_end_step();
      }
      
      move_all_comps(shadow->strict_sleep, shadow->awake);

      //%% hook_end();
      shadow->discrete_step = 0;
      shadow->zeno_counter = 0;
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

        hook_pat =
          /\/\/%%[ \t]*(#{cl_hooks.join("|")})\(((?:.|\n[ \t]*\/\/%%)*)\)/
        file_str.gsub!(hook_pat) do
          hook = $1
          argstr = $2.gsub(/\/\/%%/, "")
          args = argstr.split(/,\s+/)
          args.each {|arg| arg.gsub(/\/\/.*$/, "")}
            # crude parser--no ", " within args, but may be multiline
            # and may have "//" comments, which can be used to extend an arg
            # across lines.
          args.unshift(args.size)
          ## enclose the following in if(shadow->hook) {...}
          %{rb_funcall(shadow->self, #{meth.declare_symbol hook},
               #{args.join(", ")})}
        end
      end
    end
  end

end # class World


class Component
    shadow_library_include_file.include(World.shadow_library_include_file)
    shadow_attr_reader :world => [World]

    define_c_method :__set__world do
      arguments :world
      world_ssn = World.shadow_struct_name
      body %{
        if (world != Qnil) {
          Data_Get_Struct(world, #{world_ssn}, shadow->world);
        } else
          shadow->world = 0;
      }
    end
    protected :__set__world
end

end # module RedShift
