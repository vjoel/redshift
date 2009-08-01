module RedShift; class EulerDifferentialFlow
  def flow_wrapper cl, state
    var_name = @var
    flow = self
    
    flow_name = "flow_#{CGenerator.make_c_name cl.name}_#{var_name}_#{state}"
    
    Component::FlowWrapper.make_subclass flow_name do
      @inspect_str = "#{var_name} = #{flow.formula}"

      ssn = cl.shadow_struct.name
      cont_state_ssn = cl.cont_state_class.shadow_struct.name
      
      # We need the struct
      shadow_library_source_file.include(cl.shadow_library_include_file)
      
      shadow_library_source_file.define(flow_name).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          ContVar  *var;
          double    ddt_#{var_name};
        }
        setup :shadow => %{
          if (rk_level == 1) {
            shadow = (#{ssn} *)comp_shdw;
            cont_state = (#{cont_state_ssn} *)shadow->cont_state;
            var = &cont_state->#{var_name};
          }
          else
            return;
        } # return is necessary--else shadow, cont_state, var are uninitialized
        setup :rk_level => %{
          rk_level -= 1;
        } # has to happen before referenced alg flows are called in other setups
        body %{
          if (rk_level == 0) {
            #{flow.translate(self, "ddt_#{var_name}", 0, cl).join("
            ")};

            var->value_0 = var->value_3 = var->value_2 =
              var->value_0 + time_step * ddt_#{var_name};
            
            var->rk_level = 4;
          }
          rk_level += 1;
        }
      end
      define_c_method :calc_function_pointer do
        body "shadow->flow = &#{flow_name}"
      end
    end
  end
end; end
