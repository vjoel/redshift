module RedShift

class World

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
          var_count = comp_shdw->var_count;
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

  define_method :step_discrete do
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
      { //### assert type check?
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
        assert(RARRAY(list)->ptr[RARRAY(list)->len-1] == comp);
        if (nl->len == nl->capa)
          rb_ary_store(next_list, nl->len, comp);
        else
          nl->ptr[nl->len++] = comp;
        --RARRAY(list)->len;
      }
      inline void remove_comp(VALUE comp, VALUE list)
      {
        ComponentShadow *comp_shdw = get_shadow(comp);
        assert(RARRAY(list)->ptr[RARRAY(list)->len-1] == comp);
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
                return 0;   //## faster way to call instance_eval ???
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
  
end # class World

end # module RedShift

