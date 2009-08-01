require 'redshift/world'
require 'redshift/component'

module RedShift

# Register the given block to be called for instances of this class of World as
# they are instantiated (before the block passed to #new is called). The
# registered code is inherited by subclasses of this World class. The block is
# called with the world as +self+. Any number of blocks can be registered.
# (There are no per-world defaults. Use the #new block instead.)
def World.defaults(&block)
  (@defaults_procs ||= []) << block if block
end
class << World
  alias default defaults
end

# Register the given block to be called for instances of this class of World
# just before they are first run. The registered code is inherited by
# subclasses of this World class. The block is called with the world as +self+.
# Any number of blocks can be registered.
def World.setup(&block)
  (@setup_procs ||= []) << block if block
end

# Register the given block to be called for this world just before it is
# first run. The block is called with the world as +self+.
# Any number of blocks can be registered.
class World
  def setup(&block)
    (@setup_procs ||= []) << block if block
  end
end


class Component
  # Create a component in the same world as this component. This method is
  # provided for convenience. It just calls World#create.
  def create(component_class)
    if block_given?
      world.create(component_class) {|c| yield c}
    else
      world.create(component_class)
    end
  end

  # Specify the starting state +s+ of the component.
  # To be called only before the component starts running: during the default,
  # setup, or initialization block (block passed to Component#new).
  def start(s)
    raise AlreadyStarted if state
    case s
    when State
      @start_state = s
    else
      @start_state = self.class.const_get(s.to_s)
    end
  end
end

class << Component
  # Specify the starting state +s+ of the component, as a default for the class.
  def start(s)
    default {start s}
  end

  def make_init_value_map(h)
    h.inject({}) do |hh, (var, val)|
      if val.kind_of? Proc or val.kind_of? String
        raise TypeError,
          "value for '#{var}' must be literal, like #{var} => 1.23"
      end
      hh.update "#{var}=" => val
    end
  end

  # Register, for the current component class, the given block to be called at
  # the beginning of initialization of an instance.
  # The block is called with the world as +self+.
  # Any number of blocks can be registered.
  def defaults(h = nil, &block)
    (@defaults_procs ||= []) << block if block
    (@defaults_map ||= {}).update make_init_value_map(h) if h
  end
  alias default defaults

  # Register, for the current component class, the given block to be called
  # later in the initialization of an instance, after defaults and the
  # initialization block (the block passed to Component#new).
  # The block is called with the world as +self+.
  # Any number of blocks can be registered.
  def setup(h = nil, &block)
    (@setup_procs ||= []) << block if block
    (@setup_map ||= {}).update make_init_value_map(h) if h
  end
  
  # Define states in this component class, listed in +state_names+. A state
  # name should be a string or symbol beginning with [A-Z] and consisting of
  # alphanumeric (<tt>/\w/</tt>) characters. States are inherited.
  def state(*state_names)
    state_names.flatten!
    state_names.map do |state_name|
      if state_name.kind_of? Symbol
        state_name = state_name.to_s
      else
        begin
          state_name = state_name.to_str
        rescue NoMethodError
          raise SyntaxError, "Not a valid state name: #{state_name.inspect}"
        end
      end
      
      unless state_name =~ /^[A-Z]/
        raise SyntaxError,
          "State name #{state_name.inspect} does not begin with [A-Z]."
      end
      
      begin
        val = const_get(state_name)
      rescue NameError
        attach_state(state_name)
      else
        case val
        when State
          raise NameError, "state #{state_name} already exists"
        else
          raise NameError,
            "state name '#{state_name}' is already used for a constant " +
            "of type #{val.class}."
        end
      end
    end
  end
  
  def permissively_continuous(*var_names)
    attach_continuous_variables(:permissive, var_names)
  end

  def strictly_continuous(*var_names)
    attach_continuous_variables(:strict, var_names)
  end

  def continuous(*var_names)
    attach_continuous_variables(:piecewise, var_names)
  end
  alias piecewise_continuous continuous

  def permissively_constant(*var_names)
    attach_constant_variables(:permissive, var_names)
  end

  def strictly_constant(*var_names)
    attach_constant_variables(:strict, var_names)
  end

  def constant(*var_names)
    attach_constant_variables(:piecewise, var_names)
  end
  alias piecewise_constant constant

  def strict_link vars
    attach_link vars, :strict
  end

  # link :x => MyComponent, :y => :FwdRefComponent
  def link vars
    attach_link vars, false
  end
