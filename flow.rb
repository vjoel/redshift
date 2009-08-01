module RedShift

class Flow

	attr_reader :var, :formula
	
	def initialize v, f
		@var, @formula = v, f
    
    @var_equals = "#{@var}=".intern

    @direct_getter = "__direct__#{@var}".intern
    @direct_setter = "__direct__#{@var}=".intern
	end
  
  
  def getter state
    "__state__#{state.name}__#{@var}".intern
  end
  
  def setter state
    "__state__#{state.name}__#{@var}=".intern
  end
  private :getter, :setter
  
  def attach cl, state
    
    cl.module_eval <<-END
    
      unless method_defined? :#{@direct_getter}
        def #{@direct_getter}
          @#{@var}
        end

        def #{@direct_setter} value
          @#{@var} = value
        end
      end
      
    END
    
    begin
    
      _attach cl, getter(state), setter(state)
      
      old_flow = Component.cached_flows(cl, state)[@var]
        # cache has not been updated yet
        # hack, hack!
      
      if old_flow
        ObjectSpace.each_object(cl) do |c|
          if c.state == state and
             c.flows.include? old_flow
                # watch out for override in subclass!
                # c.flows has not been recalculated yet
            arrive c, state
          end
        end
      end
      
    rescue SyntaxError
      $stderr.print "Flow:\n\tvar is '#{@var}',\n\tformula is '#{@formula}'\n"
      raise
      
    end
    
  end
  
  def arrive c, state
    
    c.instance_eval <<-END
      alias :#{@var} :#{getter(state)}
      alias :#{@var_equals} :#{setter(state)}
    END
    
  end
  
  def depart c, state
  
    c.instance_eval <<-END
      alias :#{@var} :#{@direct_getter}
      alias :#{@var_equals} :#{@direct_setter}
    END
    
  end
  
  def update c
    c.send @var_equals, nil
  end
  
  def eval c
    c.send @var
  end
  
end # class Flow


class AlgebraicFlow < Flow

  def _attach cl, getter, setter
    
    cl.module_eval <<-END

      def #{getter}
        #{@formula}
      end

      def #{setter} value
      end

    END
    
  end

end # class AlgebraicFlow


class CachedAlgebraicFlow < Flow

  def _attach cl, getter, setter
    
    cl.module_eval <<-END

      def #{getter}
        @#{@var} ||
          @#{@var} = (#{@formula})
      end

      def #{setter} value
        @#{@var} = value
      end

    END
    
  end

end # class CachedAlgebraicFlow


class EulerDifferentialFlow < Flow

  def _attach cl, getter, setter
    
    cl.module_eval <<-END

      def #{getter}
        if $RK_level and $RK_level < 2
          @#{@var}_prev
        else
          unless @#{@var}
            save_RK_level = $RK_level
            $RK_level = 0
            @#{@var} = @#{@var}_prev + (#{@formula}) * @dt
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

end # class EulerDifferentialFlow


class RK4DifferentialFlow < Flow
  
  def _attach cl, getter, setter
    
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
            @#{@var}_F1 = (#{@formula}) * @dt
            $RK_level = save_RK_level
          end
          @#{@var}_prev + @#{@var}_F1 / 2

        when 2
          unless @#{@var}_F2
            save_RK_level = $RK_level
            $RK_level = 1
            @#{@var}_F2 = (#{@formula}) * @dt
            #{getter} unless @#{@var}_F1
            $RK_level = save_RK_level
          end
          @#{@var}_prev + @#{@var}_F2 / 2

        when 3
          unless @#{@var}_F3
            save_RK_level = $RK_level
            $RK_level = 2
            @#{@var}_F3 = (#{@formula}) * @dt
            #{getter} unless @#{@var}_F2
            $RK_level = save_RK_level
          end
          @#{@var}_prev + @#{@var}_F3

        when 4
          unless @#{@var}_F4   # always true
            save_RK_level = $RK_level
            $RK_level = 3
            @#{@var}_F4 = (#{@formula}) * @dt
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
	
end # class RK4DifferentialFlow

end # module RedShift
