require 'redshift/flow'
require 'redshift/cgen'

=begin

=Algebraic cflow expressions

The restrictions on the Ruby expressions allowed within cflow expressions are
intended to promote efficient code. The purpose of cflows is not rapid
development, or elegant model expression, but optimization. Inefficient
constructs should be rewritten. For instance, using a complex expression like

  radar_sensors[:front_left].target[4].range

will incur the overhead of recalculation each time the expression is evaluated,
even though the object which receives the (({range})) method call does not
change during continuous evolution. Instead, use intermediate variables. Define
an instance variable {{|@front_left_target_4|}}, updated when necessary during discrete evolution, and use the expression

  @front_left_target_4.range

The increase in efficiency comes at the cost of maintaining this new variable. Use of cflows should be considered only for mature, stable code. Premature optimization is the root of all evil.

==Syntax

The syntax of algebraic cflows is

  var = rhs
  
where rhs is a C expression except that it may also have the following additional subexpressions in Ruby syntax:

  @ivar
  @@cvar
  @ivar.method
  @@cvar.method
  method
  self.method

Note that method arguments are not allowed, nor are special methods such as []. All use of () and [] is reserved for C expressions.

==Semantic restrictions

The value of each Ruby subexpression must be Float or convertible to Float (Fixnum, String, etc.).

If a receiver.method pair occurs more than once in a cflow, the method is
called only once on that receiver per evaluation of the expression. (The
expression may be evaluated several times per time-step, depending on the
integration algorithm.) Avoid using methods with side efffects. Typically, the
methods used are accessors, which have no side effects.

==C interface

All functions in math.h are available in the expression.

==Limitations

The cflow cannot be recompiled while the simulation is running. Changes are ignored. Must reload everything to change cflows (however, can change other things without restarting).

==To do

===Soon
globals, class vars
constants: FOO, FOO.bar, FOO::BAR

===Later
differential cflows
handle calls to user-defined C functions
also C variables, declarations, includes
blocks of inline C code

===Eventually
migrate continuous state from Ruby to C
unload/reload dlls
Someday, use a true parser, which potentially could parse full ruby subexprs.

===Maybe
cascading mthods @x.foo.bar
arrays and other non-standard method calls
will static libs perform much better?

=end


module RedShift

CFlowLib = CLibrary.new 'cflows'
CFlowLib.declare '#include <math.h>'

class AlgebraicFlow_C < Flow

  def _attach cl, getter, setter
  
    cl.module_eval <<-END
      def #{setter} value
      end
    END
    
    float_fn = CFlowLib.define FloatFunction, cl, getter
    
    translation = {}
    
    c_formula = @formula.dup
    
    # check for self methods
    c_formula.gsub!(/(^|[^@$.\w])([a-z_]\w*)(?=$|[^\w.([])/) {
      $1 +  'self.' + $2
    }
    
    # handle method call with no args, returning numeric
    # assume no side effects
    c_formula.gsub!(/(@?@?[A-Za-z_]\w*)\.(\w+)/) { |expr|
      
      obj_ref   = $1
      meth_name = $2

      unless translation[expr]
        
        meth_c_name = CFlowLib.declare_symbol(meth_name)
        
        value_c_name = 'value_' + CFlowLib.make_name(expr)
        
        float_fn.declare "double    #{value_c_name};"

        case obj_ref
        when 'self'
          c_receiver = 'obj'
        when /^@\w+/
          obj_ref_c_name = CFlowLib.declare_symbol(obj_ref)
          c_receiver = "rb_ivar_get(obj, #{obj_ref_c_name})"
        when /^@@(\w+)/
          raise "Not yet implemented."
        when /\w+/
          raise "Not yet implemented."
        end

        float_fn.setup %{
          temp = rb_Float(rb_funcall(#{c_receiver}, #{meth_c_name}, 0));
          #{value_c_name} = RFLOAT(temp)->value;
        }
      
        translation[expr] = value_c_name
        
      end
      
      translation[expr]
    }
    
    # anything left with '@' in it is ivar or cvar
    c_formula.gsub!(/@?@\w+/) { |expr|
      
      unless translation[expr]
        
        attr_c_name = CFlowLib.declare_symbol(expr)
        value_c_name = 'value_' + CFlowLib.make_name(expr)

        float_fn.declare "double    #{value_c_name};"

        float_fn.setup %{\
            temp = rb_Float(rb_ivar_get(obj, #{attr_c_name}));
            #{value_c_name} = RFLOAT(temp)->value;
        }

        translation[expr] = value_c_name
        
      end
      
      translation[expr]
    }
    
    float_fn.returns c_formula
    
  end

end # class AlgebraicFlow_C

end # module RedShift
