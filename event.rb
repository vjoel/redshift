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
  
# how to add/remove singleton methods?
=begin
  def unexport c
    n = @name
    cl = class <<c
      remove_method n
    end
  end
=end
  
end # class Event

end # module RedShift
