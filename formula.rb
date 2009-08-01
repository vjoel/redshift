module RedShift

class Formula

	attr_reader :block
	
	def initialize(&b)

		@block = b

    def self.eval c
      c.instance_eval(&@block)
    end

	end
	
end # class Formula

end # module RedShift
