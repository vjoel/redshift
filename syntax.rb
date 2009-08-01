require 'redshift/component'

# None of the defs in this file are strictly necessary to
# use RedShift, but they make your code prettier.
#
# On the other hand, I'm trying to keep all user callable
# functions in this file, and internals in other files.

module RedShift

def World.setup(&block)
  (@setup_procs ||= []) << block if block
end

class World
  def setup(&block)
    (@setup_procs ||= []) << block if block
  end
end


class Component
  def create(*args, &block)
    @world.create(*args, &block)
  end
  
  def start s
    raise RuntimeError if @state
    @start_state = s
  end
end

class << Component
  def defaults(&block)
    (@defaults_procs ||= []) << block if block
  end
  alias default defaults

  def setup(&block)
    (@setup_procs ||= []) << block if block
  end
end


def Component.state(*state_names)

  for name in state_names do
    
    if name.to_s =~ /^[A-Z]/
    
      if class_eval "defined?(#{name})"  ## avoid class_eval, string?
        if class_eval(name.to_s).is_a? State  ## const_get works?
          raise "state :#{name} already exists"
        else
          raise "state name '#{name}' is used for a constant."
        end
      else
        attach_state name
      end
      
    else
    
      raise SyntaxError, "State name #{name} does not begin with [A-Z]."
    
#      if class_variables.include "@@#{name}_state"
#        if class_eval("@@#{name}_state").is_a? State
#          raise "state :#{name} already exists"
#        else  
#          raise "state name '#{name}' is used for a class variable, @@#{name}."
#        end
#      else
#        eval <<-END
#          @@#{name}_state = State.new :#{name}, #{self.name}
#          def #{name}
#            @@#{name}_state
#          end
#        END
#      end
      
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
    
    ## This should all be more OO
    
    def algebraic(*equations)
      for equation in equations
        unless equation =~ /^\s*(\w+)\s*=\s*(.*)/m
          raise "parse error in\n\t#{equation}."
        else
          @flows << AlgebraicFlow.new($1.intern, $2.strip)
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
    
    def rk4(*equations)
      for equation in equations
        unless equation =~ /^\s*(\w+)\s*'\s*=\s*(.*)/m
          raise "parse error in\n\t#{equation}."
        else
          @flows << RK4DifferentialFlow.new($1.intern, $2.strip)
        end
      end
    end
    
    alias alg           algebraic
    alias diff          rk4
    alias differential  rk4

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
    def guard(g1=nil,&g2); @g = g1 || g2; end
    def action(a1=nil,&a2); @a = a1 || a2; end
    
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
  states = Enter if states == []
  
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
