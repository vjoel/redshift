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
  def link(*vars)
    h = {}
    vars.each do |var|
      case var
      when Hash
        h.update var
      else
        h[var] = Component
      end
    end
    attach_link h, false
  end
  
  def input(*var_names)
    attach_input :piecewise, var_names
  end
  
  def strict_input(*var_names)
    attach_input :strict, var_names
  end
  
  def strict(*var_names)
    var_names.each do |var_name|
      dest = find_var_superhash(var_name)
      case dest
      when nil
       raise VarTypeError, "Variable #{var_name.inspect} not found."
      when link_variables
        var_type = link_variables[var_name].first
        attach_variables(dest, :strict, [var_name], var_type)
      else
        attach_variables(dest, :strict, [var_name])
      end
    end
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
      val = instance_eval(&block)
      if val.kind_of? String and val =~ /=/
        warn "Equation appears to be missing a specifier (alg, diff, etc.):" +
          val
      end
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
      equations.each do |equation|
        unless equation =~ /^\s*(\w+)\s*'\s*=\s*(.+)/m
          raise SyntaxError, "parse error in\n\t#{equation}."
        end
        @flows << EulerDifferentialFlow.new($1.intern, $2.strip)
      end
    end
    
    def rk4(*equations)
      equations.each do |equation|
        unless equation =~ /^\s*(\w+)\s*'\s*=\s*(.+)/m
          raise SyntaxError, "parse error in\n\t#{equation}."
        end
        @flows << RK4DifferentialFlow.new($1.intern, $2.strip)
      end
    end
    
    def derive(*equations)
      opts = equations.pop
      unless opts and opts.kind_of? Hash and
             (opts[:feedback] == true or opts[:feedback] == false)
        raise SyntaxError, "Missing option: :feedback => <true|false>\n" +
          "Use 'true' when the output of this flow feeds back into another\n" +
          "derivative flow (even after a delay). Also, set <var>_init_rhs.\n"
        ## should false be the default?
        ## rename 'feedback'?
      end
      feedback = opts[:feedback]
      equations.each do |equation|
        unless equation =~ /^\s*(\w+)\s*=\s*(.+)'\s*\z/m
          raise SyntaxError, "parse error in\n\t#{equation}."
        end
        @flows << DerivativeFlow.new($1.intern, $2.strip, feedback)
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
    attr_reader :name,
      :guards, :syncs, :actions,
      :resets, :events, :posts,
      :connects
    
    def initialize block
      @name = nil
      instance_eval(&block)
    end
    
    def name(*n); n.empty? ? @name : @name = n.first; end
    
    def sync(*a)
      @syncs ||= Component::SyncPhase.new
      
      if a.last.kind_of?(Hash)
        a.concat a.pop.to_a
      end
      
      a.each do |link_name, event|
        link_names = case link_name
        when Array; link_name
        else [link_name]
        end
        
        events = case event
        when Array; event
        else [event]
        end
        
        link_names.each do |ln|
          events.each do |e|
            item = Component::SyncPhaseItem.new
            item.link_name = ln
            item.event = e
            @syncs << item
          end
        end
      end
    end
    
    def wait(*args)
      @guards ||= Component::GuardPhase.new
      
      args.each do |arg|
        case arg
        when Hash
          @guards.concat(arg.sort_by {|q,m| q.to_s}.map{|q,m| 
            Component::QMatch[q.to_sym,*m]})
                                 # { :queue => match }
        when Symbol
          @guards << Component::QMatch[arg]   # :queue
        else raise SyntaxError
        end
      end
    end
    
    def guard(*args, &block)
      @guards ||= Component::GuardPhase.new
      
      args.each do |arg|
        case arg
        when String;  @guards << arg.strip      # "<expression>"
        when Proc;    @guards << arg            # proc { ... }
        when Symbol;  @guards << arg            # :method
        when nil, true;     # no condition
        when false;   @guards << arg
        else          raise SyntaxError, "'guard #{arg.inspect}'"
        end
      end
      
      @guards << block if block
    end
    
    def action(meth = nil, &bl)
      @actions ||= Component::ActionPhase.new
      @actions << meth if meth
      @actions << bl if bl
    end
    
    def post(meth = nil, &bl)
      @posts ||= Component::PostPhase.new
      @posts << meth if meth
      @posts << bl if bl
    end
    alias after post
    
    # +h+ is a hash of :var => proc {value_expr_ruby} or "value_expr_c".
    def reset(h)
      badkeys = h.keys.reject {|k| k.is_a?(Symbol)}
      unless badkeys.empty?
        raise SyntaxError, "Keys #{badkeys.inspect} in reset must be symbols"
      end
      
      @resets ||= Component::ResetPhase.new
      @resets.value_map ||= {}
      @resets.concat [nil, nil, nil] # continuous, constant, link
      @resets.value_map.update h
    end
    
    # +h+ is a hash of :var => proc {port_expr_ruby} or [:link, :var].
    def connect(h)
      badkeys = h.keys.reject {|k| k.is_a?(Symbol)}
      unless badkeys.empty?
        raise SyntaxError, "Keys #{badkeys.inspect} in connect must be symbols"
      end
      
      @connects ||= Component::ConnectPhase.new
      @connects.concat h.entries
    end
    
    # each arg can be an event name (string or symbol), exported with value 
    # +true+, or a hash of event_name => value. In the latter case, _value_
    # can be either a Proc, string (C expr), or a literal. If you need to
    # treat a Proc or string as a literal, use the notation
    #
    #  :e => literal("str")
    #
    #  :e => literal(proc {...})
    #
    def event(*args, &bl)
      @events ||= Component::EventPhase.new
      for arg in args
        case arg
        when Symbol, String
          item = Component::EventPhaseItem.new
          item.event = arg
          item.value = true
          @events << item
        
        when Hash
          arg.sort_by {|e,v| e.to_s}.each do |e,v|
            item = Component::EventPhaseItem.new
            item.event = e
            item.value = v
            @events << item
          end
        else
          raise SyntaxError, "unrecognized event specifier #{arg}."
        end
      end
      if bl
        eb = EventBlockParser.new(bl)
        @events.concat(eb.events)
      end
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
  states = states.map {|s| must_be_state(s)}
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
# The block contains method calls to define guards, events, resets, connects,
# and action and post procs.
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
    d = must_be_state(d)

    case s
    when Array
      s.each do |t|
        t = must_be_state(t)
        warn << t if e[t]
        e[t] = d
      end

    else
      s = must_be_state(s)
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
    
    if parser.events
      parser.events.each do |event_phase_item|
        event_phase_item.index = export(event_phase_item.event)[0]
            # cache index
      end
    end
    
    trans = Transition.new(parser)
    
  else
    if edges == {}
      raise TransitionError, "No transition specified."
    else
      trans = Always
    end
  end
  
  attach edges, trans
end

def Component.must_be_state s
  return s if s.kind_of?(State)
  state = const_get(s.to_s)
rescue NameError
  raise TypeError, "Not a state: #{s.inspect}"
else
  unless state.kind_of?(State)
    raise TypeError, "Not a state: #{s.inspect}"
  end
  state
end

end
