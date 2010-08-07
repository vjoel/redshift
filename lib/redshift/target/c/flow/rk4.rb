module RedShift; class RK4DifferentialFlow
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
      
      flow = self
      var_name = @var
      source_file.define(fname).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        scope :extern
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
          #{flow.translate(self, "ddt_#{var_name}", cl).join("
          ")};

          switch (shadow->world->rk_level) {
          case 0:
            var->value[1] = var->value[0] + ddt_#{var_name} * time_step/2;
            break;

          case 1:
            var->value[2] = var->value[0] + ddt_#{var_name} * time_step/2;
            break;

          case 2:
            var->value[3] = var->value[0] + ddt_#{var_name} * time_step;
            break;

          case 3:
            value_4 = var->value[0] + ddt_#{var_name} * time_step;
            var->value[0] =
              (-3*var->value[0] + 2*var->value[1] + 4*var->value[2] +
                2*var->value[3] + value_4) / 6;
            break;

          default:
            rb_raise(#{declare_class RuntimeError},
              "Bad rk_level, %d!", shadow->world->rk_level);
          }
          
          shadow->world->rk_level++;
          var->rk_level = shadow->world->rk_level;
        }
      end
    end
  end
end; end