end

# Defines the flow types that can be used within a flow block.
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
    
    def algebraic(*equations)
      equations.each do |equation|
        unless equation =~ /^\s*(\w+)\s*=\s*(.+)/m
          raise SyntaxError, "parse error in\n\t#{equation}."
        end
        @flows << AlgebraicFlow.new($1.intern, $2.strip)
      end
    end
    
    def euler(*equations)
      for equation in equations
        unless equation =~ /^\s*(\w+)\s*'\s*=\s*(.+)/m
          raise SyntaxError, "parse error in\n\t#{equation}."
        end
        @flows << EulerDifferentialFlow.new($1.intern, $2.strip)
      end
    end
    
    def rk4(*equations)
      for equation in equations
        unless equation =~ /^\s*(\w+)\s*'\s*=\s*(.+)/m
          raise SyntaxError, "parse error in\n\t#{equation}."
        end
        @flows << RK4DifferentialFlow.new($1.intern, $2.strip)
      end
    end
    
    def derive(*equations)
      for equation in equations
        unless equation =~ /^\s*(\w+)\s*=\s*(.+)'\s*\z/m
          raise SyntaxError, "parse error in\n\t#{equation}."
        end
        @flows << DerivativeFlow.new($1.intern, $2.strip)
      end
    end
    
    def delay(*equations)
      opts = equations.pop
      unless opts and opts.kind_of? Hash and opts[:by]
        raise SyntaxError, "Missing delay term: :delay => <delay>"
      end
      delay_by = opts[:by]
      equations.each do |equation|
        unless equation =~ /^\s*(\w+)\s*=\s*(.+)/m
          raise SyntaxError, "parse error in\n\t#{equation}."
        end
        @flows << DelayFlow.new($1.intern, $2.strip, delay_by)
      end
    end
    
    alias alg           algebraic
    alias diff          rk4
    alias differential  rk4
  end
end

module TransitionSyntax
  def self.parse block
    TransitionParser.new(block)
  end
  
  class EventBlockParser
    attr_reader :events
    
    def method_missing event_name, *args, &bl
      if args.size > 1 or (args.size == 1 and bl)
        raise SyntaxError, "Too many arguments in event specifier"
      end
      
      item = Component::EventPhaseItem.new
      item.event = event_name
      item.value = bl || (args.size > 0 && args[0]) || true

      @events << item
    end
    
    def initialize(block)
      @events = []
      instance_eval(&block)
    end
    
    def literal val
      Component.literal val
    end
  end
  
  class TransitionParser
    attr_reader :name, :parts
    
    def initialize block
      @name = nil
      @parts = []
      instance_eval(&block)
    end
    
    def name(*n); n.empty? ? @name : @name = n.first; end
    
    def guard(*args, &block)
      guard = Component::GuardPhase.new
      
      args.each do |arg|
        case arg
        when Hash;    guard.concat(arg.sort_by {|l,e| l.to_s})
                                              # { :link => :event }
        ## need something like [:set_link, :event]
        when Array;   guard << arg            # [:link, :event] ## , value] ?
        when String;  guard << arg.strip      # "<expression>"
        when Proc;    guard << arg            # proc { ... }
        when Symbol;  guard << arg            # :method
        when nil, true;     # no condition
        when false;   guard << arg
        else          raise SyntaxError
        end
        ## should define, for each link, a TransitionParser method which returns
        ## a dummy link object that responds to #event and returns
        ## a dummy event that responds to #==(value) so that you can write
        ##
        ##   guard link_var.some_event == 123
        ##
        ## instead of
        ##
        ##  [:link_var, :some_event, 123]
      end
      
      guard << block if block
      @parts << guard
    end
    
    def action(meth = nil, &bl)
      action_phase = Component::ActionPhase.new
      action_phase << meth if meth
      action_phase << bl if bl
      @parts << action_phase
    end
    
    def post(meth = nil, &bl)
      post_phase = Component::PostPhase.new
      post_phase << meth if meth
      post_phase << bl if bl
      @parts << post_phase
    end
    alias after post
    
    # +h+ is a hash of :var => proc {value_expr_ruby} or "value_expr_c".
    def reset(h)
      badkeys = h.keys.reject {|k| k.is_a?(Symbol)}
      unless badkeys.empty?
        raise SyntaxError, "Keys #{badkeys.inspect} in reset must be symbols"
      end
      
      resets = Component::ResetPhase.new
      resets.concat [nil, nil, nil] # continuous, constant, link
      resets.value_map = h
      @parts << resets
    end
    
    # each arg can be an event name (string or symbol), exported with value 
    # +true+, or a hash of event_name => value. In the latter case, _value_
    # can be either a Proc, string (C expr), or a literal. If you need to
    # treat a Proc or string as a literal, use the notation
    #
    #  :e => literal "str"
    #
    #  :e => literal {...}
    #
    def event(*args, &bl)
      events = Component::EventPhase.new
      for arg in args
        case arg
        when Symbol, String
          item = Component::EventPhaseItem.new
          item.event = arg
          item.value = true
          events << item
        
        when Hash
          arg.sort_by {|e,v| e.to_s}.each do |e,v|
            item = Component::EventPhaseItem.new
            item.event = e
            item.value = v
            events << item
          end
        else
          raise SyntaxError, "unrecognized event specifier #{arg}."
        end
      end
      if bl
        eb = EventBlockParser.new(bl)
        events.concat(eb.events)
      end
      @parts << events
    end
    
    def literal val
      Component.literal val
    end
  end
