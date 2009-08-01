module RedShift

require 'input.rb'

class Component

	attr_reader :world
	attr_reader :state
	attr_reader :event		# {:event_name => value, ...}
	attr_reader :enabled_transition

	@inits			# key is var_name, value is init_spec
	
	@@input_specs	# hash mapping subclasses of Component to instances of InputSpecSet

public

	def initialize(world, initializer_hash = {}, &block)
		@world = world
		
		# do all default initialization provided by the variable definitions,
		# except for keys in the hash (** TO DO **)
		
		input_specs

		initializer_hash.each { |key, value|

			eval "@#{key.to_s} = #{value}"

				# Slow but effective. What we really
				# need is 'set :var-name, value'

		}
		
		if block
			instance_eval(&block)
		end

	end
	
	def enable t
		@enabled_transition = t
		@event = t.event
	end
	
	def disable
		@enabled_transition = nil
		@event = {}
	end
	
	# each input is :name or [:name, init-value]
	# semantic problem: not evaluated at component-creation time
	def Component.input *vars
	
		h = @@input_specs[self.name]
	
		vars.each { |var_spec|
		
			if var_spec.type == Symbol
			
				attr_reader var_spec
				
			else
			
				unless var_spec.type == Array
			 		raise "Must be symbol or array: #{var_spec}"
				end
			
				unless var_spec.length == 2
					raise "Array must be of length 2: #{var_spec}"
				end
				
				unless var_spec[0].type == Symbol
					raise "Array must begin with symbol: #{var_spec}"
				end
				
				attr_reader var_spec[0]
				
				inits[var_spec[0]] = var_spec[1]
			
			end
			
		}
	
	end
		
end # class Component

end # module RedShift
