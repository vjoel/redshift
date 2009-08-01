require 'redshift/flow'

=begin

Flow syntax:

C expressions (operators, math functions, user-defined C functions, constants) with variables as follows:

var       -- shadow attribute of the 'self' object

link.var  -- shadow attribute of another ruby object
             link is a shadow attr of self


=end

=begin

=cflow expressions

A cflow is a flow whose formula is a C expression involving some Ruby subexpressions. The formula is compiled to executable code before the simulation runs.

The restrictions on the Ruby expressions allowed within cflow expressions are
intended to promote efficient code. The purpose of cflows is not rapid
development, or elegant model expression, but optimization. Inefficient
constructs should be rewritten. For instance, using a complex expression like

  radar_sensors[:front_left].target[4].range

will incur the overhead of recalculation each time the expression is evaluated,
even though the object which receives the (({range})) method call cannot
change during continuous evolution. Instead, use intermediate variables. Define
an instance variable ((|@front_left_target_4|)), updated when necessary during discrete evolution, and use the expression

  @front_left_target_4.range

The increase in efficiency comes at the cost of maintaining this new variable. Use of cflows should be considered only for mature, stable code. Premature optimization is the root of all evil.

==Syntax

The syntax of algebraic and differential cflows is

  var = rhs
  var' = rhs

where rhs is a C expression, except that it may also have the following additional subexpressions in Ruby syntax:

  @ivar
  @@cvar
  @ivar.method
  @@cvar.method
  method
  self.method

The last two are equivalent. Method arguments are not allowed, nor are special methods such as []. All use of () and [] is reserved for C expressions.

Note that C has a comma operator which allows a pair (and therefore any sequence) of expressions to be evaluated, returning the value of the last one. However, on-the-fly assignments are not yet supported (see the to do list), so this isn't useful.

==Semantic restrictions

The value of each Ruby subexpression must be Float or convertible to Float (Fixnum, String, etc.).

If a receiver.method pair occurs more than once in a cflow, the method is
called only once on that receiver per evaluation of the expression. (The
expression as a whole may be evaluated several times per time-step, depending
on the integration algorithm.) Using methods that have side efffects with
caution. Typical methods used are accessors, which have no side effects.

==C interface

All functions in math.h are available in the expression. The library is geberated with (({CGenerator})) (in file ((*cgen.rb*))). This is a very flexible tool:

* To statically link to other C files, simply place them in the same dir as the library (you may need to create the dir yourself unless the RedShift program has already run). To include a .h file, simply do the following somewhere in your Ruby code:

  RedShift::CLib.include "my-file.h"
  
or
  
  RedShift::CLib.include "<lib-file.h>"

The external functions declared in the .h file will be available in cflow expressions.

* Definitions can be added to the library file itself (though large definitions that do not change from run to run are better kept externally). See the (({CGenerator})) documentation for details.

==Limitations

The cflow cannot be changed or recompiled while the simulation is running. Changes are ignored. Must reload everything to change cflows (however, can change other things without restarting). This limitation will lifted eventually.

==To do

* globals (store these in a unique GlobalData object)

* class vars (store these in the TypeData instance)

* constants: FOO, FOO.bar, FOO::BAR (as above)

* link1.link2.var, etc.

* WARN when variable name conflics with ruby method.

=end


module RedShift

