require 'option-block/option-block'
require 'pstore'

module RedShift

class ZenoError < RuntimeError; end

class World
  include OptionBlock
  include Enumerable
  
  # see also clib.rb
  
  Infinity = 1.0/0.0
  
  $RK_level = nil

  option_block_defaults \
    :name         =>  nil,
    :time_step    =>  0.1,
    :zeno_limit   =>  Infinity,
    :clock_start  =>  0.0,
    :clock_finish =>  Infinity
  
  @@count = 0

  attr_reader :components, :started
  private :components
  
  attr_reader :step_count #, :clock_start
#  attr_accessor :name, :time_step, :zeno_limit, :clock_finish

  def initialize(&block)
    
    super
    
    @components = {}

    @name          = options[:name] || "#{type} #{@@count}"
    @time_step     = options[:time_step]
    @zeno_limit    = options[:zeno_limit]
    @clock_start   = options[:clock_start]
    @clock_finish  = options[:clock_finish]
    
    @step_count = 0
    
    @@count += 1

  end
  
  def do_setup
    if @setup_procs
      for pr in @setup_procs
        instance_eval(&pr)
      end
    end
    type.do_setup self
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
    CLib.commit unless CLib.committed? or CLib.empty?
    c = component_class.new(self, &block)
    @components[c.id] = c
  end
  
  def remove c
    @components.delete c.id
  end
  
  
  def run(steps = 1)
  
    unless @started
      do_setup
      @started = true
    end
    
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
  private :step_continuous

  def step_discrete
    $RK_level = nil # need SEMAPHORE

    done = false
    zeno_counter = 0
    
    until done
    
      done = true
      each { |c| done &= c.step_discrete }
      
      zeno_counter += 1
      if zeno_counter > @zeno_limit
        raise ZenoError
      end
  
    end
  end
  private :step_discrete
  
  
  def clock
    @step_count * @time_step + @clock_start
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
  
  
  def each(&b)
    @components.each_value(&b)
  end
  
  def size
    @components.size
  end
  
  def member?(component)
    component.world == self
  end
  
  def inspect
    if @started
      sprintf "<%s: %d step%s, %s second%s, %d component%s>",
        @name,
        @step_count, ("s" if @step_count != 1),
        clock, ("s" if clock != 1),
        size, ("s" if size != 1)
    else
      sprintf "<%s: not started. Do 'run 0' to setup.>",
        @name
    end
  end
  
  
  def save filename = @name
    File.delete filename rescue
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
