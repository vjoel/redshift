module RedShift; class CexprGuard
  def initialize f
    super nil, f
  end
  
  @@serial = 0
  
  def make_generator cl
    @fname = "guard_#{CGenerator.make_c_name cl.name}_#{@@serial}"
    @@serial += 1
    @inspect_str = "#{cl.name}: #{formula}"
 
    @generator = proc do
      sl = cl.shadow_library
      ssn = cl.shadow_struct_name
      cont_state_ssn = cl.cont_state_class.shadow_struct_name
      gw_ssn = Component::GuardWrapper.shadow_struct_name
      gw_cname = sl.declare_class Component::GuardWrapper
      
      sl.init_library_function.declare \
        :guard_wrapper_shadow => "#{gw_ssn} *gw_shadow",
        :guard_wrapper_value  => "VALUE gw"
      
      include_file, source_file = sl.add_file fname
      
      # We need the struct
      source_file.include(cl.shadow_library_include_file)
      
      strict = false
      
      guard = self
      source_file.define(fname).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        scope:extern
        return_type "int"
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          ContVar  *var;
        }
        setup :shadow => %{
          shadow = (#{ssn} *)comp_shdw;
          cont_state = (struct #{cont_state_ssn} *)shadow->cont_state;
        }
        declare :result => "int result"
        translation = guard.translate(self, "result", cl, 0) {|s| strict = s}
        body %{
          #{translation.join("
          ")};
          return result;
        }
      end

      sl.init_library_function.body %{
        gw = rb_funcall(#{gw_cname}, #{sl.declare_symbol :new}, 1, rb_str_new2(#{inspect_str.inspect}));
        Data_Get_Struct(gw, #{gw_ssn}, gw_shadow);
        gw_shadow->guard = &#{fname};
        gw_shadow->strict = #{strict ? "1" : "0"};
        rb_funcall(#{sl.declare_class Component}, #{sl.declare_symbol :store_wrapper}, 2,
          rb_str_new2(#{fname.inspect}), gw);
      }
      @strict = strict
    end
  end
end; end

module RedShift; class Expr
  attr_reader :type
  
  def initialize f, type = "double"
    super nil, f
    @type = type
  end
  
  @@serial = 0
  
  def make_generator cl
    @fname = "expr_#{CGenerator.make_c_name cl.name}_#{@@serial}"
    @@serial += 1
    @inspect_str = "#{cl.name}: #{formula}"
    
    @generator = proc do
      sl = cl.shadow_library
      ssn = cl.shadow_struct_name
      cont_state_ssn = cl.cont_state_class.shadow_struct_name
      ew_ssn = Component::ExprWrapper.shadow_struct_name
      ew_cname = sl.declare_class Component::ExprWrapper
      
      sl.init_library_function.declare \
        :expr_wrapper_shadow => "#{ew_ssn} *ew_shadow",
        :expr_wrapper_value  => "VALUE ew"
      
      sl.init_library_function.body %{
        ew = rb_funcall(#{ew_cname}, #{sl.declare_symbol :new}, 1, rb_str_new2(#{inspect_str.inspect}));
        Data_Get_Struct(ew, #{ew_ssn}, ew_shadow);
        ew_shadow->expr = &#{fname};
        rb_funcall(#{sl.declare_class Component}, #{sl.declare_symbol :store_wrapper}, 2,
          rb_str_new2(#{fname.inspect}), ew);
      }

      include_file, source_file = sl.add_file fname
      
      # We need the struct
      source_file.include(cl.shadow_library_include_file)
      
      expr = self
      source_file.define(fname).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        scope:extern
        return_type expr.type
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          ContVar  *var;
        }
        setup :shadow => %{
          shadow = (#{ssn} *)comp_shdw;
          cont_state = (struct #{cont_state_ssn} *)shadow->cont_state;
        }
        declare :result => "#{expr.type} result"
        translation = expr.translate(self, "result", cl, 0)
        body %{
          #{translation.join("
          ")};
          return result;
        }
      end
    end
  end
end; end

module RedShift; class ResetExpr < Expr; end; end
