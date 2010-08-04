module RedShift; class AlgebraicFlow
  def make_generator cl, state
    @fname = "flow_#{CGenerator.make_c_name cl.name}_#{var}_#{state}"
    @inspect_str = "#{cl.name}:#{state}: #{var} = #{formula}"
    
    @generator = proc do
      sl = cl.shadow_library
      ssn = cl.shadow_struct_name
      cont_state_ssn = cl.cont_state_class.shadow_struct_name
      fw_ssn = Component::FlowWrapper.shadow_struct_name
      fw_cname = sl.declare_class Component::FlowWrapper
      
      sl.init_library_function.declare \
        :flow_wrapper_shadow => "#{fw_ssn} *fw_shadow",
        :flow_wrapper_value  => "VALUE fw"
      
      sl.init_library_function.body %{
        fw = rb_funcall(#{fw_cname}, #{sl.declare_symbol :new}, 1, rb_str_new2(#{inspect_str.inspect}));
        Data_Get_Struct(fw, #{fw_ssn}, fw_shadow);
        fw_shadow->flow = &#{fname};
        fw_shadow->algebraic = 1;
        rb_funcall(#{sl.declare_class Component}, #{sl.declare_symbol :store_flow}, 2,
          rb_str_new2(#{fname.inspect}), fw);
      }

      include_file, source_file = sl.add_file fname
      
      # We need the struct
      source_file.include(cl.shadow_library_include_file)
      
      flow = self
      var_name = @var
      source_file.define(fname).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        scope :extern
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          ContVar  *var;
        }
        exc = declare_class CircularDefinitionError
        msg = "Circularity in algebraic formula for #{var_name} in state " +
              "#{state} of class #{cl.name}."
        ## note that state may not be the same as the object's state, due
        ## to flow wrapper caching
        
        setup :shadow => %{
          shadow = (#{ssn} *)comp_shdw;
          cont_state = (struct #{cont_state_ssn} *)shadow->cont_state;
          var = &cont_state->#{var_name};
          assert(var->algebraic);
          if (shadow->world->alg_nest > shadow->world->alg_depth_limit) {
            shadow->world->alg_nest = 0;
            rs_raise(#{exc}, shadow->self, #{msg.inspect});
          }
          shadow->world->alg_nest++;
        }
        
        body %{
          #{flow.translate(self, "var->value[shadow->world->rk_level]", cl){|strict|
            flow.instance_eval {@strict = strict}
          }.join("
          ")};

          switch (shadow->world->rk_level) {
          case 0:
            var->d_tick = shadow->world->d_tick;
            break;
            
          case 1:
          case 2:
          case 3:
            var->rk_level = shadow->world->rk_level;
            break;
            
          default:
            rb_raise(#{declare_class RuntimeError},
              "Bad rk_level, %d!", shadow->world->rk_level);
          }
          
          shadow->world->alg_nest--;
        }
      end # Case 0 applies during discrete update.
          # alg flows are lazy
    end
    
    return self
  end
end; end
