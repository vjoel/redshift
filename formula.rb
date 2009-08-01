module RedShift

class Formula

	attr_reader :string
	
	def initialize s

		@string = s
    eval <<-END
      def self.feval c
        c.instance_eval {#{s}}
      end
    END
    # why is self needed?
    
    # Room for optimization!

	end
	
end # class Formula

end # module RedShift
