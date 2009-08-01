require 'option-block/option-block' #### GET RID OF THIS!!!
require 'pstore'
require 'enum/op'

module RedShift

class ZenoError < RuntimeError; end

class World
  include OptionBlock
  include Enumerable

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
  
  option_block_defaults \
    :name         =>  nil,
    :time_step    =>  0.1,
    :zeno_limit   =>  100,
    :clock_start  =>  0.0,
    :clock_finish =>  Infinity

  @@count = 0

  attr_reader :step_count
  
  def started?; @started; end
  def running?; @running; end

  def initialize(&block)
    super ## for option-block
    
    self.curr_P = []; self.curr_E = []; self.curr_R = []; self.curr_G = []
    self.next_P = []; self.next_E = []; self.next_R = []; self.next_G = []
    self.active_E = []; self.prev_active_E = []
    self.strict_sleep = []
    @components = EnumerableOperator.sum  \
      curr_P, curr_E, curr_R, curr_G,
      next_P, next_E, next_R, next_G,
      strict_sleep

    @name           = options[:name] || "#{self.class} #{@@count}"
    self.time_step  = options[:time_step]
    self.zeno_limit = options[:zeno_limit]
    @clock_start    = options[:clock_start] ## are these two really needed?
    @clock_finish   = options[:clock_finish]
    @time_unit      = options[:time_unit] || "second"
    
    @step_count = 0
    
    @@count += 1

  end
  
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

  def create(component_class, &block)
    unless component_class < Component # Component is abstract
      raise TypeError, "#{component_class} is not a Component class"
    end
    c = component_class.new(self, &block)
    curr_G << c ## problem if occurs during guard?
    c
  end
  
##  def remove c
##    components.delete c
##  end
  
  # All evolution methods untimately call step, which can be overridden.
  def step(steps = 1)
    @running = true
    
    unless @started
      do_setup
      @started = true
    end
    
    step_discrete
    steps.to_i.times do
      break if clock > @clock_finish
      @step_count += 1
      step_continuous
      step_discrete
      @running = false
      yield self if block_given?  
        ## it is client's responsibility to step_discrete at this point
        ## if vars have been changed
      @running = true
    end
    
    self
    
  ensure
    @running = false
  end
  
  def run(*args, &block)
    ## warn "World#run is deprecated -- use #step or #age"
    step(*args, &block)
  end
  
  ## maybe this shoud be called "evolve", to make it unambiguously a verb
  def age(time = 1.0, &block)
    run(time.to_f/time_step, &block)
  end

  # This method is called for each discrete step after half of the zeno_limit
  # has been exceeded.
  def step_zeno zeno_counter
    ## one useful behavior might be to shuffle guards in the active comps
    puts "Zeno step: #{zeno_counter} / #{zeno_limit}"
    ## print out the active components and their transitions if $DEBUG_ZENO?
  end
  
  ## move to C
  def clock
    @step_count * time_step + @clock_start
  end
  
  
###  def garbage_collect
###    self.components.clear
###    GC.start
###    ObjectSpace.each_object(Component) do |c|
###      if c.world == self
###        components << c
###      end
###    end
###  end
## another thing we can do: compress the various component arrays
  
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
      sprintf "<%s: %d step%s, %s #{@time_unit}%s, %d component%s>",
        @name,
        @step_count, ("s" if @step_count != 1),
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
