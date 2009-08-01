require 'option-block'
require 'pstore'

module RedShift

class World

  include OptionBlock
  include Enumerable
  
  Infinity = 1.0/0.0
  
  $RK_level = nil

  option_block_defaults \
    :name         =>  '"World #{@@count}"',
    :time_step    =>  0.1,
    :zeno_limit   =>  Infinity,
    :clock_start  =>  0.0,
    :clock_finish =>  Infinity
  
  @@count = 0

  attr_reader :components
  private :components
  
  attr_reader :step_count #, :clock_start
#  attr_accessor :name, :time_step, :zeno_limit, :clock_finish

  def initialize(&block)
    
    super
    
    @components = {}

    @name          = eval options[:name]
    @time_step     = options[:time_step]
    @zeno_limit    = options[:zeno_limit]
    @clock_start   = options[:clock_start]
    @clock_finish  = options[:clock_finish]
    
    @step_count = 0
    
    @@count += 1

  end

  def create(component_class, &block)
    
    FlowLib.commit unless FlowLib.committed? or FlowLib.empty?

    c = component_class.new(self, &block)
    @components[c.id] = c
  end
  
  def remove c
    @components.delete c.id
  end
  
  
  def run(steps = 1)
    
    step_discrete
    while (steps -= 1) >= 0
      break if clock > @clock_finish
      @step_count += 1
      step_continuous
      step_discrete
      yield self if block_given?
    end
    
    self
  end


  def step_continuous
  
    $RK_level = 4   # need SEMAPHORE
    each { |c| c.step_continuous @time_step }
    $RK_level = nil
   
  end


  def step_discrete
  
    $RK_level = nil # need SEMAPHORE

    done = false
    zeno_counter = 0
    
    while not done
    
      done = true
      each { |c| done &= c.step_discrete }
            
      zeno_counter += 1
      if zeno_counter > @zeno_limit
        raise "Zeno error!"
      end
  
    end
  end
  
  
  def clock
    @step_count * @time_step
  end
  
  
  def garbage_collect
    @components = {}
    GC.start
    ObjectSpace.each_object(Component) do |c|
      if c.world == self
        @components[c.id] = c
      end
    end
  end
  
  
  def each
    @components.each_value
  end
  
  def size
    @components.size
  end
  
  def inspect
    sprintf "<%s: %d step%s, %s second%s, %d component%s>",
      @name,
      @step_count, ("s" if @step_count != 1),
      clock, ("s" if clock != 1),
      size, ("s" if size != 1)
  end
  
  
  def save filename = @name
    store = PStore.new filename
    each { |c| c.discard_singleton_methods }
    store.transaction do
      store['world'] = self
      yield store if block_given?
    end
    each { |c| c.restore }
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
    if world
      world.each { |c| c.restore }
    end
    world
  end
  
end # class World

end # module RedShift
