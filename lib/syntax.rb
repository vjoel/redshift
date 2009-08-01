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
  class AlreadyStarted < StandardError; end
  
  def create(*args, &block)
    world.create(*args, &block)
  end
  
  def start s
    raise AlreadyStarted if state
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


module FlowSyntax

  def self.parse block
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
	
end # module FlowSyntax


module TransitionSyntax

  def self.parse block
    parser = TransitionParser.new(block)
    Transition.new parser.n, parser.g, parser.p
  end
  
  class EventBlockParser
    attr_reader :events
    
    ## should we undef some of the standard methods?

    def method_missing meth, *args, &bl
      if args.size > 1 or (args.size == 1 and bl)
        raise SyntaxError, "Too many arguments"
      end
      if bl
        @events << [meth, Component::DynamicEventValue.new(&bl)]
      elsif args.size > 0
        @events << [meth, args[0]]
      else
        @events << [meth, true]
      end
    end
    
    def initialize(block)
      @events = []
      instance_eval(&block)
    end
  end
  
  class TransitionParser
    attr_reader :n, :g, :p
    
    def initialize block
      @n = @g = nil
      @p = []
      instance_eval(&block)
    end
    
    def name n; @n = n; end
    
    def guard(*args, &block)
      guard = Component::Guard.new
      for arg in args
        case arg
        when Hash;    guard.concat arg.to_a   # { :link => :event }
        when Array;   guard << arg            # [:link, :event] ## , value] ?
        when String;  guard << CexprGuard.new(arg.strip)
        when Proc;    guard << arg            # proc { ... }
        else          raise SyntaxError
        end
      end
      guard << block if block
      if @g
        raise NotImplementedError ###
        @p << guard
      else
        @g = guard
      end
    end
    
    def action(*args, &bl)
      actions = Component::Action.new
      actions.concat args
      actions << bl if bl
      @p << actions
    end
    
    def pass
      action
    end
    
    def reset(*arg, &bl)
      raise NotImplementedError ###
    end
    
    def clear(*args)
      events = Component::Event.new
      for arg in args
        events << [arg, nil]
      end
      @p << events
    end
    
    def event(*args, &bl)
      events = Component::Event.new
      for arg in args
        case arg
        when Symbol, String
          events << [arg, true]
        when Hash
          for e, v in arg
            events << [e, v]
          end
        else
          raise SyntaxError, "unrecognized event specifier #{arg}."
        end
      end
      if bl
        eb = EventBlockParser.new(bl)
        events.concat eb.events
      end
      @p << events
    end
    
    alias events    event
    alias export    event
    alias unexport  clear
    alias watch     guard
    alias on        guard
    alias assign    reset
  
  end

end # module TransitionSyntax


def Component.flow(*states, &block)
  raise "no flows specified. Put { on same line!" unless block  
  states = Enter if states == []
  
  attach states, FlowSyntax.parse(block)
end


def Component.transition(edges = {}, &block)

  if block
    if edges == {}
      edges = {Enter => Enter}
    end
    t = TransitionSyntax.parse(block)
    exported = {}
    if t.guard
      t.guard.map! do |g|
        g.is_a?(CexprGuard) ? define_guard(g) : g
      end
    end
    for phase in t.phases
      if phase.is_a? Component::Event
        for ev_pair in phase
          export ev_pair[0]
          writer = "#{ev_pair[0]}=".intern
          ev_pair[0] = writer
          exported[writer] = ev_pair[1]
        end
      end
    end
    final = Component::Event.new
    for event, value in exported
      final << [event, false] if value
    end
    t.phases << final unless final == []
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
