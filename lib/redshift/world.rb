require 'pstore'
require 'enum/op'

module RedShift

class ZenoError < RuntimeError; end

# Set zeno_level to this to turn off zeno checking.
ZENO_UNLIMITED = -1

class World
  include Enumerable
  
  class ComponentList < EnumerableOperator::Sum
    def inspect
      to_a.inspect # looks better in irb
    end
    
    def [](idx)
      to_a[idx] ## very inefficient
    end
    
    def clear
      summands.each {|list| list.clear}
    end
  end

  @subclasses = []

  class << self
    # World is not included in subclasses. This returns nil when called on subs.
    attr_reader :subclasses

    def inherited(sub)
      World.subclasses << sub
    end
  end
  
  # see comment in redshift.rb
  def self.new(*args, &block)
    RedShift.require_target     # redefines World.new
    new(*args, &block)          # which is what this line calls
  end
  
  attr_reader :components
  
  def default_options
    {
      :name         =>  "#{self.class} #{@@count}",
      :time_unit    =>  "second",
      :time_step    =>  0.1,
      :zeno_limit   =>  100,
      :clock_start  =>  0.0,
      :clock_finish =>  Infinity,
    }
  end

  @@count = 0

  attr_accessor :name, :time_unit
  
  def started?; @started; end
  def running?; @running; end

  # Can override the options using assignments in the block.
  def initialize # :yields: world
    self.curr_P = []; self.curr_E = []; self.curr_R = []; self.curr_G = []
    self.next_P = []; self.next_E = []; self.next_R = []; self.next_G = []
    self.active_E = []; self.prev_active_E = []
    self.strict_sleep = []
    @components = ComponentList.new  \
      curr_P, curr_E, curr_R, curr_G,
      next_P, next_E, next_R, next_G,
      strict_sleep

    options = default_options

    @name             = options[:name]
    @time_unit        = options[:time_unit]
    self.time_step    = options[:time_step]
    self.zeno_limit   = options[:zeno_limit]
    self.clock_start  = options[:clock_start]
    self.clock_finish = options[:clock_finish]
    
    self.step_count = 0
    
    @@count += 1

    yield self if block_given?
  end
  
  # Registers code blocks to be run just before first step of world.
  def do_setup
    self.class.do_setup self
    if @setup_procs
      for pr in @setup_procs
        instance_eval(&pr)
      end
      @setup_procs = nil # so we can serialize
    end
  end
  private :do_setup
  
  def self.do_setup instance
    superclass.do_setup instance if superclass.respond_to? :do_setup
    if @setup_procs
      for pr in @setup_procs
        instance.instance_eval(&pr)
      end
    end
  end

  def create(component_class)
    unless component_class < Component # Component is abstract
      raise TypeError, "#{component_class} is not a Component class"
    end
    
    component = 
      if block_given?
        component_class.new(self) {|c| yield c}
      else
        component_class.new(self)
      end
    
    if discrete_phase == :guard
      next_G << component
    else
      curr_G << component
    end
    
    component
  end
  
  ## is this a good idea? tests? #add ?
  def remove c
    if components.summands.any? {|list| list.delete(c)}
      raise unless c.world == self
      c.__set_world(nil)
    else
      raise "Tried to remove #{c} from #{self}, but its world is #{c.world}."
    end
  end
  
  # All evolution methods untimately call step, which can be overridden.
  # After each step, yields to block. It is the block's responsibility to
  # step_discrete at this point after changing any vars.
  def step(steps = 1)
    @running = true
    
    unless @started
      do_setup
      @started = true
    end
    
    step_discrete
    steps.to_i.times do
      break if clock > clock_finish
      self.step_count += 1
      step_continuous
      step_discrete
      @running = false
      yield self if block_given?  
      @running = true
    end
    
    self
    
  ensure
    @running = false
    ## how to continue stepping after an exception?
  end
  
  def run(*args, &block)
    ## warn "World#run is deprecated -- use #step or #age"
    step(*args, &block)
  end
  
  ## maybe this should be called "evolve", to make it unambiguously a verb
  def age(time = 1.0, &block)
    run(time.to_f/time_step, &block)
  end

  # Default implementation is to raise RedShift::ZenoError.
  def step_zeno
    raise RedShift::ZenoError, "\nExceeded zeno limit of #{zeno_limit}.\n"
  end
  
  ## is this a good idea? tests?
  def garbage_collect
    self.components.clear
    GC.start
    ObjectSpace.each_object(Component) do |c|
      components << c if c.world == self
    end
  end
  
  def each(&b)
    @components.each(&b)
  end
  
  def size
    @components.size
  end
  
  def include? component
    component.world == self
  end
  alias member? include?
  
  def inspect
    if @started
      digits = -Math.log10(time_step).floor
      digits = 0 if digits < 0
      puts "<%s: %d step%s, %.#{digits}f #{@time_unit}%s, %d component%s>"
      sprintf "<%s: %d step%s, %.#{digits}f #{@time_unit}%s, %d component%s>",
        @name,
        step_count, ("s" if step_count != 1),
        clock, ("s" if clock != 1),
        size, ("s" if size != 1)
    else
      sprintf "<%s: not started. Do 'run 0' to setup, or 'run n' to run.>",
        @name
    end
  end
  
  def save filename = @name
    raise "\nCan't save world during its run method." if @running
    File.delete(filename) rescue SystemCallError
    store = PStore.new filename
    store.transaction do
      store['world'] = self
      yield store if block_given?
    end
  end
  
  def World.open filename
    world = nil
    store = PStore.new filename
    store.transaction do
      if store.root? 'world'
        world = store['world']
        yield store if block_given?
      end
    end
    world
  end
  
end # class World

end # module RedShift