class Flow

  attr_reader :var, :formula
  
  def initialize v, f
    @var, @formula = v, f
  end
  
  def attach cl, state
    cont_var = cl.continuous(@var)[0]
    cl.type_data_class.add_flow [state, cont_var] => flow_wrapper(cl, state)
  end
  
  def translate flow_fn, result_var, rk_level, cl
    translation = {}
    setup = []    ## should use accumulator
    
    c_formula = @formula.dup
    
    re = /(?:([A-Za-z_]\w*)\.)?([A-Za-z_]\w*)(?!\w*\s*[?(])/
    
    c_formula.gsub! re do |expr|
      unless translation[expr]
        link, var = $1, $2
        if link
          # link.var  ==>  shadow->link->cont_state->var.value_n
          link_cname = "link_#{link}"
          link_cs_cname = "link_#{link}_cs"
          unless translation[link]
            # link  ==>  shadow->link (but don't sub this into expr)
            translation[link] = link_cname # just so we know we've seen it
            
            link_type = cl.link_type link.intern
            raise "No such link, #{link}" unless link_type

            link_type_ssn = link_type.shadow_struct.name
            link_cs_ssn = link_type.cont_state_class.shadow_struct.name
            
            flow_fn.declare link_cname => %{
              #{link_type_ssn} *#{link_cname};
              #{link_cs_ssn} *#{link_cs_cname};
            }

            exc = flow_fn.declare_class(RuntimeError)
            msg = "Link #{link} is nil in component %s"
            insp = flow_fn.declare_symbol(:inspect)
            str = "STR2CSTR(rb_funcall(shadow->self, #{insp}, 0))"
            flow_fn.setup link_cname => %{
              #{link_cname} = shadow->#{link};
              if (!#{link_cname})
                rb_raise(#{exc}, #{msg.inspect}, #{str});
              #{link_cs_cname} = (#{link_cs_ssn} *)#{link_cname}->cont_state;
            } ## some redundancy
          end
          var_cname = "#{link_cname}__dot__#{var}"
          sh_cname = link_cname
          cs_cname = link_cs_cname
        else
          # var ==> cont_state->var.value_n
          var_cname = "var_#{var}"
          sh_cname = "shadow"
          cs_cname = "cont_state"
        end
        flow_fn.declare var_cname => "double    #{var_cname}"
        flow_fn.setup var_cname => %{
          if (#{cs_cname}->#{var}.algebraic) {
            if (#{cs_cname}->#{var}.rk_level < rk_level ||
               (rk_level == 0 && #{cs_cname}->#{var}.d_tick != d_tick))
              (*#{cs_cname}->#{var}.flow)(#{sh_cname});
          }
        }
        setup << %{
          #{var_cname} = #{cs_cname}->#{var}.value_#{rk_level};
        }.tabto(0).split("\n")
        translation[expr] = var_cname
      end
      translation[expr]
    end
    
    # handle the case of link_var in "x' = link_var ? link_var.y : z"
###    c_formula.gsub! /([A-Za-z_]\w*)(?=\s*\?)/ do |expr|
###      translation[expr] = "link_" + $1
      ### Hack, hack.
      ### does not handle case where link_var appears without '.', as in
      ### "x' = link_var ? 0 : 1"
###    end
    
    setup << "#{result_var} = #{c_formula}"
  end
    
end

class CircularDefinitionError < StandardError; end

class AlgebraicFlow < Flow

  def flow_wrapper cl, state
    var_name = @var
    flow = self
    flow_name = "flow_#{CGenerator.make_c_name cl.name}_#{var_name}_#{state}"
    
    Component::FlowWrapper.make_subclass flow_name do
      ssn = cl.shadow_struct.name
      cont_state_ssn = cl.cont_state_class.shadow_struct.name
      
      shadow_library_source_file.define(flow_name).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          ContVar  *var;
        }
        setup :shadow => %{
          shadow = (#{ssn} *)comp_shdw;
          cont_state = (#{cont_state_ssn} *)shadow->cont_state;
          var = &cont_state->#{var_name};
          assert(var->algebraic);
          if (var->nested)
            rb_raise(#{declare_class CircularDefinitionError},
              "\\nCircularity in algebraic formula: #{var_name}");
          var->nested = 1;
        }
        body %{
          
          switch (rk_level) {
          case 0:
            #{flow.translate(self, "var->value_0", 0, cl).join("
            ")};
            var->d_tick = d_tick;
            break;
          case 1:
            #{flow.translate(self, "var->value_1", 1, cl).join("
            ")};
            var->rk_level = rk_level;
            break;
          case 2:
            #{flow.translate(self, "var->value_2", 2, cl).join("
            ")};
            var->rk_level = rk_level;
            break;
          case 3:
            #{flow.translate(self, "var->value_3", 3, cl).join("
            ")};
            var->rk_level = rk_level;
            break;
          default:
            rb_raise(#{declare_class RuntimeError},
              "Bad rk_level, %d!", rk_level);
          }
          
          var->nested = 0;
        }
      end # Case 0 applies during discrete update.
          # alg flows are lazy

      define_method :calc_function_pointer do
        body "shadow->flow = &#{flow_name}", "shadow->algebraic = 1"
      end
    end
  end

end # class AlgebraicFlow


class EulerDifferentialFlow < Flow

  def flow_wrapper cl, state
    var_name = @var
    flow = self
    
    flow_name = "flow_#{CGenerator.make_c_name cl.name}_#{var_name}_#{state}"
    
    Component::FlowWrapper.make_subclass flow_name do
      ssn = cl.shadow_struct.name
      cont_state_ssn = cl.cont_state_class.shadow_struct.name
      
      shadow_library_source_file.define(flow_name).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          ContVar  *var;
          double    ddt_#{var_name};
        }
        setup :shadow => %{
          if (rk_level == 2) {
            shadow = (#{ssn} *)comp_shdw;
            cont_state = (#{cont_state_ssn} *)shadow->cont_state;
            var = &cont_state->#{var_name};
          }
        }
        setup :rk_level => %{
          rk_level -= 2;
        } # has to happen before referenced alg flows are called in other setups
        body %{
          if (rk_level == 0) {
            #{flow.translate(self, "ddt_#{var_name}", 0, cl).join("
            ")};

            var->value_0 = var->value_3 = var->value_2 =
              var->value_0 + time_step * ddt_#{var_name};
            
            var->rk_level = 4;
          }
          rk_level += 2;
        }
      end ## setting var->rk_level=4 saves two function calls
          ## but there's still the wasted rk_level=1 function call...
          ## this might be a reason to handle euler steps at rk_level=1
      define_method :calc_function_pointer do
        body "shadow->flow = &#{flow_name}"
      end
    end
  end

end # class EulerDifferentialFlow


class RK4DifferentialFlow < Flow
  
  def flow_wrapper cl, state
    var_name = @var
    flow = self
    
    flow_name = "flow_#{CGenerator.make_c_name cl.name}_#{var_name}_#{state}"
    
    Component::FlowWrapper.make_subclass flow_name do
      ssn = cl.shadow_struct.name
      cont_state_ssn = cl.cont_state_class.shadow_struct.name
      
      shadow_library_source_file.define(flow_name).instance_eval do
        arguments "ComponentShadow *comp_shdw"
        declare :shadow => %{
          struct #{ssn} *shadow;
          struct #{cont_state_ssn} *cont_state;
          ContVar  *var;
          double    ddt_#{var_name};
          double    value_4;
        }
        setup :shadow => %{
          shadow = (#{ssn} *)comp_shdw;
          cont_state = (#{cont_state_ssn} *)shadow->cont_state;
          var = &cont_state->#{var_name};
        }
        setup :rk_level => %{
          rk_level--;
        } # has to happen before referenced alg flows are called in other setups
        body %{
          switch (rk_level) {
          case 0:
            #{flow.translate(self, "ddt_#{var_name}", 0, cl).join("
            ")};
            var->value_1 = var->value_0 + ddt_#{var_name} * time_step / 2;
            break;

          case 1:
            #{flow.translate(self, "ddt_#{var_name}", 1, cl).join("
            ")};
            var->value_2 = var->value_0 + ddt_#{var_name} * time_step / 2;
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
              "Bad rk_level, %d!", rk_level);
          }
          
          rk_level++;
          var->rk_level = rk_level;
        }
      end

      define_method :calc_function_pointer do
        body "shadow->flow = &#{flow_name}"
      end
    end
  end

end # class RK4DifferentialFlow


end # module RedShift
