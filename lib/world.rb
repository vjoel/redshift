require 'option-block/option-block'
require 'pstore'
require 'enum/op'

module RedShift

class ZenoError < RuntimeError; end

class World
  include OptionBlock
  include Enumerable
  include CShadow
    shadow_library RedShift.library
    shadow_library_file "world"
  
  attr_reader :components
  
# The indeterminacy of hash ordering causes the .c file to get written
# when not strictly necessary. Until deferred compile works, break
# the def up.
#  shadow_attr_accessor \
#    :curr_A => Array, :curr_R => Array, :curr_E => Array, :curr_G => Array,
#    :next_A => Array, :next_R => Array, :next_E => Array, :next_G => Array
  shadow_attr_accessor :curr_A => Array
  shadow_attr_accessor :curr_R => Array
  shadow_attr_accessor :curr_E => Array
  shadow_attr_accessor :curr_G => Array
  shadow_attr_accessor :next_A => Array
  shadow_attr_accessor :next_R => Array
  shadow_attr_accessor :next_E => Array
  shadow_attr_accessor :next_G => Array
  protected \
    :curr_A=, :curr_R=, :curr_E=, :curr_G=,
    :next_A=, :next_R=, :next_E=, :next_G=
  
  option_block_defaults \
    :name         =>  nil,
    :time_step    =>  0.1,
###    :zeno_limit   =>  -1, ## Infinity,
    :clock_start  =>  0.0,
    :clock_finish =>  Infinity
  
  @@count = 0

  attr_reader :step_count
  
  def started?; @started; end
  def running?; @running; end

  shadow_attr_writer   :time_step    => "double   time_step"
  shadow_attr_accessor :zeno_limit   => "long     zeno_limit"
  protected :time_step=
  ### what about dynamically changing time step?
  
  def self.new(*args, &block)
    RedShift.library.commit # redefines self.new  
    new(*args, &block)
  end
  
  def initialize(&block)
    super ##??
    
    self.curr_A = []; self.curr_R = []; self.curr_E = []; self.curr_G = []
    self.next_A = []; self.next_R = []; self.next_E = []; self.next_G = []
    @components = EnumerableOperator.sum  \
      curr_A, curr_R, curr_E, curr_G,
      next_A, next_R, next_E, next_G

    @name           = options[:name] || "#{type} #{@@count}"
    self.time_step  = options[:time_step]
###    self.zeno_limit = options[:zeno_limit]
    self.zeno_limit = -1
    @clock_start    = options[:clock_start]
    @clock_finish   = options[:clock_finish]
    
    @step_count = 0
    
    @@count += 1

  end
  
  def do_setup
    type.do_setup self
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
    c = component_class.new(self, &block)
    curr_G << c ## problem if occurs during guard?
    c
  end
  
##  def remove c
##    components.delete c
##  end
  
  def run(steps = 1)
    @running = true
    
    unless @started
      do_setup
      @started = true
    end
    
    step_discrete
    while (steps -= 1) >= 0 ## faster to use '(1..steps).each do' ?
      break if clock > @clock_finish
      @step_count += 1
      step_continuous
      step_discrete
      @running = false
      yield self if block_given?  
        ## it is client's responsibility to step_discrete at this point
        ## if vars have been changed
      @running = true
    end ### put this whole loop in C
    
    self
    
  ensure
    @running = false
  end

  def step_zeno zeno_counter
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
      sprintf "<%s: %d step%s, %s second%s, %d component%s>",
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
    File.delete filename rescue SystemCallError
    store = PStore.new filename
    store.transaction do
      store['world'] = self
      yield store if block_given?
    end
  end
  
  def World.open filename
    RedShift.library.commit unless RedShift.library.committed?
      # defines World.alloc methods
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
