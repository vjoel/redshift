module RedShift

class Flow

	attr_reader :var_name, :formula_str
	
	def initialize v, f
		@var_name, @formula_str = v, f

    @getter = @var_name.intern
    @setter = (@var_name + '=').intern
	end
  
  def update c
    c.send @setter, nil
  end
  
  def eval c
    c.send @getter
  end
	
end # class Flow


class AlgebraicFlow < Flow

  def attach cl
    
    cl.module_eval <<-END

      def #{@var_name}
        #{@formula_str}
      end

      def #{@var_name}= value
      end

    END
    
  end

end # class AlgebraicFlow


class CachedAlgebraicFlow < Flow

  def attach cl
    
    cl.module_eval <<-END

      def #{@var_name}
        @#{@var_name} ||
          @#{@var_name} = (#{@formula_str})
      end

      def #{@var_name}= value
        @#{@var_name} = value
      end

    END
    
  end

end # class CachedAlgebraicFlow


class EulerDifferentialFlow < Flow

  def attach cl
    
    cl.module_eval <<-END

      def #{@var_name}
        if $RK_level and $RK_level < 2
          @#{@var_name}_prev
        else
          @#{@var_name} ||
            @#{@var_name} = @#{@var_name}_prev + (#{@formula_str}) * @dt
        end
      end

      def #{@var_name}= value
        @#{@var_name}_prev = @#{@var_name}
        @#{@var_name} = value
      end

    END
    
  end

end # class EulerDifferentialFlow


class RK4DifferentialFlow < Flow
  
  def attach cl
    
    cl.module_eval <<-END
    
      def #{@var_name}
      
        case $RK_level

        when nil
          @#{@var_name}

        when 0
          @#{@var_name}_prev

        when 1
          if not @#{@var_name}_F1
            save_RK_level = $RK_level
            $RK_level = 0
            @#{@var_name}_F1 = (#{@formula_str}) * @dt
            $RK_level = save_RK_level
          end
          @#{@var_name}_prev + @#{@var_name}_F1 / 2

        when 2
          if not @#{@var_name}_F2
            save_RK_level = $RK_level
            $RK_level = 1
            #{@var_name} if not @#{@var_name}_F1
            @#{@var_name}_F2 = (#{@formula_str}) * @dt
            $RK_level = save_RK_level
          end
          @#{@var_name}_prev + @#{@var_name}_F2 / 2

        when 3
          if not @#{@var_name}_F3
            save_RK_level = $RK_level
            $RK_level = 2
            #{@var_name} if not @#{@var_name}_F2
            @#{@var_name}_F3 = (#{@formula_str}) * @dt
            $RK_level = save_RK_level
          end
          @#{@var_name}_prev + @#{@var_name}_F3

        when 4
          if not @#{@var_name}_F4   # always true
            save_RK_level = $RK_level
            $RK_level = 3
            #{@var_name} if not @#{@var_name}_F3
            @#{@var_name}_F4 = (#{@formula_str}) * @dt
            $RK_level = save_RK_level
          end
          @#{@var_name} =
            @#{@var_name}_prev +
            (@#{@var_name}_F1     +
             @#{@var_name}_F2 * 2 +
             @#{@var_name}_F3 * 2 +
             @#{@var_name}_F4      ) / 6
          
        end            

      end
      
      def #{@var_name}= value
        @#{@var_name}_prev = @#{@var_name}
        @#{@var_name} = value
        @#{@var_name}_F1 = value
        @#{@var_name}_F2 = value
        @#{@var_name}_F3 = value
        @#{@var_name}_F4 = value
      end
      
    END
    
  end
  
  def eval c
    c.send @getter
  end
	
end # class RK4DifferentialFlow

end # module RedShift
