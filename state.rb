module RedShift

class State

	attr_reader :name, :flows, :transitions
	
	def initialize n, f, t
		@name, @flows, @transitions = n, f, t
	end

  def attach class_name
    for f in flows
      f.attach class_name
    end  
  end
  
end # class State

end # module RedShift
