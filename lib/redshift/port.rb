module RedShift; class Component
  class Port
    attr_reader :component, :variable, :connectable
    
    def initialize component, variable, connectable
      @component, @variable, @connectable = component, variable, connectable
    end
    
    # Convenience method to get source port rather than component/var pair.
    def source
      source_component && source_component.port(source_variable)
    end
    
    def check_connectable
      unless connectable
        raise TypeError, "Not an input: #{variable} in #{component.class}"
      end
    end
    
    def connect port
      check_connectable
      component.connect(variable, port && port.component, port && port.variable)
    end
    
    def <<(other)
      connect(other)
      return other
    end
    
    def >>(other)
      other.connect(self)
      return other
    end
    
    def disconnect
      connect nil
    end
    
    def source_component
      check_connectable
      component.source_component_for(variable)
    end
    
    def source_variable
      check_connectable
      component.source_variable_for(variable)
    end
    
    def value
      component.send variable
    end
  end
end; end
