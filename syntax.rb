require 'redshift/component'
require 'redshift/cflow'

module RedShift

class Component

  def create(component_class, &block)
    @world.create(component_class, &block)
  end

  @@defaults_proc = {}
  @@setup_proc = {}

end

def Component.defaults(&block)

  @@defaults_proc[name.intern] = block
  
  module_eval <<-END
    def defaults
      super
      pr = @@defaults_proc[:#{name}]
      if pr
        instance_eval(&pr)
      end
    end
  END

end

def Component.setup(&block)

  @@setup_proc[name.intern] = block
  
  module_eval <<-END
    def setup
      super
      pr = @@setup_proc[:#{name}]
      if pr
        instance_eval(&pr)
      end
    end
  END

end


def Component.state(*state_names)

  for name in state_names do
    
    if name.to_s =~ /^[A-Z]/
    
      if const_defined?(name)
        RedShift.warn "state :#{name} already exists. Not redefined."
      else
        const_set name, State.new(name, self.name)
      end
      
    else
    
      if class_variables.include "@@#{name}_state"
        RedShift.warn "state :#{name} already exists. Not redefined."
      else
        eval <<-END
          @@#{name}_state = State.new :#{name}, #{self.name}
          def #{name}
            @@#{name}_state
          end
        END
      end
      
    end
  end

end


class Flow

  def Flow.parse block
    FlowParser.new(block).flows
  end
  
  class FlowParser
    attr_reader :flows
    
    def initialize block
      @flows = []
      instance_eval(&block)
    end
    
    def algebraic(*equations)
      for equation in equations
        unless equation =~ /^\s*(\w+)\s*=\s*(.*)/m
          raise "parse error in\n\t#{equation}."
        else
          @flows << AlgebraicFlow.new($1.intern, $2.strip)
        end
      end
    end
    
    def algebraic_c(*equations)
      for equation in equations
        unless equation =~ /^\s*(\w+)\s*=\s*(.*)/m
          raise "parse error in\n\t#{equation}."
        else
          @flows << AlgebraicFlow_C.new($1.intern, $2.strip)
        end
      end
    end
    
    def cached_algebraic(*equations)
      for equation in equations
        unless equation =~ /^\s*(\w+)\s*=\s*(.*)/m
          raise "parse error in\n\t#{equation}."
        else
          @flows << CachedAlgebraicFlow.new($1.intern, $2.strip)
        end
      end
    end
    
    def euler(*equations)
      for equation in equations
        unless equation =~ /^\s*(\w+)\s*'\s*=\s*(.*)/m
          raise "parse error in\n\t#{equation}."
        else
          @flows << EulerDifferentialFlow.new($1.intern, $2.strip)
        end
      end
    end
    
    def differential(*equations)
      for equation in equations
        unless equation =~ /^\s*(\w+)\s*'\s*=\s*(.*)/m
          raise "parse error in\n\t#{equation}."
        else
          @flows << RK4DifferentialFlow.new($1.intern, $2.strip)
        end
      end
    end
    
    alias alg         algebraic
    alias cached      cached_algebraic
    alias runge_kutta differential
    alias diff        differential

  end
	
end # class Flow


class Transition

  def Transition.parse block
    parser = TransitionParser.new(block)
    Transition.new parser.n, parser.g, parser.es, parser.a
  end
  
  class TransitionParser
    attr_reader :n, :g, :es, :a
    
    def initialize block
      @n = @g = @a = nil
      @es = []
      instance_eval(&block)
    end
    
    def name n;     @n = n; end
    def guard(&g);  @g = g; end
    def action(&a); @a = a; end
    
    def events(*es)
      for e in es
        case e
        when Symbol
          @es << Event.new(e)
        when String
          @es << Event.new(e.intern)
        when Event
          @es << e
        else
          raise "unknown event specifier #{e}, use Symbol, String, or Event."
        end
      end
    end
    
    alias event events
    alias watch guard
    alias on guard
  
  end

end # class Transition


def Component.flow(*states, &block)

  raise "no flows specified. Put { on same line!" unless block
  
  if states == []
    states = Enter
  end
  
  attach states, Flow.parse(block)

end


def Component.transition(edges = {}, &block)

  if block
    if edges == {}
      edges = {Enter => Enter}
    end
    t = Transition.parse(block)
  else
    if edges == {}
      raise "No transition specified."
    else
      t = Always
    end
  end
  
  attach edges, t

end

end # module RedShift
