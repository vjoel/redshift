module RedShift; class DelayFlow
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
        shadow_attr_accessor bufname    => "Buffer  #{bufname}"
        shadow_attr_accessor offsetname => "long    #{offsetname}"
        shadow_attr_reader   delayname  => "double  #{delayname}"
          # delay can be set only using the var designated in :by => "var"
      end
      
      # We need the struct
      shadow_library_source_file.include(cl.shadow_library_include_file)
      
      shadow_library_source_file.define(flow_name).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        world_ssn = World.shadow_struct.name
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          #{world_ssn} *world_shadow;
          
          ContVar   *var;
          double    *ptr;
          long      i, len, offset, steps;
          double    delay, fill;
        }
        setup :first => %{
          if (rk_level == 2 || rk_level == 3)
            return;
        }
        setup :shadow => %{
          shadow = (#{ssn} *)comp_shdw;
          cont_state = (#{cont_state_ssn} *)shadow->cont_state;
          var = &cont_state->#{var_name};
        }
        setup :rk_level => %{
          rk_level--;
        } # has to happen before referenced alg flows are called in other setups

        setup :delay => 
          case delay_by
          when /\A\w+\z/
            flow.translate(self, "delay", 0, cl, delay_by)
          else
            begin
              "delay = #{Float(delay_by)}"
            rescue ArgumentError
              raise ArgumentError,
                "Delay by expression #{delay_by.inspect} not implemented."
            end
          end
        
        include World.shadow_library_include_file

        body %{
          switch (rk_level) {
          case 0:
            ptr = shadow->#{bufname}.ptr;
            offset = shadow->#{offsetname};
            
            if (ptr && delay == shadow->#{delayname}) {
              len = shadow->#{bufname}.len;
              if (offset < 0 || offset > len - 4) {
                rb_raise(#{declare_class RuntimeError},
                "Offset out of bounds: %d not in 0..%d!", offset, len);
              }
            }
            else {
              Data_Get_Struct(shadow->world, #{world_ssn}, world_shadow);
              steps = ceil(delay / world_shadow->time_step);
              if (steps <= 0) {
                rb_raise(#{declare_class RuntimeError},
                "Delay too small: %f", delay);
              }
              len = steps*4;

              if (!ptr) {
                #{flow.translate(self, "fill", 0, cl).join("
                ")};

                ptr = ALLOC_N(double, len);
                shadow->#{bufname}.ptr = ptr;
                shadow->#{bufname}.len = len;
                shadow->#{offsetname} = 0;
                shadow->#{delayname} = delay;

                for (i=0; i<len; i++) {
                  ptr[i] = fill;
                }
              }
              else { // # delay != shadow->#{delayname}
                long old_len = shadow->#{bufname}.len;
                double *dst, *src;

                if (delay < shadow->#{delayname}) {
                  if (offset < len) {
                    dst = ptr + offset;
                    src = ptr + offset + old_len - len;
                  }
                  else {
                    dst = ptr;
                    src = ptr + offset - len;
                    offset = 0;
                  }
                  memmove(dst, src, (len - offset) * sizeof(double));
                  REALLOC_N(ptr, double, len);
                }
                else { // # delay > shadow->#{delayname}
                  REALLOC_N(ptr, double, len);

                  fill = ptr[offset];
                  dst = ptr + offset + len - old_len;
                  src = ptr + offset;
                  memmove(dst, src, (old_len - offset) * sizeof(double));

                  for (i = 0; i < len - old_len; i++) {
                    ptr[offset + i] = fill;
                  }
                }
                
                shadow->#{bufname}.ptr = ptr;
                shadow->#{bufname}.len = len;
                shadow->#{offsetname} = offset;
                shadow->#{delayname} = delay;
              }
            }
            
            // ## Check if buffer is stale, and advance as needed?
            // ## This might be correct if A => B => A, staying in B
            // ## for time > 0, and B doesn't delay this var.

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
            rb_raise(#{declare_class RuntimeError},
              "Bad rk_level, %d!", rk_level);
            break;
            
          case 3:
            ptr = shadow->#{bufname}.ptr;
            len = shadow->#{bufname}.len;
            offset = shadow->#{offsetname};

            #{flow.translate(self, "ptr[offset]", 0, cl).join("
            ")};
            #{flow.translate(self, "ptr[offset+1]", 1, cl).join("
            ")};
            #{flow.translate(self, "ptr[offset+2]", 2, cl).join("
            ")};
            #{flow.translate(self, "ptr[offset+3]", 3, cl).join("
            ")};

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
end; end
