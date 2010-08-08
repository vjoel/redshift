module RedShift; class CexprGuard
  def initialize f
    super nil, f
  end
  
  @@serial = Hash.new(0)
  
  def make_generator cl
    @fname = "guard_#{CGenerator.make_c_name cl.name}_#{@@serial[cl]}"
    @@serial[cl] += 1
    @inspect_str = "#{cl.name}: #{formula}"
 
    @generator = proc do
      sl = cl.shadow_library
      ssn = cl.shadow_struct_name
      cont_state_ssn = cl.cont_state_class.shadow_struct_name
      
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

      s = strict ? "STRICT" : "NONSTRICT"
      sl.init_library_function.body \
        "s_init_guard(#{fname}, #{fname.inspect}, #{inspect_str.inspect}, #{s});"
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
  
  @@serial = Hash.new(0)
  
  def make_generator cl
    @fname = "expr_#{CGenerator.make_c_name cl.name}_#{@@serial[cl]}"
    @@serial[cl] += 1
    @inspect_str = "#{cl.name}: #{formula}"
    
    @generator = proc do
      sl = cl.shadow_library
      ssn = cl.shadow_struct_name
      cont_state_ssn = cl.cont_state_class.shadow_struct_name

      sl.init_library_function.body \
        "s_init_expr(#{fname}, #{fname.inspect}, #{inspect_str.inspect});"

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
