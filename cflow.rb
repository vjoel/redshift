require 'redshift/flow.rb'
require 'mkmf'

module RedShift

class AlgebraicFlow_C < Flow

#  MathLib = %w{
#    cos sin tan acos asin atan acosh asinh atanh cosh sinh tanh
#    exp frexp ldexp log log10 expm1 log1p logb exp2 log2 pow
#    sqrt hypot cbrt ceil fabs floor fmod nearbyint round trunc
#    remquo lrint llrint lround llround copysign erf erfc tgamma
#    lgamma rint next_after next_toward remainder scalb scalbn
#    scalbln ilogb fdim fmax fmin fma
#  } # from /usr/include/tgmath.h

  def _attach cl, getter, setter
  
    cl.module_eval <<-END
      def #{setter} value
      end
    END
    
#    filename = /(.*)\..*/.match(__FILE__)[1]
#    filename += '.c'

    libname = "#{cl}_#{getter}"
#    getter_name = "get_#{cl}_#{getter}"
    
    translation = {}
    
    c_formula = @formula.dup
    
    # eventually, turn a parser loose on this thing to
    # get an AST and generate a C expression from that
    
    c_declarations    = ""
    c_initialization  = ""  # done once
    c_setup           = ""  # done each time
    
    c_code = [c_declarations, c_initialization, c_setup]
    
#    # check for math library calls and self methods
#    c_formula.gsub!(/(^|[^@])([A-Za-z_]\w*)/) {
#      $1 + 
#        if MathLib.member? $2
#          $2
#        elsif $2 == 'abs'
#          'fabs'
#        else
#          'self.' + $2
#        end
#    }
    
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
        
        meth_c_name = c_declare_symbol(c_code, meth_name)
        
        value_c_name = 'value_' + make_c_name(expr)
        
        c_declarations << %{\
          double    #{value_c_name};
        }

        case obj_ref
        when 'self'
          c_receiver = 'obj'
        when /^@\w+/
          obj_ref_c_name = c_declare_symbol c_code, obj_ref
          c_receiver = "rb_ivar_get(obj, #{obj_ref_c_name})"
        when /^@@(\w+)/
          raise "Not yet implemented."
        when /\w+/
          raise "Not yet implemented."
        end

        c_setup << %{
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
        
        attr_c_name = c_declare_symbol(c_code, expr)
        value_c_name = 'value_' + make_c_name(expr)

        c_declarations << %{\
            double    #{value_c_name};
        }

        c_setup << %{\
            temp = rb_Float(rb_ivar_get(obj, #{attr_c_name}));
            #{value_c_name} = RFLOAT(temp)->value;
        }

        translation[expr] = value_c_name
        
      end
      
      translation[expr]
    }
    
    tab = proc { |n, str|
      if n >= 0
        str.gsub(/^/, ' ' * n)
      else
        str.gsub(/^ {0,#{-n}}/, "")
      end
    }
    tabto = proc { |n, str|
      str =~ /^( *)\S/
      tab[n - $1.length, str]
    }
    taballto = proc { |n, str|
      str.gsub(/^ */, ' ' * n)
    }
    
    c_output = tabto[0, %{\
      #include <ruby.h>
      #include <math.h>

      static VALUE
      #{getter}(obj)
        VALUE obj;
      {
        static int first_time = 1;
        VALUE temp;
        double result;
        \
        #{taballto[8, "\n" + c_declarations]}
        if (first_time) {\
          #{taballto[10, "\n" + c_initialization]}
          first_time = 0;
        }\
        #{taballto[8, "\n" + c_setup]}\

        result = rb_float_new(#{c_formula});
        return result;
      }

      Init_#{libname}(void)
      {
        VALUE class;
        class = rb_eval_string("#{cl.name}");
        rb_define_method(class, "#{getter}", #{getter}, 0);
      }
    }]
      
    File.open(libname + '.c', 'w') { |file|
      file.print c_output
    }
    
    create_makefile(libname)
    system 'make'
    require libname
    
    # Eventually, do this with temp files, unless debug flag set
    # avoid stepping on or crudding up local dir
    # and check mod times to avoid unnecessary work
    # and do everything lazily, when first invoked,
    # so that all defs can be collected in a data struct
    # and written to one file
    
  end
  
protected

  def c_declare_symbol c_code, symbol_name
    c_declarations, c_initialization, c_setup = c_code
    symbol_c_name = 'id_' + make_c_name(symbol_name)
    unless c_declarations =~ /\b#{symbol_c_name}\b/
      c_declarations << %{\
        static ID #{symbol_c_name};
      }
      c_initialization << %{\
        #{symbol_c_name} = rb_intern("#{symbol_name}");
      }
    end
    symbol_c_name
  end
      
  def make_c_name expr
    # we use a single '_' to indicate our subs
    c_name = expr.gsub(/_/, '__')
    c_name.gsub!(/@/, 'attr_')
    c_name.gsub!(/\./, '_dot_')
    c_name
  end

end # class AlgebraicFlow_C

end # module RedShift
