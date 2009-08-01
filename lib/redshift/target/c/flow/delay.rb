class RedShift::DelayFlow
  def flow_wrapper cl, state
    var_name = @var
    flow = self
    flow_name = "flow_#{CGenerator.make_c_name cl.name}_#{var_name}_#{state}"
    delay_by = @delay_by
    
    Component::FlowWrapper.make_subclass flow_name do
      @inspect_str = "#{var_name} = #{flow.formula} [delay: #{delay_by}]"

      ssn = cl.shadow_struct.name
      cont_state_ssn = cl.cont_state_class.shadow_struct.name
      
      require "redshift/target/c/flow/buffer"
      RedShift.library.define_buffer

      bufname     = "#{var_name}_buffer_data"
      offsetname  = "#{var_name}_buffer_offset"
      delayname   = "#{var_name}_delay"
      
      cl.class_eval do
        shadow_attr_reader bufname    => "Buffer  #{bufname}"
        shadow_attr_reader offsetname => "long    #{offsetname}"
        shadow_attr_reader delayname  => "double  #{delayname}"
      end
      
      # We need the struct
      shadow_library_source_file.include(cl.shadow_library_include_file)
      
      shadow_library_source_file.define(flow_name).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          ContVar   *var, *target_var;
          double    *ptr;
          long      i, len, offset, steps;
          double    delay, fill;
        }
        setup :shadow => %{
          shadow = (#{ssn} *)comp_shdw;
          cont_state = (#{cont_state_ssn} *)shadow->cont_state;
          var = &cont_state->#{var_name};
          target_var = &cont_state->#{flow.formula};
        }
        setup :rk_level => %{
          rk_level--;
        } # has to happen before referenced alg flows are called in other setups

        case delay_by
        when /\A\w+\z/
          flow.translate(self, "delay", 0, cl, delay_by)
        else
          begin
            setup :delay => "delay = #{Float(delay_by)}"
          rescue ArgumentError
            raise ArgumentError,
              "Delay by expression #{delay_by.inspect} not implemented."
          end
        end
        
        include "World.h"

        world_ssn = "RedShift_o_World_Shadow" ## chicken or egg?
        body %{
          switch (rk_level) {
          case 0:
            ptr = shadow->#{bufname}.ptr;
            len = shadow->#{bufname}.len;
            if (ptr) {
            
              // ## if (size != shadow->#{bufname}.len)
              // ## check consistency with delay_by and timestep
              // ## check if state changed recently--clear old hist
            
            }
            else {
              #{world_ssn} *world_shadow;

              #{flow.translate(self, "fill", 0, cl, flow.formula.dup).join("
              ")};
              
              Data_Get_Struct(shadow->world, #{world_ssn}, world_shadow);
              steps = ceil(delay / world_shadow->time_step);
              len = steps*4;
              ptr = ALLOC_N(double, len);
              shadow->#{bufname}.ptr = ptr;
              shadow->#{bufname}.len = len;
              shadow->#{offsetname} = 0;
              shadow->#{delayname} = delay;
              
              for (i=0; i<len; i++) {
                ptr[i] = fill;
              }
            }

            offset = shadow->#{offsetname};
            if (offset < 0 || offset > len - 4) {
              rb_raise(#{declare_class RuntimeError},
              "Offset out of bounds: %d not in 0..%d!", offset, len);
            }

            offset = (offset + 4) % len;
            shadow->#{offsetname} = offset;
            
            var->value_0 = ptr[offset];
            var->value_1 = ptr[offset + 1];
            var->value_2 = ptr[offset + 2];
            var->value_3 = ptr[offset + 3];
            
            var->rk_level = 3;
            break;
            
          case 1:
          case 2:
            break;
            
          case 3:
            #{flow.translate(self, "fill", 3, cl, flow.formula).join("
            ")};
            ptr = shadow->#{bufname}.ptr;
            len = shadow->#{bufname}.len;
            offset = shadow->#{offsetname};

            ptr[offset]     = target_var->value_0;
            ptr[offset + 1] = target_var->value_1;
            ptr[offset + 2] = target_var->value_2;
            ptr[offset + 3] = target_var->value_3;

            var->value_0 = ptr[(offset + 4) % len];

            var->rk_level = 4;
            break;
            
          default:
            rb_raise(#{declare_class RuntimeError},
              "Bad rk_level, %d!", rk_level);
          }

          rk_level++;
        }
      end

      define_c_method :calc_function_pointer do
        body "shadow->flow = &#{flow_name}"
      end
    end
  end
end
