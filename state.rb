module RedShift

class State

	attr_reader :name, :persist_name
	
	def initialize n, context
		@name = n || "[State #{id}]".intern
    @persist_name = (context + "::" + n.to_s).intern
	end
  
  def _dump depth
    @persist_name.to_s
  end
  
  def State._load str
    pn = str.intern
    # could cache this lookup in a hash
    ObjectSpace.each_object(State) { |st|
      if st.persist_name == pn
        return st
      end
    }
  end

end # class State

end # module RedShift
