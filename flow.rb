module RedShift

class Flow

	attr_reader :var, :formula_str
	
	def initialize v, f
		@var, @formula_str = v, f

    @getter = @var
    @setter = (@var.to_s + '=').intern
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

      def #{@getter}
        #{@formula_str}
      end

      def #{@setter} value
      end

    END
    
  end

end # class AlgebraicFlow


class CachedAlgebraicFlow < Flow

  def attach cl
    
    cl.module_eval <<-END

      def #{@getter}
        @#{@var} ||
          @#{@var} = (#{@formula_str})
      end

      def #{@setter} value
        @#{@var} = value
      end

    END
    
  end

end # class CachedAlgebraicFlow


class EulerDifferentialFlow < Flow

  def attach cl
    
    cl.module_eval <<-END

      def #{@getter}
        if $RK_level and $RK_level < 2
          @#{@var}_prev
        else
          @#{@var} ||
            @#{@var} = @#{@var}_prev + (#{@formula_str}) * @dt
        end
      end

      def #{@setter} value
        @#{@var}_prev = @#{@var}
        @#{@var} = value
      end

    END
    
  end

end # class EulerDifferentialFlow


class RK4DifferentialFlow < Flow
  
  def attach cl
    
    cl.module_eval <<-END
    
      def #{@getter}
      
        case $RK_level

        when nil
          @#{@var}

        when 0
          @#{@var}_prev

        when 1
          if not @#{@var}_F1
            save_RK_level = $RK_level
            $RK_level = 0
            @#{@var}_F1 = (#{@formula_str}) * @dt
            $RK_level = save_RK_level
          end
          @#{@var}_prev + @#{@var}_F1 / 2

        when 2
          if not @#{@var}_F2
            save_RK_level = $RK_level
            $RK_level = 1
            #{@getter} if not @#{@var}_F1
            @#{@var}_F2 = (#{@formula_str}) * @dt
            $RK_level = save_RK_level
          end
          @#{@var}_prev + @#{@var}_F2 / 2

        when 3
          if not @#{@var}_F3
            save_RK_level = $RK_level
            $RK_level = 2
            #{@getter} if not @#{@var}_F2
            @#{@var}_F3 = (#{@formula_str}) * @dt
            $RK_level = save_RK_level
          end
          @#{@var}_prev + @#{@var}_F3

        when 4
          if not @#{@var}_F4   # always true
            save_RK_level = $RK_level
            $RK_level = 3
            #{@getter} if not @#{@var}_F3
            @#{@var}_F4 = (#{@formula_str}) * @dt
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
      
      def #{@setter} value
        @#{@var}_prev = @#{@var}
        @#{@var} = value
        @#{@var}_F1 = value
        @#{@var}_F2 = value
        @#{@var}_F3 = value
        @#{@var}_F4 = value
      end
      
    END
    
  end
  
  def eval c
    c.send @getter
  end
	
end # class RK4DifferentialFlow

end # module RedShift
