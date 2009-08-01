require 'redshift/flow'

=begin

=cflow expressions

A cflow is a flow whose formula is a C expression involving some Ruby subexpressions. The formula is compiled to executable code before the simulation runs.

The restrictions on the Ruby expressions allowed within cflow expressions are
intended to promote efficient code. The purpose of cflows is not rapid
development, or elegant model expression, but optimization. Inefficient
constructs should be rewritten. For instance, using a complex expression like

  radar_sensors[:front_left].target[4].range

will incur the overhead of recalculation each time the expression is evaluated,
even though the object which receives the (({range})) method call does not
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

The external functions declared in the .h file will be available in cflow expressions.

* Definitions can be added to the library file itself (though large definitions that do not change from run to run are better kept externally). See the (({CGenerator})) documentation for details.

==Limitations

The cflow cannot be changed or recompiled while the simulation is running. Changes are ignored. Must reload everything to change cflows (however, can change other things without restarting). This limitation will lifted eventually.

==To do

===Soon
globals, class vars, module methods
constants: FOO, FOO.bar, FOO::BAR
scan for assignments, as in "(y = x + 1, y*y)", and define a local var.

===Later
migrate continuous state from Ruby to C
cache non-continuous values (esp. links) each timestep (or less often if we can prove that they don't change during discrete step)
continuous evolution should require just one call from Ruby code into the dynamic lib.
unload/reload dynamic libs (this is in the CGenerator to do list).

===Eventually
Someday, use a true parser, which potentially could parse full ruby subexprs.

===Maybe
cascading mthods @x.foo.bar
arrays and other non-standard method calls
will static libs perform much better?

=end


module RedShift

class Flow_C < Flow

  def translate getter_fn
  
    translation = {}
    
    c_formula = @formula.dup
    
    # check for self methods
    c_formula.gsub!(/(^|[^@$.\w])([a-z_]\w*)(?=$|[^\w.([])/) {
      $1 + 'self.' + $2
    }
    
    # handle method call with no args, returning numeric
    # assume no side effects
    c_formula.gsub!(/(@?@?[A-Za-z_]\w*)\.(\w+)/) { |expr|
      
      obj_ref   = $1
      meth_name = $2

      unless translation[expr]
        
        meth_c_name = CLib.declare_symbol meth_name
        value_c_name = "value_#{CGenerator.make_c_name expr}"

        getter_fn.declare :temp => 'VALUE temp'
        getter_fn.declare expr => "double #{value_c_name};"

        case obj_ref
        when 'self'
          c_receiver = 'self'
        when /^@\w+/
          obj_ref_c_name = CLib.declare_symbol obj_ref
          c_receiver = "rb_ivar_get(self, #{obj_ref_c_name})"
        when /^@@(\w+)/
          raise "Not yet implemented." ##
        when /\w+/
          raise "Not yet implemented." ##
        end
        
        getter_fn.setup value_c_name => %{
          temp = rb_Float(rb_funcall(#{c_receiver}, #{meth_c_name}, 0));
          #{value_c_name} = RFLOAT(temp)->value;
        }.tab(-10)
      
        translation[expr] = value_c_name
        
      end
      
      translation[expr]
    }
    
    # anything left with '@' in it is ivar or cvar
    c_formula.gsub!(/@?@\w+/) { |expr|
      
      unless translation[expr]
        
        attr_c_name = CLib.declare_symbol expr
        value_c_name = "value_#{CGenerator.make_c_name expr}"

        getter_fn.declare expr => "double #{value_c_name};"

        getter_fn.setup value_c_name => %{\
          temp = rb_Float(rb_ivar_get(self, #{attr_c_name}));
          #{value_c_name} = RFLOAT(temp)->value;
        }.tab(-10)

        translation[expr] = value_c_name
        
      end
      
      translation[expr]
    }
    
    c_formula
  
  end
  
  def define_formula_method cl, name
    fn = CLib.define_method cl, name
    c_formula = translate fn
    fn.returns "rb_float_new(#{c_formula})"
  end
    
end

## unify these implementations with those in flow.rb using mixins

class AlgebraicFlow_C < Flow_C

  def _attach cl, getter, setter
  
    define_formula_method cl, getter
    
    cl.module_eval <<-END
      def #{setter} value
      end
    END
    
  end

end # class AlgebraicFlow_C


class CachedAlgebraicFlow_C < Flow_C

  def _attach cl, getter, setter
    
    define_formula_method cl, "#{getter}_calc"
    
    cl.module_eval <<-END

      def #{getter}
        @#{@var} ||
          @#{@var} = #{getter}_calc
      end

      def #{setter} value
        @#{@var} = value
      end

    END
    
  end

end # class CachedAlgebraicFlow_C


class EulerDifferentialFlow_C < Flow_C

  def _attach cl, getter, setter
    
    define_formula_method cl, "#{getter}_calc"
    
    cl.module_eval <<-END

      def #{getter}
        if $RK_level and $RK_level < 2
          @#{@var}_prev
        else
          unless @#{@var}
            save_RK_level = $RK_level
            $RK_level = 0
            @#{@var} = @#{@var}_prev + #{getter}_calc * @dt
            $RK_level = save_RK_level
          end
          @#{@var}
        end
      end

      def #{setter} value
        @#{@var}_prev = @#{@var}
        @#{@var} = value
      end

    END
    
  end

end # class EulerDifferentialFlow_C


class RK4DifferentialFlow_C < Flow_C
  
  def _attach cl, getter, setter
    
    define_formula_method cl, "#{getter}_calc"
    
    cl.module_eval <<-END
    
      def #{getter}
      
        case $RK_level

        when nil
          @#{@var}

        when 0
          @#{@var}_prev

        when 1
          unless @#{@var}_F1
            save_RK_level = $RK_level
            $RK_level = 0
            @#{@var}_F1 = #{getter}_calc * @dt
            $RK_level = save_RK_level
          end
          @#{@var}_prev + @#{@var}_F1 / 2

        when 2
          unless @#{@var}_F2
            save_RK_level = $RK_level
            $RK_level = 1
            @#{@var}_F2 = #{getter}_calc * @dt
            #{getter} unless @#{@var}_F1
            $RK_level = save_RK_level
          end
          @#{@var}_prev + @#{@var}_F2 / 2

        when 3
          unless @#{@var}_F3
            save_RK_level = $RK_level
            $RK_level = 2
            @#{@var}_F3 = #{getter}_calc * @dt
            #{getter} unless @#{@var}_F2
            $RK_level = save_RK_level
          end
          @#{@var}_prev + @#{@var}_F3

        when 4
          unless @#{@var}_F4   # always true
            save_RK_level = $RK_level
            $RK_level = 3
            @#{@var}_F4 = #{getter}_calc * @dt
            #{getter} unless @#{@var}_F3
            $RK_level = save_RK_level
          end
          @#{@var} =
            @#{@var}_prev +
            (@#{@var}_F1     +
             @#{@var}_F2 * 2 +
             @#{@var}_F3 * 2 +
             @#{@var}_F4      ) / 6
          
        end            

      end
      
      def #{setter} value
        @#{@var}_prev = @#{@var}
        @#{@var} = value
        @#{@var}_F1 = value
        @#{@var}_F2 = value
        @#{@var}_F3 = value
        @#{@var}_F4 = value
      end
      
    END
    
  end

end # class RK4DifferentialFlow_C


end # module RedShift
