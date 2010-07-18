module RedShift; class RK4DifferentialFlow
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
          double    value_4;
          double    time_step;
        }
        setup :shadow => %{
          shadow = (#{ssn} *)comp_shdw;
          cont_state = (struct #{cont_state_ssn} *)shadow->cont_state;
          var = &cont_state->#{var_name};
          time_step = shadow->world->time_step;
        }
        setup :rk_level => %{
          shadow->world->rk_level--;
        } # has to happen before referenced alg flows are called in other setups
        body %{
          switch (shadow->world->rk_level) {
          case 0:
            #{flow.translate(self, "ddt_#{var_name}", 0, cl).join("
            ")};
            var->value_1 = var->value_0 + ddt_#{var_name} * time_step/2;
            break;

          case 1:
            #{flow.translate(self, "ddt_#{var_name}", 1, cl).join("
            ")};
            var->value_2 = var->value_0 + ddt_#{var_name} * time_step/2;
            break;

          case 2:
            #{flow.translate(self, "ddt_#{var_name}", 2, cl).join("
            ")};
            var->value_3 = var->value_0 + ddt_#{var_name} * time_step;
            break;

          case 3:
            #{flow.translate(self, "ddt_#{var_name}", 3, cl).join("
            ")};
            value_4 = var->value_0 + ddt_#{var_name} * time_step;
            var->value_0 = 
              (-3*var->value_0 + 2*var->value_1 + 4*var->value_2 +
                2*var->value_3 + value_4) / 6;
            break;

          default:
            rb_raise(#{declare_class RuntimeError},
              "Bad rk_level, %d!", shadow->world->rk_level);
          }
          
          shadow->world->rk_level++;
          var->rk_level = shadow->world->rk_level;
        }
      end

      define_c_method :calc_function_pointer do
        body "shadow->flow = &#{flow_name}"
      end
    end
  end
end; end
