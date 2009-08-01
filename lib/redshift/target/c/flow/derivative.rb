module RedShift; class DerivativeFlow
  def flow_wrapper cl, state
    var_name = @var
    flow = self
    flow_name = "flow_#{CGenerator.make_c_name cl.name}_#{var_name}_#{state}"
    
    Component::FlowWrapper.make_subclass flow_name do
      @inspect_str = "#{var_name} = #{flow.formula}'"

      ssn = cl.shadow_struct.name
      cont_state_ssn = cl.cont_state_class.shadow_struct.name
      
      # We need the struct
      shadow_library_source_file.include(cl.shadow_library_include_file)
      
      scratch_name = cl.scratch_for var_name
      
      shadow_library_source_file.define(flow_name).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          ContVar  *var;
          double    antiddt, *scratch;
        }
        setup :shadow => %{
          shadow = (#{ssn} *)comp_shdw;
          cont_state = (#{cont_state_ssn} *)shadow->cont_state;
          var = &cont_state->#{var_name};
          scratch = &shadow->#{scratch_name};
        }
        setup :rk_level => %{
          rk_level--;
        } # has to happen before referenced alg flows are called in other setups
        body %{
          switch (rk_level) {
          case 0:
            #{flow.translate(self, "antiddt", 0, cl).join("
            ")};
            var->value_1 = var->value_0;
            *scratch = antiddt;
            break;
            
          case 1:
            #{flow.translate(self, "antiddt", 1, cl).join("
            ")};
            var->value_2 = (antiddt - *scratch) / (time_step/2);
            *scratch = antiddt;
            break;
            
          case 2:
            #{flow.translate(self, "antiddt", 2, cl).join("
            ")};
            var->value_3 = (antiddt - *scratch) / (time_step/2);
            //# *scratch = antiddt; (worse)
            break;
            
          case 3:
            #{flow.translate(self, "antiddt", 3, cl).join("
            ")};
            var->value_0 = (antiddt - *scratch) / (time_step/2);
            break;
            
          default:
            rb_raise(#{declare_class RuntimeError},
              "Bad rk_level, %d!", rk_level);
          }
          
          rk_level++;
          var->rk_level = rk_level;
        }
      end

      define_c_method :calc_function_pointer do
        body "shadow->flow = &#{flow_name}"
      end
    end
  end

end; end
