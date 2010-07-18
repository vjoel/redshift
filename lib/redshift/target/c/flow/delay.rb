module RedShift; class DelayFlow
  def flow_wrapper cl, state
    var_name = @var
    flow = self
    flow_name = "flow_#{CGenerator.make_c_name cl.name}_#{var_name}_#{state}"
    delay_by = @delay_by
    
    Component::FlowWrapper.make_subclass flow_name do
      @inspect_str =
        "#{cl.name}:#{state}: " +
        "#{var_name} = #{flow.formula} [delay: #{delay_by}]"

      ssn = cl.shadow_struct_name
      cont_state_ssn = cl.cont_state_class.shadow_struct_name
      
      require "redshift/target/c/flow/buffer"
      RedShift.library.define_buffer

      bufname     = "#{var_name}_buffer_data"
      delayname   = "#{var_name}_delay"
      tsname      = "#{var_name}_time_step"
      
      cl.class_eval do
        shadow_attr_accessor bufname    => "RSBuffer  #{bufname}"
        shadow_attr_accessor delayname  => "double    #{delayname}"
          # delay should be set only using the expr designated in :by => "expr"
        shadow_attr          tsname     => "double    #{tsname}"
      
        after_commit do
          alias_method "__#{bufname}=", "#{bufname}="
          define_method "#{bufname}=" do |val|
            send("__#{bufname}=", val)
            d = world.time_step * (val.size / 4)
            send("#{delayname}=", d) # keep cached delay consistent
          end
        end
        private :"#{delayname}="
      end
      
      # We need the struct
      shadow_library_source_file.include(cl.shadow_library_include_file)
      
      shadow_library_source_file.define(flow_name).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          
          ContVar   *var;
          double    *ptr;
          long      len, offset, steps;
          double    delay, fill;
        }
        setup :shadow => %{
          shadow = (#{ssn} *)comp_shdw;
          cont_state = (struct #{cont_state_ssn} *)shadow->cont_state;
          var = &cont_state->#{var_name};
        }
        setup :rk_level => %{
          shadow->world->rk_level--;
        } # has to happen before referenced alg flows are called in other setups

        setup :delay => 
          begin
            "delay = #{Float(delay_by)}"
          rescue ArgumentError
            flow.translate(self, "delay", 0, cl, delay_by)
          end
        
        include World.shadow_library_include_file

        # Note: cases 1,2 must proceed to allow alg deps to be computed,
        # since their values are used later.
        body %{
          switch (shadow->world->rk_level) {
          case 0:
            ptr = shadow->#{bufname}.ptr;
            offset = shadow->#{bufname}.offset;
            
            if (shadow->world->time_step != shadow->#{tsname}) {
              if (shadow->#{tsname} == 0.0)
                shadow->#{tsname} = shadow->world->time_step;
              else
                rs_raise(#{declare_class RedShiftError}, shadow->self,
                "Delay flow doesn't support changing time_step yet"); // ##
            }
            
            if (ptr && delay == shadow->#{delayname}) {
              len = shadow->#{bufname}.len;
              if (offset < 0 || offset > len - 4) {
                rs_raise(#{declare_class RedShiftError}, shadow->self,
                "Offset out of bounds: %d not in 0..%d!", offset, len - 4);
              }
            }
            else {
              steps = floor(delay / shadow->world->time_step + 0.5);
              if (steps <= 0) {
                rs_raise(#{declare_class RedShiftError}, shadow->self,
                "Delay too small: %f.", delay);
              }
              len = steps*4;

              if (!ptr) {
                #{flow.translate(self, "fill", 0, cl).join("
                ")};

                rs_buffer_init(&shadow->#{bufname}, len, fill);
              }
              else { // # delay != shadow->#{delayname}
                rs_buffer_resize(&shadow->#{bufname}, len);
              }
              
              shadow->#{delayname} = delay;
              ptr = shadow->#{bufname}.ptr;
              offset = shadow->#{bufname}.offset;
            }
            
            var->value_0 = ptr[offset];
            var->value_1 = ptr[offset + 1];
            var->value_2 = ptr[offset + 2];
            var->value_3 = ptr[offset + 3];
            
            #{flow.translate(self, "ptr[offset]", 0, cl).join("
            ")};
            break;
            
          case 1:
          case 2:
            break;

          case 3:
            ptr = shadow->#{bufname}.ptr;
            len = shadow->#{bufname}.len;
            offset = shadow->#{bufname}.offset;

            #{flow.translate(self, "ptr[offset+1]", 1, cl).join("
            ")};
            #{flow.translate(self, "ptr[offset+2]", 2, cl).join("
            ")};
            #{flow.translate(self, "ptr[offset+3]", 3, cl).join("
            ")};

            offset = (offset + 4) % len;
            var->value_0 = ptr[offset];
            shadow->#{bufname}.offset = offset;
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
