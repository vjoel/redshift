module RedShift

class Event

	attr_reader :name

	def initialize n
		@name = n
    
    # how to add/remove singleton methods?
    
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
  
end # class Event

end # module RedShift
