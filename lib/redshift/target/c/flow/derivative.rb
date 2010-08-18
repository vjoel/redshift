module RedShift; class DerivativeFlow
  def make_generator cl, state
    @fname = "flow_#{CGenerator.make_c_name cl.name}_#{var}_#{state}"
    @inspect_str = "#{cl.name}:#{state}: #{var} = #{formula}"

    @generator = proc do
      sl = cl.shadow_library
      ssn = cl.shadow_struct_name
      cont_state_ssn = cl.cont_state_class.shadow_struct_name

      sl.init_library_function.body \
        "s_init_flow(#{fname}, #{fname.inspect}, #{inspect_str.inspect}, NONALGEBRAIC);"

      include_file, source_file = sl.add_file fname
      
      # We need the struct
      source_file.include(cl.shadow_library_include_file)
      
      init_rhs_name = "#{var}_init_rhs"
      cl.class_eval do
        shadow_attr_accessor init_rhs_name => "double #{init_rhs_name}"
      end
      
      flow = self
      var_name = @var
      feedback = @feedback
      source_file.define(fname).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        scope :extern
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          ContVar  *var;
          double    antiddt, *scratch;
          double    time_step;
        }
        setup :shadow => %{
          shadow = (#{ssn} *)comp_shdw;
          cont_state = (struct #{cont_state_ssn} *)shadow->cont_state;
          var = &cont_state->#{var_name};
          scratch = &shadow->#{init_rhs_name};
          time_step = shadow->world->time_step;
        }
        setup :rk_level => %{
          shadow->world->rk_level--;
        } # has to happen before referenced alg flows are called in other setups
        if feedback ## possible to unite these cases somehow?
          body %{
            switch (shadow->world->rk_level) {
            case 0:
              #{flow.translate(self, "antiddt", cl, 0).join("
              ")};
              var->value[0] = var->value[1] =
              var->value[2] = var->value[3] =
              (antiddt - *scratch) / time_step;
              *scratch = antiddt;
            }
            shadow->world->rk_level++;
            var->rk_level = shadow->world->rk_level;
          }
        else
          body %{
            #{flow.translate(self, "antiddt", cl).join("
            ")};

            switch (shadow->world->rk_level) {
            case 0:
              var->value[1] = var->value[0];
              *scratch = antiddt;
              break;

            case 1:
              var->value[2] = (antiddt - *scratch) / (time_step/2);
              *scratch = antiddt;
              break;

            case 2:
              var->value[3] = (antiddt - *scratch) / (time_step/2);
              break;

            case 3:
              var->value[0] = (antiddt - *scratch) / (time_step/2);
              break;

            default:
              rb_raise(#{declare_class RuntimeError},
                "Bad rk_level, %ld!", shadow->world->rk_level);
            }

            shadow->world->rk_level++;
            var->rk_level = shadow->world->rk_level;
          }
        end
      end
    end
  end

end; end
