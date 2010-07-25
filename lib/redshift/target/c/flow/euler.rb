module RedShift; class EulerDifferentialFlow
  def flow_wrapper cl, state
    var_name = @var
    flow = self
    
    flow_name = "flow_#{CGenerator.make_c_name cl.name}_#{var_name}_#{state}"
    
    Component::FlowWrapper.make_subclass flow_name do
      @inspect_str = "#{cl.name}:#{state}: #{var_name} = #{flow.formula}"

      ssn = cl.shadow_struct_name
      cont_state_ssn = cl.cont_state_class.shadow_struct_name
      
      # We need the struct
      shadow_library_source_file.include(cl.shadow_library_include_file)
      
      shadow_library_source_file.define(flow_name).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          ContVar  *var;
          double    ddt_#{var_name};
          double    time_step;
        }
        setup :first => %{
          if (comp_shdw->world->rk_level == 2 ||
              comp_shdw->world->rk_level == 3)
            return;
        } ## optimization: in rk_level==4 case, don't need to calc deps
        setup :shadow => %{
          shadow = (#{ssn} *)comp_shdw;
          cont_state = (struct #{cont_state_ssn} *)shadow->cont_state;
          var = &cont_state->#{var_name};
          time_step = shadow->world->time_step;
        } # return is necessary--else shadow, cont_state, var are uninitialized
        setup :rk_level => %{
          shadow->world->rk_level--;
        } # has to happen before referenced alg flows are called in other setups
        body %{
          switch (shadow->world->rk_level) {
          case 0:
            #{flow.translate(self, "ddt_#{var_name}", 0, cl).join("
            ")};

            var->value[1] = var->value[2] =
              var->value[0] + ddt_#{var_name} * time_step/2;
            var->value[3] =
              var->value[0] + ddt_#{var_name} * time_step;
            var->rk_level = 3;
            break;
          
          case 3:
            var->value[0] = var->value[3];
            var->rk_level = 4;
            break;
          }

          shadow->world->rk_level++;
        }
      end
      define_c_method :calc_function_pointer do
        body "shadow->flow = &#{flow_name}"
      end
    end
  end
end; end
