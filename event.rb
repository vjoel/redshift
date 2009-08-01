module RedShift

class Event

	attr_reader :name

	def initialize n
		@name = n || "[Event #{id}]".intern
        
    eval <<-END
    
      def export c
        def c.#{@name}
	        super
        end
      end

      def unexport c
        def c.#{@name}
	        nil
        end
      end
      
    END
    
	end
  
  
  def attach cl
  
    unless cl.method_defined? @name
      cl.module_eval <<-END
      
        def #{@name}
          true
        end
      
      END
    end
  
  end
  
end # class Event

end # module RedShift