end

# Define flows in this component class. Flows are attached to all of the
# +states+ listed. The block contains method calls such as:
#
#   alg "var = expression"
#   diff "var' = expression"
#
def Component.flow(*states, &block)
  raise "no flows specified. Put { on same line!" unless block  
  states = [Enter] if states == []
  
  attach states, FlowSyntax.parse(block)
end

# Define transitions in this component class. Transitions are attached to
# all of the +edges+ listed as <tt>src => dst</tt>. In fact, edges may
# also be given as <tt>[s0, s1, ...] => d</tt> and then the transition
# is attached to all <tt>si => d</tt>.
#
# If no edges are specified, <tt>Enter => Enter<\tt> is used.
# If no block is given, the +Always+ transition is used.
# It is a TransitionError to omit both the edges and the block.
# Specifying two outgoing transitions for the same state is warned, but
# only when this is done within the same call to this method.
#
# The block contains method calls to define guards, resets, procs, and events.
#
# The block also can have a call to the name method, which defines the name of
# the transition--this is necessary for overriding the transition in a subclass.
#
def Component.transition(edges = {}, &block)
  e = {}
  warn = []
  
  unless edges.kind_of?(Hash)
    raise SyntaxError, "transition syntax must be 'S1 => S2, S3 => S4, ...' "
  end
  
  edges.each do |s, d|
    case s
    when Array
      s.each do |t|
        warn << t if e[t]
        e[t] = d
      end
    else
      warn << s if e[s]
      e[s] = d
    end
  end
  edges = e
  warn.each do |st|
    warn "Two destinations for state #{st} at #{caller[0]}."
  end

  if block
    edges = {Enter => Enter} if edges.empty?
    parser = TransitionSyntax.parse(block)
    parts = parser.parts
    
    parts.each do |phase|
      case phase
      when Component::EventPhase
        phase.each do |event_phase_item|
          event_phase_item.index = export(event_phase_item.event)[0]
            # cache index
        end
      end
    end
    
    trans = Transition.new(parser.name,
      :guard  => combine_transition_parts(parts.grep(Component::GuardPhase)),
      :action => combine_transition_parts(parts.grep(Component::ActionPhase)),
      :event  => combine_transition_parts(parts.grep(Component::EventPhase)),
      :reset  => combine_transition_parts(parts.grep(Component::ResetPhase)),
      :post   => combine_transition_parts(parts.grep(Component::PostPhase))
    )
    
  else
    if edges == {}
      raise TransitionError, "No transition specified."
    else
      trans = Always
    end
  end
  
  attach edges, trans
end

def Component.combine_transition_parts parts
  return nil if parts.empty?
  
  result = parts[0].class.new
  
  has_value_map = defined?(result.value_map)
  if has_value_map
    result.value_map = {}
  end
  
  parts.each do |part|
    result.concat part
    if has_value_map
      result.value_map.update part.value_map
    end
  end
  result
end

end
