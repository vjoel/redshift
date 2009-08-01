require 'redshift/flow.rb'

module RedShift

# to do
# cascading? @x.foo.bar
# arrays and other non-standard method calls
# constants: FOO
# avoid duplicates in decl/init/setup
# handle repeated calls: 'foo = x.bar + sqrt(x.bar)'
# serial number for result_#{meth_name}
# generated .c file should #include <math.h>
# make sure to use -O for compiler
# long term -- will static libs perform much better?

    # to do: globals, class vars,
    #  "ob.meth1.meth2", "obj[i]", etc. <-- No: should use aux var instead.
    # add sequence number to locals to prevent conflicts
    # handle duplicates: 'x = y * y + y'
    
class AlgebraicFlow_C < Flow

  MathLib = %w{
    cos sin tan acos asin atan acosh asinh atanh cosh sinh tanh
    exp frexp ldexp log log10 expm1 log1p logb exp2 log2 pow
    sqrt hypot cbrt ceil fabs floor fmod nearbyint round trunc
    remquo lrint llrint lround llround copysign erf erfc tgamma
    lgamma rint next_after next_toward remainder scalb scalbn
    scalbln ilogb fdim fmax fmin fma
  } # from /usr/include/tgmath.h

  def _attach cl, getter, setter
  
    cl.module_eval <<-END
      def #{setter} value
      end
    END
    
#    filename = /(.*)\..*/.match(__FILE__)[1]
#    filename += '.c'

    libname = "#{cl}_#{getter}"
    getter_name = "get_#{cl}_#{getter}"
    
    redundant = {}
    
    c_formula = @formula.dup
    
    # eventually, turn a parser loose on this thing to
    # get an AST and generate a C expression from that
    
    c_declarations    = ""
    c_initialization  = ""  # done once
    c_setup           = ""  # done each time
    
    # check for math library calls and self methods
    c_formula.gsub!(/(^|[^@])([A-Za-z_]\w*)/) {
      $1 + 
        if MathLib.member? $2
          $2
        elsif $2 == 'abs'
          'fabs'
        else
          'self.' + $2
        end
    }
    
    # handle method call with no args, returning numeric
    c_formula.gsub!(/(@?@?[A-Za-z_]\w*)\.(\w+)/) { |expr|
      
      obj_ref   = $1
      meth_name = $2

      unless redundant[expr]
        
        redundant[expr] = true
        
        c_declarations += %{
            static ID id_#{meth_name};
            VALUE     receiver_#{meth_name};
            double    result_#{meth_name};
        }

        c_initialization += %{
              id_#{meth_name} = rb_intern("#{meth_name}");
        }

        case obj_ref
        when 'self'
          c_receiver = 'obj'
        when /^@(\w+)/
          c_declarations += %{
            static ID idattr_#{$1};
          }
          c_initialization += %{
              idattr_#{$1} = rb_intern("#{obj_ref}");
          }
          c_receiver = "rb_ivar_get(obj, idattr_#{$1})"
        when /^@@(\w+)/
          raise "Not yet implemented."
        when /\w+/
          raise "Not yet implemented."
        end

        c_setup += %{
            temp = rb_Float(rb_funcall(#{c_receiver}, id_#{meth_name}, 0));
            result_#{meth_name} = RFLOAT(temp)->value;
        }
      
      end
      
      "result_#{meth_name}"
    }
    
    # handle request to get value of float-valued ivar
    c_formula.gsub!(/(^|[^@])@(\w+)/) {
      
      pre = $1
      attr_name = $2
      
      c_declarations += %{
          static ID idattr_#{attr_name};
          double    ivar_#{attr_name};
      }
      
      c_initialization += %{
            idattr_#{attr_name} = rb_intern("@#{attr_name}");
      }
      
      c_setup += %{
          temp = rb_Float(rb_ivar_get(obj, idattr_#{attr_name}));
          ivar_#{attr_name} = RFLOAT(temp)->value;
      }
      
      pre + "ivar_#{attr_name}"
    }
    
    File.open(libname + '.c', 'w') { |file|
      file.write %{

        #include <ruby.h>
        #include <math.h>

        Init_#{libname}
        {
          VALUE class;
          class = rb_eval_string("#{cl.name}");
          rb_define_method(class, "#{getter_name}", #{getter_name}, 0);
        }

        static VALUE
        #{getter_name}(obj)
          VALUE obj;
        {
          static int first_time = 1;
          VALUE temp;
          #{c_declarations}
          if (first_time) {
            #{c_initialization}
            first_time = 0;
          }
          #{c_setup}
          return rb_float_new(#{c_formula});
        }

      }
    }
    
    # if MANIFEST doesn't exist, create it and put filename in it
    
    # make ext files, if they don't already exist
    # run make
    # load the dyn lib
    
    # Eventually, do this with temp files, unless debug flag set
    # and check mod times to avoid unnecessary work
    # and do everything lazily, when first invoked,
    # so that all defs can be collected in a data struct
    # and written to one file
    
  end

end # class AlgebraicFlow_C

end # module RedShift
